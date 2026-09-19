/// Mirrors the `user_role` enum in Postgres. Adding a value there
/// without adding it here makes `fromJson` throw on a perfectly valid
/// row, which is how `delivery` went missing until the invite screen
/// tried to offer it.
enum UserRole {
  customer,
  staff,
  owner,
  delivery;

  /// Roles that belong in the staff app rather than the customer app.
  bool get isStaffSide => this != UserRole.customer;

  /// Wording for the people-facing screens.
  String get label => switch (this) {
        UserRole.customer => 'Customer',
        UserRole.staff => 'Staff',
        UserRole.owner => 'Owner',
        UserRole.delivery => 'Delivery partner',
      };

  static UserRole fromJson(String value) =>
      UserRole.values.firstWhere((e) => e.name == value);

  String toJson() => name;
}
