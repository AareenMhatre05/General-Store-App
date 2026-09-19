import 'package:equatable/equatable.dart';

enum InventoryAdjustmentReason {
  restock,
  sale,
  cancellation,
  correction,
  wastage;

  static InventoryAdjustmentReason fromJson(String value) =>
      InventoryAdjustmentReason.values.firstWhere((e) => e.name == value);

  String toJson() => name;
}

class InventoryAdjustment extends Equatable {
  const InventoryAdjustment({
    required this.id,
    required this.productId,
    required this.changeQuantity,
    required this.reason,
    this.referenceOrderId,
    this.note,
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final int changeQuantity;
  final InventoryAdjustmentReason reason;
  final String? referenceOrderId;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;

  factory InventoryAdjustment.fromJson(Map<String, dynamic> json) =>
      InventoryAdjustment(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        changeQuantity: json['change_quantity'] as int,
        reason: InventoryAdjustmentReason.fromJson(json['reason'] as String),
        referenceOrderId: json['reference_order_id'] as String?,
        note: json['note'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        productId,
        changeQuantity,
        reason,
        referenceOrderId,
        note,
        createdBy,
        createdAt,
      ];
}
