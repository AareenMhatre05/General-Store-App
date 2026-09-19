import 'package:equatable/equatable.dart';

import 'user_role.dart';

class ProductInquiry extends Equatable {
  const ProductInquiry({
    required this.id,
    required this.customerId,
    this.productId,
    required this.senderRole,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String? productId;
  final UserRole senderRole;
  final String message;
  final DateTime createdAt;

  factory ProductInquiry.fromJson(Map<String, dynamic> json) => ProductInquiry(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        productId: json['product_id'] as String?,
        senderRole: UserRole.fromJson(json['sender_role'] as String),
        message: json['message'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, customerId, productId, senderRole, message, createdAt];
}
