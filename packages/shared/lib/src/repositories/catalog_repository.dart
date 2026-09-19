import '../models/category.dart';
import '../models/delivery_fee_tier.dart';
import '../models/offer.dart';
import '../models/product.dart';
import '../models/product_image.dart';
import '../models/store_settings.dart';
import '../supabase/supabase_bootstrap.dart';

/// Read access to the product/offer catalog and store settings. Writes
/// (creating products, offers, adjusting stock, setting the store
/// location) are staff/owner-only and gated by RLS -- this repository
/// only wraps the reads every screen in both apps needs.
class CatalogRepository {
  /// Public URL for a category's picture, or null when none is set.
  ///
  /// Category images live in the same public `product-images` bucket as
  /// product photos: identical access rules (anyone reads, staff write),
  /// one bucket to configure, and a category picture is no more
  /// sensitive than a product one.
  String? categoryImageUrl(Category category) {
    final path = category.imagePath;
    if (path == null || path.isEmpty) return null;
    return supabase.storage.from('product-images').getPublicUrl(path);
  }

  Future<List<Category>> getCategories() async {
    final rows = await supabase
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return rows.map(Category.fromJson).toList();
  }

  /// Reads through `products_with_pricing` rather than `products`, so
  /// every product carries the price a customer actually pays today
  /// (see [Product.sellingPrice]). The view is security_invoker, so RLS
  /// behaves exactly as it does on the table.
  Future<Product> getProduct(String id) async {
    final row =
        await supabase.from('products_with_pricing').select().eq('id', id).single();
    return Product.fromJson(row);
  }

  Future<List<Product>> getProducts({String? categoryId}) async {
    var query =
        supabase.from('products_with_pricing').select().eq('is_active', true);
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    // Bounded: the shop's catalog is small, and a client that asks for
    // an unbounded list will keep working as it grows -- right up until
    // it doesn't.
    final rows = await query.order('name').limit(500);
    return rows.map(Product.fromJson).toList();
  }

  Future<List<ProductImage>> getProductImages(String productId) async {
    final rows = await supabase
        .from('product_images')
        .select()
        .eq('product_id', productId)
        .order('sort_order');
    return rows.map(ProductImage.fromJson).toList();
  }

  /// One (primary, or first-uploaded) public image URL per product, for
  /// grids where fetching every image would be wasteful. Products with
  /// no uploaded image are simply absent from the result.
  Future<Map<String, String>> getPrimaryImageUrls(List<String> productIds) async {
    if (productIds.isEmpty) return {};
    final rows = await supabase
        .from('product_images')
        .select()
        .inFilter('product_id', productIds)
        .order('is_primary', ascending: false)
        .order('sort_order');

    final urls = <String, String>{};
    for (final row in rows) {
      final productId = row['product_id'] as String;
      urls.putIfAbsent(
        productId,
        () => supabase.storage.from('product-images').getPublicUrl(row['storage_path'] as String),
      );
    }
    return urls;
  }

  /// Special items that are actually buyable right now, newest flag
  /// first. In stock is part of the definition: announcing something
  /// the customer cannot buy is worse than not announcing it.
  Future<List<Product>> getSpecialProducts() async {
    final rows = await supabase
        .from('products_with_pricing')
        .select()
        .eq('is_active', true)
        .eq('is_special', true)
        .gt('stock_quantity', 0)
        .order('special_since', ascending: false);
    return rows.map(Product.fromJson).toList();
  }

  /// Typo-tolerant product search, ranked by relevance.
  ///
  /// Runs in Postgres (`search_products`), not in Dart: it combines
  /// trigram similarity with edit distance across name, description,
  /// category and barcode, none of which a `String.contains` filter over
  /// an already-loaded list can do. RLS still applies, so customers
  /// search active products and staff search everything.
  Future<List<Product>> searchProducts(String query, {int limit = 50}) async {
    final term = query.trim();
    if (term.isEmpty) return [];

    final matches = await supabase.rpc('search_products', params: {
      'p_query': term,
      'p_limit': limit,
    });

    final ranked = (matches as List)
        .map((m) => (m as Map)['id'] as String)
        .toList();
    if (ranked.isEmpty) return [];

    final rows = await supabase
        .from('products_with_pricing')
        .select()
        .inFilter('id', ranked);
    final byId = {
      for (final row in rows) row['id'] as String: Product.fromJson(row),
    };

    // Preserve the server's ranking; the IN query returns arbitrary order.
    return [
      for (final id in ranked)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<List<Offer>> getActiveOffers() async {
    final rows = await supabase
        .from('offers')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return rows.map(Offer.fromJson).toList();
  }

  Future<List<DeliveryFeeTier>> getDeliveryFeeTiers() async {
    final rows = await supabase
        .from('delivery_fee_tiers')
        .select()
        .order('min_distance_meters');
    return rows.map(DeliveryFeeTier.fromJson).toList();
  }

  Future<StoreSettings> getStoreSettings() async {
    final row = await supabase
        .from('store_settings_with_coords')
        .select()
        .eq('id', 1)
        .single();
    return StoreSettings.fromJson(row);
  }

  /// Delivery fee for a customer's live/foreground location, computed
  /// server-side from the store's location via ST_Distance.
  Future<double?> getDeliveryFeeForCoords({
    required double latitude,
    required double longitude,
  }) async {
    final result = await supabase.rpc('get_delivery_fee_for_coords', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
    return (result as num?)?.toDouble();
  }
}
