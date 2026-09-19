import 'package:equatable/equatable.dart';

/// Maps to the `store_settings_with_coords` view (not the raw
/// `store_settings` table), which exposes `latitude`/`longitude`
/// instead of the raw PostGIS `location` column.
class StoreSettings extends Equatable {
  const StoreSettings({
    required this.storeName,
    this.latitude,
    this.longitude,
    this.address,
    required this.updatedAt,
    this.isOpen = true,
    this.closedMessage,
    this.statusChangedAt,
  });

  final String storeName;
  final double? latitude;
  final double? longitude;
  final String? address;
  final DateTime updatedAt;

  /// Whether the shop is serving right now. Flipped by staff, not by a
  /// schedule -- see the store_open_state migration.
  final bool isOpen;

  /// Optional line shown to customers instead of the default wording.
  final String? closedMessage;

  /// When [isOpen] last changed.
  final DateTime? statusChangedAt;

  /// What the customer app shows on the closed banner.
  String get closedBanner =>
      (closedMessage?.trim().isNotEmpty ?? false)
          ? closedMessage!.trim()
          : 'The shop is closed right now. You can still browse, and order '
              'when we reopen.';

  factory StoreSettings.fromJson(Map<String, dynamic> json) => StoreSettings(
        storeName: json['store_name'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        address: json['address'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        isOpen: json['is_open'] as bool? ?? true,
        closedMessage: json['closed_message'] as String?,
        statusChangedAt: json['status_changed_at'] == null
            ? null
            : DateTime.parse(json['status_changed_at'] as String),
      );

  @override
  List<Object?> get props =>
      [storeName, latitude, longitude, address, updatedAt, isOpen,
        closedMessage, statusChangedAt];
}
