import '../models/delivery_fee_tier.dart';
import '../models/store_settings.dart';
import '../supabase/supabase_bootstrap.dart';

/// Staff/owner-only store configuration: where the store is, and what
/// delivery costs at each distance. Both feed the trigger that prices
/// an order's delivery -- with no location set, every delivery fee
/// resolves to ₹0, so this screen is not optional in practice.
class StoreRepository {
  Future<StoreSettings> getSettings() async {
    final row = await supabase
        .from('store_settings_with_coords')
        .select()
        .eq('id', 1)
        .single();
    return StoreSettings.fromJson(row);
  }

  /// Goes through the RPC because the underlying column is a PostGIS
  /// geography that PostgREST can't write directly.
  Future<void> setLocation({
    required double latitude,
    required double longitude,
  }) async {
    await supabase.rpc('set_store_location', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
  }

  /// Opens or closes the shop. Customers see the change on their next
  /// load; nothing is cached beyond that.
  Future<void> setOpen({required bool isOpen, String? closedMessage}) async {
    await supabase.from('store_settings').update({
      'is_open': isOpen,
      if (closedMessage != null) 'closed_message': closedMessage.trim(),
    }).eq('id', 1);
  }

  Future<void> setStoreDetails({String? storeName, String? address}) async {
    await supabase.from('store_settings').update({
      if (storeName != null) 'store_name': storeName,
      if (address != null) 'address': address,
    }).eq('id', 1);
  }

  Future<List<DeliveryFeeTier>> getFeeTiers() async {
    final rows = await supabase
        .from('delivery_fee_tiers')
        .select()
        .order('min_distance_meters');
    return rows.map(DeliveryFeeTier.fromJson).toList();
  }

  /// [maxDistanceMeters] null means "and everything beyond" -- the last
  /// band. A distance no band covers gets no fee at all, which is how
  /// you express "we don't deliver that far".
  Future<DeliveryFeeTier> createFeeTier({
    required double minDistanceMeters,
    double? maxDistanceMeters,
    required double feeAmount,
  }) async {
    final row = await supabase
        .from('delivery_fee_tiers')
        .insert({
          'min_distance_meters': minDistanceMeters,
          'max_distance_meters': maxDistanceMeters,
          'fee_amount': feeAmount,
        })
        .select()
        .single();
    return DeliveryFeeTier.fromJson(row);
  }

  Future<void> deleteFeeTier(String id) async {
    await supabase.from('delivery_fee_tiers').delete().eq('id', id);
  }
}
