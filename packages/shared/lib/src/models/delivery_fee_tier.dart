import 'package:equatable/equatable.dart';

class DeliveryFeeTier extends Equatable {
  const DeliveryFeeTier({
    required this.id,
    required this.minDistanceMeters,
    this.maxDistanceMeters,
    required this.feeAmount,
    required this.createdAt,
  });

  final String id;
  final double minDistanceMeters;
  final double? maxDistanceMeters;
  final double feeAmount;
  final DateTime createdAt;

  factory DeliveryFeeTier.fromJson(Map<String, dynamic> json) =>
      DeliveryFeeTier(
        id: json['id'] as String,
        minDistanceMeters: (json['min_distance_meters'] as num).toDouble(),
        maxDistanceMeters: (json['max_distance_meters'] as num?)?.toDouble(),
        feeAmount: (json['fee_amount'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, minDistanceMeters, maxDistanceMeters, feeAmount, createdAt];
}
