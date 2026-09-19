import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../cart/cart_controller.dart';
import '../widgets/product_card.dart';

/// Browse by category. Lives as a *page* inside the home shell rather
/// than a route of its own, so it can be reached by swiping left from
/// the shop — hence no Scaffold or AppBar here; the shell supplies both.
class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView>
    // Keeps the loaded list alive when the page scrolls out of the
    // PageView's cache, so swiping back and forth doesn't refetch.
    with AutomaticKeepAliveClientMixin {
  late Future<List<Category>> _loadFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<CatalogRepository>().getCategories();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Category>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load categories.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final categories = snapshot.data ?? [];
          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Text(
                  'No categories yet. Everything is on the home screen for now.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.gutter,
              crossAxisSpacing: AppSpacing.gutter,
              childAspectRatio: 1.3,
            ),
            // +1 for Favourites, which behaves like a category the
            // customer curates themselves and so belongs alongside them.
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CategoryTile(
                  label: 'My Favourites',
                  icon: Icons.favorite,
                  iconColor: context.colors.error,
                  onTap: () => context.push('/favorites'),
                );
              }
              final category = categories[index - 1];
              return _CategoryTile(
                label: category.name,
                imageUrl:
                    context.read<CatalogRepository>().categoryImageUrl(category),
                icon: Icons.category,
                onTap: () =>
                    context.push('/category/${category.id}', extra: category.name),
              );
            },
          );
        },
      );
  }
}

/// Products inside one category.
class CategoryProductsScreen extends StatefulWidget {
  const CategoryProductsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  late Future<void> _loadFuture;
  List<Product> _products = [];
  Map<String, String> _imageUrls = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogRepository>();
    final products = await catalog.getProducts(categoryId: widget.categoryId);
    final imageUrls =
        await catalog.getPrimaryImageUrls(products.map((p) => p.id).toList());
    setState(() {
      _products = products;
      _imageUrls = imageUrls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text(widget.categoryName)),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load products.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }
          if (_products.isEmpty) {
            return Center(
              child: Text(
                'Nothing in this category yet.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.gutter,
              crossAxisSpacing: AppSpacing.gutter,
              childAspectRatio: 0.62,
            ),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              return ProductCard(
                product: product,
                imageUrl: _imageUrls[product.id],
                onTap: () => context.push('/product/${product.id}'),
                onAdd: () {
                  context.read<CartController>().add(product);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added ${product.name} to cart')),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


/// One tile in the category grid. Shows the category's photo when there
/// is one and falls back to an icon, so a shop that has not uploaded
/// pictures yet still gets a usable grid rather than empty boxes.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.imageUrl,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? imageUrl;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: imageUrl == null
                    ? Center(
                        child: Icon(icon,
                            size: 36, color: iconColor ?? context.colors.primary),
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(icon,
                              size: 36, color: iconColor ?? context.colors.primary),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelLg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
