import 'package:equatable/equatable.dart';

class Product extends Equatable {
  const Product({
    required this.id,
    this.categoryId,
    required this.name,
    this.description,
    required this.unit,
    required this.price,
    this.mrp,
    this.barcode,
    required this.stockQuantity,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.effectivePrice,
    this.offerTitle,
    this.costPrice,
    this.isSpecial = false,
    this.specialSince,
  });

  final String id;
  final String? categoryId;
  final String name;
  final String? description;
  final String unit;
  final double price;
  final double? mrp;
  final String? barcode;
  final int stockQuantity;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Price after the best active offer, present only when the row came
  /// from the `products_with_pricing` view. Null when read straight
  /// from the `products` table -- use [sellingPrice], not this.
  final double? effectivePrice;

  /// Title of the offer responsible for [effectivePrice], if any.
  final String? offerTitle;

  /// Flagged by staff as a special item -- a fresh arrival or one-off
  /// deal the customer app announces.
  final bool isSpecial;

  /// When [isSpecial] last became true; null when never flagged. The
  /// customer app uses it to announce the newest first.
  final DateTime? specialSince;

  /// What the shop pays its supplier. Present only when the row came
  /// from `products_with_costs`, which only staff can read -- it is null
  /// for customers by design, never merely absent.
  final double? costPrice;

  /// Profit on one unit at the current selling price, or null when no
  /// cost has been recorded.
  double? get marginPerUnit =>
      costPrice == null ? null : sellingPrice - costPrice!;

  /// Margin as a percentage of the selling price.
  double? get marginPercent {
    final margin = marginPerUnit;
    if (margin == null || sellingPrice <= 0) return null;
    return (margin / sellingPrice) * 100;
  }

  /// What a customer actually pays today. Falls back to the list price
  /// when no offer applies or pricing wasn't fetched.
  double get sellingPrice => effectivePrice ?? price;

  /// True when an offer is currently reducing this product's price, so
  /// the UI can show the list price struck through.
  bool get hasActiveOffer => effectivePrice != null && effectivePrice! < price;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        categoryId: json['category_id'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        unit: json['unit'] as String,
        price: (json['price'] as num).toDouble(),
        mrp: (json['mrp'] as num?)?.toDouble(),
        barcode: json['barcode'] as String?,
        stockQuantity: json['stock_quantity'] as int,
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        effectivePrice: (json['effective_price'] as num?)?.toDouble(),
        offerTitle: json['offer_title'] as String?,
        costPrice: (json['cost_price'] as num?)?.toDouble(),
        isSpecial: json['is_special'] as bool? ?? false,
        specialSince: json['special_since'] == null
            ? null
            : DateTime.parse(json['special_since'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        categoryId,
        name,
        description,
        unit,
        price,
        mrp,
        barcode,
        stockQuantity,
        isActive,
        createdAt,
        updatedAt,
        effectivePrice,
        offerTitle,
        costPrice,
        isSpecial,
        specialSince,
      ];
}
