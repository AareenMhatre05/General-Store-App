import 'package:equatable/equatable.dart';

import 'user_role.dart';

class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.phone,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final UserRole role;
  final String? fullName;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        role: UserRole.fromJson(json['role'] as String),
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  @override
  List<Object?> get props => [id, role, fullName, phone, createdAt, updatedAt];
}
