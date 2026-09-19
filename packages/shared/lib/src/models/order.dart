import 'package:equatable/equatable.dart';

import 'order_enums.dart';

class Order extends Equatable {
  const Order({
    required this.id,
    this.customerId,
    required this.channel,
    required this.status,
    this.deliveryAddressId,
    this.distanceMeters,
    required this.subtotalAmount,
    required this.deliveryFeeAmount,
    required this.totalAmount,
    this.scheduledFor,
    required this.paymentStatus,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? customerId;
  final OrderChannel channel;
  final OrderStatus status;
  final String? deliveryAddressId;
  final double? distanceMeters;
  final double subtotalAmount;
  final double deliveryFeeAmount;
  final double totalAmount;
  final DateTime? scheduledFor;
  final PaymentStatus paymentStatus;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        customerId: json['customer_id'] as String?,
        channel: OrderChannel.fromJson(json['channel'] as String),
        status: OrderStatus.fromJson(json['status'] as String),
        deliveryAddressId: json['delivery_address_id'] as String?,
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        subtotalAmount: (json['subtotal_amount'] as num).toDouble(),
        deliveryFeeAmount: (json['delivery_fee_amount'] as num).toDouble(),
        totalAmount: (json['total_amount'] as num).toDouble(),
        scheduledFor: json['scheduled_for'] == null
            ? null
            : DateTime.parse(json['scheduled_for'] as String),
        paymentStatus: PaymentStatus.fromJson(json['payment_status'] as String),
        razorpayOrderId: json['razorpay_order_id'] as String?,
        razorpayPaymentId: json['razorpay_payment_id'] as String?,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        customerId,
        channel,
        status,
        deliveryAddressId,
        distanceMeters,
        subtotalAmount,
        deliveryFeeAmount,
        totalAmount,
        scheduledFor,
        paymentStatus,
        razorpayOrderId,
        razorpayPaymentId,
        notes,
        createdAt,
        updatedAt,
      ];
}
