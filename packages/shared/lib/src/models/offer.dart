import 'package:equatable/equatable.dart';

enum DiscountType {
  percentage,
  flat;

  static DiscountType fromJson(String value) =>
      DiscountType.values.firstWhere((e) => e.name == value);

  String toJson() => name;
}

enum OfferScope {
  allProducts,
  category,
  product;

  static OfferScope fromJson(String value) => switch (value) {
        'all_products' => OfferScope.allProducts,
        'category' => OfferScope.category,
        'product' => OfferScope.product,
        _ => throw ArgumentError('Unknown offer_scope: $value'),
      };

  String toJson() => switch (this) {
        OfferScope.allProducts => 'all_products',
        OfferScope.category => 'category',
        OfferScope.product => 'product',
      };
}

class Offer extends Equatable {
  const Offer({
    required this.id,
    required this.title,
    this.description,
    required this.discountType,
    required this.discountValue,
    required this.scope,
    this.categoryId,
    this.productId,
    this.bannerImagePath,
    required this.startsAt,
    this.endsAt,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final DiscountType discountType;
  final double discountValue;
  final OfferScope scope;
  final String? categoryId;
  final String? productId;
  final String? bannerImagePath;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        discountType: DiscountType.fromJson(json['discount_type'] as String),
        discountValue: (json['discount_value'] as num).toDouble(),
        scope: OfferScope.fromJson(json['scope'] as String),
        categoryId: json['category_id'] as String?,
        productId: json['product_id'] as String?,
        bannerImagePath: json['banner_image_path'] as String?,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: json['ends_at'] == null
            ? null
            : DateTime.parse(json['ends_at'] as String),
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        discountType,
        discountValue,
        scope,
        categoryId,
        productId,
        bannerImagePath,
        startsAt,
        endsAt,
        isActive,
        createdAt,
        updatedAt,
      ];
}
