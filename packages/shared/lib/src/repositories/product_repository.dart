import 'dart:typed_data';

import '../models/inventory_adjustment.dart';
import '../models/product.dart';
import '../supabase/supabase_bootstrap.dart';

/// Staff/owner-only writes for the product catalog: creating/editing
/// products, adjusting stock, and uploading product photos. Reads live
/// in [CatalogRepository]; RLS enforces the staff/owner-only part of
/// everything here regardless.
/// Why a product could not be deleted.
class ProductInUseException implements Exception {
  const ProductInUseException(this.salesCount);

  /// How many order lines reference it.
  final int salesCount;

  @override
  String toString() =>
      'Product appears on $salesCount order line(s) and cannot be deleted';
}

class ProductRepository {
  /// How many order lines reference this product. Non-zero means it
  /// cannot be deleted -- order_items -> products is ON DELETE RESTRICT,
  /// deliberately, because deleting it would tear a hole in past orders.
  Future<int> countSales(String productId) async {
    final rows = await supabase
        .from('order_items')
        .select('id')
        .eq('product_id', productId)
        .limit(1000);
    return rows.length;
  }

  /// Permanently removes a product, along with its images, cost and
  /// stock history (those cascade). Throws [ProductInUseException] if it
  /// has ever been sold -- hide it instead, via [setActive].
  Future<void> deleteProduct(String productId) async {
    final sales = await countSales(productId);
    if (sales > 0) throw ProductInUseException(sales);
    await supabase.from('products').delete().eq('id', productId);
  }

  /// Hides a product from customers without destroying anything. The
  /// right answer for something that has sold before, or is simply out
  /// of season.
  Future<void> setActive({
    required String productId,
    required bool isActive,
  }) async {
    await supabase
        .from('products')
        .update({'is_active': isActive})
        .eq('id', productId);
  }

  /// Records what the shop pays its supplier. Upsert, because a product
  /// has at most one cost and staff re-enter it whenever it changes.
  ///
  /// Lives in `product_costs`, which customers cannot read at all --
  /// see Decisions.md D50.
  Future<void> setCostPrice({
    required String productId,
    required double costPrice,
  }) async {
    await supabase.from('product_costs').upsert({
      'product_id': productId,
      'cost_price': costPrice,
    });
  }

  Future<void> clearCostPrice(String productId) async {
    await supabase.from('product_costs').delete().eq('product_id', productId);
  }

  /// Staff view of the catalog: selling price, supplier cost, margin.
  /// Reads `products_with_costs`, where cost comes back null for anyone
  /// who is not staff.
  Future<List<Product>> getProductsWithCosts() async {
    final rows = await supabase
        .from('products_with_costs')
        .select()
        .order('name');
    return rows.map(Product.fromJson).toList();
  }

  /// Same ranked search as the customer app, but resolved through
  /// `products_with_costs` so results keep their margin. Searching the
  /// customer view instead would show "No cost price set" against
  /// products that have one.
  Future<List<Product>> searchProductsWithCosts(String query,
      {int limit = 50}) async {
    final term = query.trim();
    if (term.isEmpty) return [];

    final matches = await supabase.rpc('search_products', params: {
      'p_query': term,
      'p_limit': limit,
    });
    final ranked =
        (matches as List).map((m) => (m as Map)['id'] as String).toList();
    if (ranked.isEmpty) return [];

    final rows = await supabase
        .from('products_with_costs')
        .select()
        .inFilter('id', ranked);
    final byId = {
      for (final row in rows) row['id'] as String: Product.fromJson(row),
    };
    return [
      for (final id in ranked)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<void> setSpecial({
    required String productId,
    required bool isSpecial,
  }) async {
    await supabase
        .from('products')
        .update({'is_special': isSpecial})
        .eq('id', productId);
  }

  Future<Product> createProduct({
    String? categoryId,
    required String name,
    String? description,
    required String unit,
    required double price,
    double? mrp,
    String? barcode,
    required int initialStock,
  }) async {
    final row = await supabase
        .from('products')
        .insert({
          'category_id': categoryId,
          'name': name,
          'description': description,
          'unit': unit,
          'price': price,
          'mrp': mrp,
          'barcode': barcode,
        })
        .select()
        .single();
    final product = Product.fromJson(row);

    if (initialStock > 0) {
      await adjustStock(
        productId: product.id,
        changeQuantity: initialStock,
        reason: InventoryAdjustmentReason.restock,
        note: 'Initial stock',
      );
    }
    return getProduct(product.id);
  }

  Future<Product> updateProduct({
    required String id,
    String? categoryId,
    required String name,
    String? description,
    required String unit,
    required double price,
    double? mrp,
    String? barcode,
    required bool isActive,
  }) async {
    final row = await supabase
        .from('products')
        .update({
          'category_id': categoryId,
          'name': name,
          'description': description,
          'unit': unit,
          'price': price,
          'mrp': mrp,
          'barcode': barcode,
          'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Product.fromJson(row);
  }

  /// Staff read of one product: reads `products_with_costs` so the
  /// edit form gets the supplier cost and margin alongside the rest.
  Future<Product> getProduct(String id) async {
    final row = await supabase
        .from('products_with_costs')
        .select()
        .eq('id', id)
        .single();
    return Product.fromJson(row);
  }

  Future<void> adjustStock({
    required String productId,
    required int changeQuantity,
    required InventoryAdjustmentReason reason,
    String? note,
  }) async {
    await supabase.from('inventory_adjustments').insert({
      'product_id': productId,
      'change_quantity': changeQuantity,
      'reason': reason.toJson(),
      'note': note,
    });
  }

  /// Uploads a photo to the public `product-images` bucket and records
  /// it against the product. The first image for a product is marked
  /// primary automatically.
  Future<void> uploadProductImage({
    required String productId,
    required Uint8List bytes,
    required String fileExtension,
    bool isPrimary = false,
  }) async {
    final path = '$productId/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await supabase.storage.from('product-images').uploadBinary(path, bytes);
    await supabase.from('product_images').insert({
      'product_id': productId,
      'storage_path': path,
      'is_primary': isPrimary,
    });
  }
}
