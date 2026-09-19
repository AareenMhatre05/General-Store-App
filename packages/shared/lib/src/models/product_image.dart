import 'package:equatable/equatable.dart';

class ProductImage extends Equatable {
  const ProductImage({
    required this.id,
    required this.productId,
    required this.storagePath,
    required this.isPrimary,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String storagePath;
  final bool isPrimary;
  final int sortOrder;
  final DateTime createdAt;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        storagePath: json['storage_path'] as String,
        isPrimary: json['is_primary'] as bool,
        sortOrder: json['sort_order'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, productId, storagePath, isPrimary, sortOrder, createdAt];
}
