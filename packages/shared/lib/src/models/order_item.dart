import 'package:equatable/equatable.dart';

class OrderItem extends Equatable {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final DateTime createdAt;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        productId: json['product_id'] as String,
        quantity: json['quantity'] as int,
        unitPrice: (json['unit_price'] as num).toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, orderId, productId, quantity, unitPrice, subtotal, createdAt];
}
