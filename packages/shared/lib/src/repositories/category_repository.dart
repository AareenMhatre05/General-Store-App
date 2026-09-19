import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../models/category.dart';
import '../supabase/supabase_bootstrap.dart';

/// Staff/owner-only category management. Customers read categories
/// through [CatalogRepository.getCategories], which returns active ones
/// only; this repository also returns inactive categories, because
/// staff need to see and re-enable them. RLS enforces the write side.
class CategoryRepository {
  /// Every category, active or not, in the order customers would see
  /// them.
  Future<List<Category>> getAllCategories() async {
    final rows =
        await supabase.from('categories').select().order('sort_order').order('name');
    return rows.map(Category.fromJson).toList();
  }

  Future<Category> createCategory({required String name, int? sortOrder}) async {
    final row = await supabase
        .from('categories')
        .insert({
          'name': name,
          if (sortOrder != null) 'sort_order': sortOrder,
        })
        .select()
        .single();
    return Category.fromJson(row);
  }

  Future<Category> updateCategory({
    required String id,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) async {
    final row = await supabase
        .from('categories')
        .update({
          if (name != null) 'name': name,
          if (sortOrder != null) 'sort_order': sortOrder,
          if (isActive != null) 'is_active': isActive,
        })
        .eq('id', id)
        .select()
        .single();
    return Category.fromJson(row);
  }

  /// Uploads a category picture into the shared public product-images
  /// bucket and records its path. Same bucket as product photos: one set
  /// of storage policies to reason about, and a category picture is no
  /// more sensitive than a product one.
  Future<void> uploadCategoryImage({
    required String categoryId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = 'categories/$categoryId-'
        '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await supabase.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    await supabase
        .from('categories')
        .update({'image_path': path})
        .eq('id', categoryId);
  }

  Future<void> clearCategoryImage(String categoryId) async {
    await supabase
        .from('categories')
        .update({'image_path': null})
        .eq('id', categoryId);
  }

  /// Deleting a category does NOT delete its products: the foreign key
  /// is `on delete set null`, so they become uncategorized instead.
  /// Deactivating is usually the better option -- it hides the category
  /// from customers without touching the products.
  Future<void> deleteCategory(String id) async {
    await supabase.from('categories').delete().eq('id', id);
  }

  /// How many products sit in each category, so the management screen
  /// can warn before a delete uncategorizes them.
  Future<Map<String, int>> getProductCounts() async {
    final rows = await supabase.from('products').select('category_id');
    final counts = <String, int>{};
    for (final row in rows) {
      final categoryId = row['category_id'] as String?;
      if (categoryId != null) {
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
    }
    return counts;
  }
}
