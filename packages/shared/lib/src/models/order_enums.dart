enum OrderChannel {
  delivery,
  inStore;

  static OrderChannel fromJson(String value) => switch (value) {
        'delivery' => OrderChannel.delivery,
        'in_store' => OrderChannel.inStore,
        _ => throw ArgumentError('Unknown order_channel: $value'),
      };

  String toJson() => switch (this) {
        OrderChannel.delivery => 'delivery',
        OrderChannel.inStore => 'in_store',
      };
}

/// An order's state.
///
/// Three phases on the happy path: **confirmed -> out for delivery ->
/// delivered**. There used to be a "preparing" step between the first
/// two; it told the customer nothing they could act on and gave the shop
/// an extra button to press, so it is gone. The database enum still
/// carries the value -- Postgres has no DROP VALUE -- and [fromJson]
/// folds it into [confirmed] so any historical row still reads.
enum OrderStatus {
  pendingPayment,
  scheduled,
  confirmed,
  outForDelivery,
  delivered,
  cancelled,

  /// Someone outside the delivery area asking to be served anyway, and
  /// the shop's refusal. Both exist in the database enum; without them
  /// here, fromJson threw on a perfectly ordinary row.
  requested,
  declined;

  static OrderStatus fromJson(String value) => switch (value) {
        'pending_payment' => OrderStatus.pendingPayment,
        'scheduled' => OrderStatus.scheduled,
        'confirmed' => OrderStatus.confirmed,
        // Retired phase, folded forward rather than rejected.
        'preparing' => OrderStatus.confirmed,
        'out_for_delivery' => OrderStatus.outForDelivery,
        'delivered' => OrderStatus.delivered,
        'cancelled' => OrderStatus.cancelled,
        'requested' => OrderStatus.requested,
        'declined' => OrderStatus.declined,
        _ => throw ArgumentError('Unknown order_status: $value'),
      };

  String toJson() => switch (this) {
        OrderStatus.pendingPayment => 'pending_payment',
        OrderStatus.scheduled => 'scheduled',
        OrderStatus.confirmed => 'confirmed',
        OrderStatus.outForDelivery => 'out_for_delivery',
        OrderStatus.delivered => 'delivered',
        OrderStatus.cancelled => 'cancelled',
        OrderStatus.requested => 'requested',
        OrderStatus.declined => 'declined',
      };

  /// Customer-facing wording, used on order cards and status chips in
  /// both apps.
  String get label => switch (this) {
        OrderStatus.pendingPayment => 'Payment pending',
        OrderStatus.scheduled => 'Scheduled',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.outForDelivery => 'Out for delivery',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.requested => 'Requested',
        OrderStatus.declined => 'Declined',
      };

  /// The step staff advance this order to next, or null if it has
  /// reached an end state. Scheduled orders can be confirmed early --
  /// the cron job would do it at the scheduled time anyway.
  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pendingPayment => OrderStatus.confirmed,
        OrderStatus.scheduled => OrderStatus.confirmed,
        OrderStatus.requested => OrderStatus.confirmed,
        OrderStatus.confirmed => OrderStatus.outForDelivery,
        OrderStatus.outForDelivery => OrderStatus.delivered,
        OrderStatus.delivered ||
        OrderStatus.cancelled ||
        OrderStatus.declined =>
          null,
      };

  /// The label on the button that performs [nextStatus].
  String? get advanceLabel => switch (this) {
        OrderStatus.pendingPayment ||
        OrderStatus.scheduled ||
        OrderStatus.requested =>
          'Confirm Order',
        OrderStatus.confirmed => 'Send Out for Delivery',
        OrderStatus.outForDelivery => 'Mark Delivered',
        OrderStatus.delivered ||
        OrderStatus.cancelled ||
        OrderStatus.declined =>
          null,
      };

  /// Still needs staff attention -- i.e. has not reached an end state.
  bool get isOpen =>
      this != OrderStatus.delivered &&
      this != OrderStatus.cancelled &&
      this != OrderStatus.declined;

  /// The happy-path sequence an order moves through. Excludes
  /// [cancelled] (an exit, not a step) and [pendingPayment]/[scheduled]
  /// (entry states that both resolve into [confirmed]).
  static const progressSteps = [
    OrderStatus.confirmed,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];
}

enum PaymentStatus {
  pending,
  paid,
  failed,
  refunded;

  static PaymentStatus fromJson(String value) =>
      PaymentStatus.values.firstWhere((e) => e.name == value);

  String toJson() => name;
}
