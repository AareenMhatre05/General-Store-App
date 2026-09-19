import '../models/product.dart';
import '../supabase/supabase_bootstrap.dart';

/// A customer's saved products.
///
/// Private by construction: RLS restricts every row to
/// `customer_id = auth.uid()`, and staff have no policy at all — nobody
/// needs to know what a customer saved, and not collecting it is simpler
/// than protecting it.
class FavoritesRepository {
  /// Ids only, for deciding which hearts are filled. Cheap enough to
  /// refetch whenever a product list loads.
  Future<Set<String>> getFavoriteIds() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await supabase
        .from('favorites')
        .select('product_id')
        .eq('customer_id', userId)
        .limit(500);
    return {for (final row in rows) row['product_id'] as String};
  }

  /// The saved products themselves, newest first, priced like any other
  /// listing so an active offer still shows.
  Future<List<Product>> getFavorites() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await supabase
        .from('favorites')
        .select('product_id, created_at')
        .eq('customer_id', userId)
        .order('created_at', ascending: false)
        .limit(500);
    final ids = [for (final row in rows) row['product_id'] as String];
    if (ids.isEmpty) return [];

    final products = await supabase
        .from('products_with_pricing')
        .select()
        .inFilter('id', ids)
        .eq('is_active', true);
    final byId = {
      for (final row in products) row['id'] as String: Product.fromJson(row),
    };

    // Preserve "recently saved first"; the IN query returns any order.
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<void> add(String productId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    // Upsert, not insert: double-tapping a heart must not error.
    await supabase.from('favorites').upsert({
      'customer_id': userId,
      'product_id': productId,
    });
  }

  Future<void> remove(String productId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase
        .from('favorites')
        .delete()
        .eq('customer_id', userId)
        .eq('product_id', productId);
  }

  /// Returns the new state, so callers can update the icon without a
  /// second round trip.
  Future<bool> toggle(String productId, {required bool isFavorite}) async {
    if (isFavorite) {
      await remove(productId);
      return false;
    }
    await add(productId);
    return true;
  }
}
