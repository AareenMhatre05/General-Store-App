import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../cart/cart_controller.dart';
import '../widgets/product_card.dart';

/// The customer's own saved products — a category they curate
/// themselves, which is why it sits alongside the shop's categories
/// rather than being buried in the profile menu.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<void> _loadFuture;
  List<Product> _products = [];
  Map<String, String> _imageUrls = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final favorites = context.read<FavoritesRepository>();
    final catalog = context.read<CatalogRepository>();
    final products = await favorites.getFavorites();
    final imageUrls =
        await catalog.getPrimaryImageUrls(products.map((p) => p.id).toList());
    setState(() {
      _products = products;
      _imageUrls = imageUrls;
    });
  }

  Future<void> _remove(Product product) async {
    final favorites = context.read<FavoritesRepository>();
    final messenger = ScaffoldMessenger.of(context);
    // Drop it from the list at once -- on this screen every card is a
    // favourite, so an un-favourited one has no business staying.
    setState(() => _products = _products.where((p) => p.id != product.id).toList());
    await favorites.remove(product.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${product.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await favorites.add(product.id);
            if (mounted) setState(() => _loadFuture = _load());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('My Favourites')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load your favourites.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }
          if (_products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border, size: 48, color: context.colors.outline),
                    const SizedBox(height: AppSpacing.base),
                    Text('Nothing saved yet', style: AppTextStyles.headlineSm),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'Tap the heart on any item to keep it here for next time.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    ElevatedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Browse the shop'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: GridView.builder(
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
                  isFavorite: true,
                  onToggleFavorite: () => _remove(product),
                  onTap: () => context.push('/product/${product.id}'),
                  onAdd: () {
                    context.read<CartController>().add(product);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added ${product.name} to cart')),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
