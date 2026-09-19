import 'package:equatable/equatable.dart';

/// Maps to the `addresses_with_coords` view (not the raw `addresses`
/// table), which exposes `latitude`/`longitude` instead of the raw
/// PostGIS `location` column.
class Address extends Equatable {
  const Address({
    required this.id,
    required this.customerId,
    this.label,
    required this.line1,
    this.line2,
    required this.city,
    required this.pincode,
    required this.latitude,
    required this.longitude,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String customerId;
  final String? label;
  final String line1;
  final String? line2;
  final String city;
  final String pincode;
  final double latitude;
  final double longitude;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        label: json['label'] as String?,
        line1: json['line1'] as String,
        line2: json['line2'] as String?,
        city: json['city'] as String,
        pincode: json['pincode'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        isDefault: json['is_default'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        customerId,
        label,
        line1,
        line2,
        city,
        pincode,
        latitude,
        longitude,
        isDefault,
        createdAt,
        updatedAt,
      ];
}
