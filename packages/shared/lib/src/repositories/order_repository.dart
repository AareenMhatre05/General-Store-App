import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/order.dart';
import '../models/order_enums.dart';
import '../models/order_item.dart';
import '../supabase/supabase_bootstrap.dart';

class OrderLineInput {
  const OrderLineInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  final String productId;
  final int quantity;
  final double unitPrice;

  Map<String, dynamic> toJson(String orderId) => {
        'order_id': orderId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

/// An order line joined to the product it refers to, so order history
/// can show "2 x Amul Butter" rather than a bare product id.
class OrderItemDetail {
  const OrderItemDetail({
    required this.item,
    required this.productName,
    required this.productUnit,
  });

  final OrderItem item;
  final String productName;
  final String productUnit;
}

/// Revenue, cost and profit for a period.
class SalesProfit {
  const SalesProfit({
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.costedItems,
    required this.uncostedItems,
  });

  final double revenue;
  final double cost;
  final double profit;
  final int costedItems;
  final int uncostedItems;

  /// Profit as a share of revenue.
  double get marginPercent => revenue <= 0 ? 0 : (profit / revenue) * 100;

  /// True when some sold items have no supplier cost recorded, which
  /// makes [profit] an overstatement rather than a fact.
  bool get isIncomplete => uncostedItems > 0;
}

/// An order write that the database refused, carrying the server's own
/// explanation. Screens show [message] rather than a generic "try
/// again", which otherwise sends people round the same loop with
/// nothing new to go on. Keeps Postgrest's exception type inside this
/// layer, per the rule in Architecture.md.
class OrderException implements Exception {
  const OrderException(this.message);

  final String message;

  @override
  String toString() => 'OrderException: $message';
}

/// An order joined to the customer and delivery address behind it --
/// what staff need to actually fulfil it. Customers never need this
/// (they know who and where they are), so it lives apart from [Order].
class StaffOrder {
  const StaffOrder({
    required this.order,
    this.customerName,
    this.customerPhone,
    this.addressLines,
  });

  final Order order;
  final String? customerName;
  final String? customerPhone;
  final List<String>? addressLines;

  String get customerLabel => customerName?.trim().isNotEmpty == true
      ? customerName!
      : (order.channel == OrderChannel.inStore ? 'Walk-in customer' : 'Customer');

  String? get addressSummary => addressLines?.isEmpty ?? true ? null : addressLines!.join(', ');
}

/// Order creation/status changes. distance_meters, delivery_fee_amount,
/// subtotal_amount and total_amount are all computed server-side (see
/// the order_totals_and_delivery_fee migration) -- this repository
/// never sends them, only the inputs a client actually controls.
class OrderRepository {
  /// For customers this returns only their own orders; for staff/owner
  /// it returns every order (RLS enforces the difference server-side --
  /// the query is identical either way). Staff-side callers should
  /// prefer [getAllOrders], a same-query alias that reads better there.
  /// Capped deliberately. An unbounded select is the realistic way this
  /// database gets overloaded -- not a flood of requests, but one request
  /// asking for everything once the table is large. 200 is far more than
  /// any screen shows.
  Future<List<Order>> getMyOrders({int limit = 200}) async {
    final rows = await supabase
        .from('orders')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Order.fromJson).toList();
  }

  Future<List<Order>> getAllOrders() => getMyOrders();

  Future<Order> getOrder(String orderId) async {
    final row = await supabase.from('orders').select().eq('id', orderId).single();
    return Order.fromJson(row);
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final rows = await supabase
        .from('order_items')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    return rows.map(OrderItem.fromJson).toList();
  }

  /// Same rows as [getOrderItems], with each line's product name/unit
  /// embedded. A product that has since been deleted falls back to a
  /// placeholder name rather than dropping the line from the order.
  Future<List<OrderItemDetail>> getOrderItemsDetailed(String orderId) async {
    final rows = await supabase
        .from('order_items')
        .select('*, products(name, unit)')
        .eq('order_id', orderId)
        .order('created_at');
    return rows.map((row) {
      final product = row['products'] as Map<String, dynamic>?;
      return OrderItemDetail(
        item: OrderItem.fromJson(row),
        productName: product?['name'] as String? ?? 'Removed item',
        productUnit: product?['unit'] as String? ?? '',
      );
    }).toList();
  }

  /// Item counts for a batch of orders in one round trip, so an order
  /// list can show "3 items" without a query per row.
  Future<Map<String, int>> getItemCounts(List<String> orderIds) async {
    if (orderIds.isEmpty) return {};
    final rows = await supabase
        .from('order_items')
        .select('order_id, quantity')
        .inFilter('order_id', orderIds);

    final counts = <String, int>{};
    for (final row in rows) {
      final orderId = row['order_id'] as String;
      counts[orderId] = (counts[orderId] ?? 0) + (row['quantity'] as int);
    }
    return counts;
  }

  /// Places a delivery order for the signed-in customer: creates the
  /// order row, then its line items (each insert automatically deducts
  /// stock and recalculates the order's totals), then returns the
  /// order with its final server-computed totals.
  Future<Order> placeDeliveryOrder({
    required String deliveryAddressId,
    required List<OrderLineInput> items,
    DateTime? scheduledFor,
    String? notes,
  }) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) {
      throw StateError('placeDeliveryOrder called while signed out');
    }

    try {
      final orderRow = await supabase
          .from('orders')
          .insert({
            // Required, and not defaulted by the column: the orders RLS
            // insert policy is `customer_id = auth.uid()`, and the table's
            // CHECK constraint refuses a delivery order without it. Sending
            // it is safe -- RLS rejects any value but the caller's own id.
            'customer_id': customerId,
            'channel': OrderChannel.delivery.toJson(),
            'status': (scheduledFor != null
                    ? OrderStatus.scheduled
                    : OrderStatus.pendingPayment)
                .toJson(),
            'delivery_address_id': deliveryAddressId,
            'scheduled_for': scheduledFor?.toIso8601String(),
            'notes': notes,
          })
          .select()
          .single();

      final orderId = orderRow['id'] as String;

      await supabase
          .from('order_items')
          .insert(items.map((item) => item.toJson(orderId)).toList());

      final finalRow =
          await supabase.from('orders').select().eq('id', orderId).single();
      return Order.fromJson(finalRow);
    } on PostgrestException catch (e) {
      throw OrderException(e.message);
    }
  }

  /// Records an in-store sale (staff app). No customer account, no
  /// delivery address -- rung up and handed over immediately.
  Future<Order> createInStoreSale({
    required List<OrderLineInput> items,
    String? notes,
  }) async {
    final orderRow = await supabase
        .from('orders')
        .insert({
          // Deliberately no customer_id: a counter sale belongs to the
          // shop, not to the staff member ringing it up.
          'channel': OrderChannel.inStore.toJson(),
          'status': OrderStatus.delivered.toJson(),
          'notes': notes,
        })
        .select()
        .single();

    final orderId = orderRow['id'] as String;

    await supabase
        .from('order_items')
        .insert(items.map((item) => item.toJson(orderId)).toList());

    final finalRow =
        await supabase.from('orders').select().eq('id', orderId).single();
    return Order.fromJson(finalRow);
  }

  /// Profit for a period, from the staff-only `sales_profit_between`
  /// function. [uncostedItems] counts lines whose product has no cost
  /// recorded -- those contribute their full revenue to profit, which
  /// overstates it, so the UI warns when the count is non-zero.
  Future<SalesProfit> getProfitBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await supabase.rpc('sales_profit_between', params: {
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
    });
    final row = (rows as List).isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from((rows).first as Map);
    return SalesProfit(
      revenue: (row['revenue'] as num?)?.toDouble() ?? 0,
      cost: (row['cost'] as num?)?.toDouble() ?? 0,
      profit: (row['profit'] as num?)?.toDouble() ?? 0,
      costedItems: (row['costed_items'] as num?)?.toInt() ?? 0,
      uncostedItems: (row['uncosted_items'] as num?)?.toInt() ?? 0,
    );
  }

  /// Replaces the lines of an existing sale. Database triggers put the
  /// stock back for removed or reduced lines and take it out again for
  /// added ones, so the ledger stays truthful without the client doing
  /// any arithmetic (see the order_item_edit_restock migration).
  Future<void> replaceOrderItems({
    required String orderId,
    required List<OrderLineInput> items,
  }) async {
    try {
      await supabase.from('order_items').delete().eq('order_id', orderId);
      if (items.isNotEmpty) {
        await supabase
            .from('order_items')
            .insert(items.map((item) => item.toJson(orderId)).toList());
      }
    } on PostgrestException catch (e) {
      throw OrderException(e.message);
    }
  }

  /// Staff/owner only (enforced by RLS) -- advance an order through its
  /// lifecycle, or cancel it (which triggers an automatic restock).
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await supabase
        .from('orders')
        .update({'status': status.toJson()})
        .eq('id', orderId);
  }

  /// Staff/owner only. Used for cash-on-delivery, where payment is
  /// collected in person rather than through Razorpay.
  Future<void> updatePaymentStatus(String orderId, PaymentStatus status) async {
    await supabase
        .from('orders')
        .update({'payment_status': status.toJson()})
        .eq('id', orderId);
  }

  /// Staff view of orders, with the customer and delivery address
  /// embedded. All filters are optional and applied server-side, so the
  /// same method backs both the fulfilment queue and the sales report.
  ///
  /// [createdBefore] is exclusive -- pass the start of the day *after*
  /// the range you want.
  Future<List<StaffOrder>> getOrdersForStaff({
    OrderStatus? status,
    OrderChannel? channel,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    var query = supabase.from('orders').select(
          '*, profiles(full_name, phone), '
          'addresses(label, line1, line2, city, pincode)',
        );

    if (status != null) query = query.eq('status', status.toJson());
    if (channel != null) query = query.eq('channel', channel.toJson());
    if (createdAfter != null) {
      query = query.gte('created_at', createdAfter.toIso8601String());
    }
    if (createdBefore != null) {
      query = query.lt('created_at', createdBefore.toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false).limit(500);

    return rows.map((row) {
      final profile = row['profiles'] as Map<String, dynamic>?;
      final address = row['addresses'] as Map<String, dynamic>?;
      return StaffOrder(
        order: Order.fromJson(row),
        customerName: profile?['full_name'] as String?,
        customerPhone: profile?['phone'] as String?,
        addressLines: address == null
            ? null
            : [
                for (final key in ['label', 'line1', 'line2', 'city', 'pincode'])
                  if ((address[key] as String?)?.trim().isNotEmpty ?? false)
                    (address[key] as String).trim(),
              ],
      );
    }).toList();
  }

  Future<StaffOrder?> getOrderForStaff(String orderId) async {
    final rows = await supabase
        .from('orders')
        .select(
          '*, profiles(full_name, phone), '
          'addresses(label, line1, line2, city, pincode)',
        )
        .eq('id', orderId)
        .limit(1);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final profile = row['profiles'] as Map<String, dynamic>?;
    final address = row['addresses'] as Map<String, dynamic>?;
    return StaffOrder(
      order: Order.fromJson(row),
      customerName: profile?['full_name'] as String?,
      customerPhone: profile?['phone'] as String?,
      addressLines: address == null
          ? null
          : [
              for (final key in ['label', 'line1', 'line2', 'city', 'pincode'])
                if ((address[key] as String?)?.trim().isNotEmpty ?? false)
                  (address[key] as String).trim(),
            ],
    );
  }
}
