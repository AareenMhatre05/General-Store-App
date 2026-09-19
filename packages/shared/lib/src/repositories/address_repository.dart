import '../models/address.dart';
import '../supabase/supabase_bootstrap.dart';

class AddressRepository {
  Future<List<Address>> getMyAddresses() async {
    final rows = await supabase
        .from('addresses_with_coords')
        .select()
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Address.fromJson).toList();
  }

  /// Creates a new address when [id] is null, otherwise updates the
  /// existing one. Goes through the upsert_address RPC because a plain
  /// REST insert/update can't build the underlying PostGIS point from
  /// lat/lng.
  /// One address by id. Reads through `addresses_with_coords` like the
  /// list does, because the table itself keeps the position as a PostGIS
  /// point and the app needs a latitude and longitude.
  ///
  /// RLS decides who may see it: the customer it belongs to, staff and
  /// owner, and a delivery partner only while it is the destination of
  /// an order assigned to them.
  Future<Address> getAddress(String id) async {
    final row = await supabase
        .from('addresses_with_coords')
        .select()
        .eq('id', id)
        .single();
    return Address.fromJson(row);
  }

  Future<Address> upsertAddress({
    String? id,
    String? label,
    required String line1,
    String? line2,
    required String city,
    required String pincode,
    required double latitude,
    required double longitude,
    bool isDefault = false,
  }) async {
    final row = await supabase.rpc('upsert_address', params: {
      'p_id': id,
      'p_label': label,
      'p_line1': line1,
      'p_line2': line2,
      'p_city': city,
      'p_pincode': pincode,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_is_default': isDefault,
    });
    return Address.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> deleteAddress(String id) async {
    await supabase.from('addresses').delete().eq('id', id);
  }
}
