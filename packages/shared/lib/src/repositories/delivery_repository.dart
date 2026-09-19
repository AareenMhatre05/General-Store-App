import '../models/address.dart';
import '../models/order_enums.dart';
import '../models/user_role.dart';
import '../supabase/supabase_bootstrap.dart';

/// Somebody who can be given a drop.
class DeliveryPartner {
  const DeliveryPartner({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;
}

/// One drop, from the delivery partner's side: what to take, where, and
/// who to hand it to.
///
/// Everything here is scoped by RLS to orders actually assigned to the
/// caller -- a partner cannot list the shop's other orders, nor the
/// customers attached to them.
class DeliveryJob {
  const DeliveryJob({
    required this.assignmentId,
    required this.orderId,
    required this.status,
    required this.totalAmount,
    required this.placedAt,
    required this.customerName,
    required this.paymentStatus,
    this.customerPhone,
    this.address,
    this.notes,
    this.pickedUpAt,
    this.deliveredAt,
  });

  final String assignmentId;
  final String orderId;
  final OrderStatus status;
  final double totalAmount;
  final DateTime placedAt;
  final String customerName;
  final PaymentStatus paymentStatus;
  final String? customerPhone;
  final Address? address;
  final String? notes;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  bool get isDone => deliveredAt != null || status == OrderStatus.delivered;

  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// Short reference the shop and the customer can both say out loud.
  String get reference =>
      '${placedAt.day.toString().padLeft(2, '0')}${placedAt.month.toString().padLeft(2, '0')}'
      '-${orderId.replaceAll('-', '').substring(0, 4).toUpperCase()}';
}

/// Where a delivery partner is, and when they were last heard from.
class PartnerPosition {
  const PartnerPosition({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final double? accuracyMeters;

  /// A position from ten minutes ago is not a live one -- the phone may
  /// have lost signal or the app may have been closed. Worth saying so
  /// rather than drawing a stale dot as though it were current.
  bool get isStale =>
      DateTime.now().toUtc().difference(updatedAt.toUtc()) >
      const Duration(minutes: 3);
}

/// Assigning drops, and carrying them out.
class DeliveryRepository {
  /// Everyone with the delivery role. Staff/owner only in practice --
  /// RLS on profiles will return nothing useful to anyone else.
  Future<List<DeliveryPartner>> getPartners() async {
    final rows = await supabase
        .from('profiles')
        .select('id, full_name, phone')
        .eq('role', 'delivery')
        .limit(100);
    return rows
        .map((row) => DeliveryPartner(
              id: row['id'] as String,
              name: (row['full_name'] as String?)?.trim().isNotEmpty == true
                  ? row['full_name'] as String
                  : 'Delivery partner',
              phone: row['phone'] as String?,
            ))
        .toList();
  }

  /// Who, if anyone, is carrying this order.
  Future<DeliveryPartner?> getAssignee(String orderId) async {
    final row = await supabase
        .from('delivery_assignments')
        .select('delivery_user_id, profiles!delivery_assignments_delivery_user_id_fkey(full_name, phone)')
        .eq('order_id', orderId)
        .maybeSingle();
    if (row == null) return null;
    final profile = row['profiles'] as Map<String, dynamic>?;
    return DeliveryPartner(
      id: row['delivery_user_id'] as String,
      name: (profile?['full_name'] as String?)?.trim().isNotEmpty == true
          ? profile!['full_name'] as String
          : 'Delivery partner',
      phone: profile?['phone'] as String?,
    );
  }

  /// One order has one carrier, so re-assigning replaces rather than
  /// stacks. Staff and owner only, enforced by RLS.
  Future<void> assign({
    required String orderId,
    required String deliveryUserId,
  }) async {
    await supabase.from('delivery_assignments').delete().eq('order_id', orderId);
    await supabase.from('delivery_assignments').insert({
      'order_id': orderId,
      'delivery_user_id': deliveryUserId,
    });
  }

  Future<void> unassign(String orderId) async {
    await supabase.from('delivery_assignments').delete().eq('order_id', orderId);
  }

  /// The signed-in partner's drops, newest first.
  Future<List<DeliveryJob>> getMyDeliveries() async {
    final rows = await supabase
        .from('delivery_assignments')
        .select(
          'id, order_id, picked_up_at, delivered_at, '
          'orders!inner(id, status, payment_status, total_amount, '
          'created_at, notes, customer_id, delivery_address_id)',
        )
        .order('created_at', ascending: false)
        .limit(100);

    final jobs = <DeliveryJob>[];
    for (final row in rows) {
      final order = row['orders'] as Map<String, dynamic>;

      // Fetched separately rather than embedded: both come through
      // policies of their own, and a failure to read one should not
      // cost the whole list.
      Address? address;
      final addressId = order['delivery_address_id'] as String?;
      if (addressId != null) {
        final addressRow = await supabase
            .from('addresses_with_coords')
            .select()
            .eq('id', addressId)
            .maybeSingle();
        if (addressRow != null) address = Address.fromJson(addressRow);
      }

      final profileRow = await supabase
          .from('profiles')
          .select('full_name, phone')
          .eq('id', order['customer_id'] as String)
          .maybeSingle();

      jobs.add(DeliveryJob(
        assignmentId: row['id'] as String,
        orderId: order['id'] as String,
        status: OrderStatus.fromJson(order['status'] as String),
        paymentStatus:
            PaymentStatus.fromJson(order['payment_status'] as String),
        totalAmount: (order['total_amount'] as num).toDouble(),
        placedAt: DateTime.parse(order['created_at'] as String),
        notes: order['notes'] as String?,
        customerName: (profileRow?['full_name'] as String?)?.trim().isNotEmpty == true
            ? profileRow!['full_name'] as String
            : 'Customer',
        customerPhone: profileRow?['phone'] as String?,
        address: address,
        pickedUpAt: row['picked_up_at'] == null
            ? null
            : DateTime.parse(row['picked_up_at'] as String),
        deliveredAt: row['delivered_at'] == null
            ? null
            : DateTime.parse(row['delivered_at'] as String),
      ));
    }
    return jobs;
  }

  /// Collected from the shop: the order goes out for delivery.
  Future<void> markPickedUp(DeliveryJob job) async {
    await supabase
        .from('delivery_assignments')
        .update({'picked_up_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', job.assignmentId);
    await supabase
        .from('orders')
        .update({'status': OrderStatus.outForDelivery.toJson()})
        .eq('id', job.orderId);
  }

  Future<void> markDelivered(DeliveryJob job) async {
    await supabase
        .from('delivery_assignments')
        .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', job.assignmentId);
    await supabase
        .from('orders')
        .update({'status': OrderStatus.delivered.toJson()})
        .eq('id', job.orderId);
  }

  /// Where the partner is now, for the customer's live tracking.
  ///
  /// One row per partner, overwritten -- this is a current position, not
  /// a movement history. Keeping a trail of where somebody has been all
  /// day is a different thing to ask for, and nobody asked for it.
  Future<void> pushLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('delivery_locations').upsert({
      'delivery_user_id': userId,
      'location': 'SRID=4326;POINT($longitude $latitude)',
      'accuracy_meters': accuracyMeters,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'delivery_user_id');
  }

  /// Cash taken at the door. Everything here is cash on delivery, so
  /// the courier is the only person who knows this happened.
  Future<void> markPaid(DeliveryJob job) async {
    await supabase
        .from('orders')
        .update({'payment_status': PaymentStatus.paid.toJson()})
        .eq('id', job.orderId);
  }

  /// Where the partner carrying the caller's live order currently is.
  ///
  /// No filter is needed: RLS on `delivery_locations` only exposes the
  /// partner attached to one of the caller's own in-flight orders, so a
  /// bare select returns their row or nothing at all. Staff and owner
  /// see every partner, hence the optional [deliveryUserId].
  Future<PartnerPosition?> getPartnerPosition({String? deliveryUserId}) async {
    var query = supabase.from('delivery_locations_with_coords').select();
    if (deliveryUserId != null) {
      query = query.eq('delivery_user_id', deliveryUserId);
    }
    final rows = await query.limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    if (latitude == null || longitude == null) return null;
    return PartnerPosition(
      latitude: (latitude as num).toDouble(),
      longitude: (longitude as num).toDouble(),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      accuracyMeters: (row['accuracy_meters'] as num?)?.toDouble(),
    );
  }

  /// Whether this account is a delivery partner, for screens that are
  /// shown to one role only.
  static bool isPartner(UserRole? role) => role == UserRole.delivery;
}
