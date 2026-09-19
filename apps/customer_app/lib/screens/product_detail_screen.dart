import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../cart/cart_controller.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<_ProductDetailData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    _loadFavorite();
  }

  bool _isFavorite = false;

  Future<void> _loadFavorite() async {
    final ids = await context.read<FavoritesRepository>().getFavoriteIds();
    if (mounted) setState(() => _isFavorite = ids.contains(widget.productId));
  }

  Future<void> _toggleFavorite() async {
    final favorites = context.read<FavoritesRepository>();
    // Flip immediately: a heart that waits for the network feels broken.
    final wasFavorite = _isFavorite;
    setState(() => _isFavorite = !wasFavorite);
    try {
      await favorites.toggle(widget.productId, isFavorite: wasFavorite);
    } catch (_) {
      if (mounted) setState(() => _isFavorite = wasFavorite);
    }
  }

  Future<_ProductDetailData> _load() async {
    final catalog = context.read<CatalogRepository>();
    final product = await catalog.getProduct(widget.productId);
    final imageUrls = await catalog.getPrimaryImageUrls([widget.productId]);
    return _ProductDetailData(product: product, imageUrl: imageUrls[widget.productId]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: FutureBuilder<_ProductDetailData>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text('Product not found.', style: TextStyle(color: context.colors.error)),
            );
          }

          final product = snapshot.data!.product;
          final imageUrl = snapshot.data!.imageUrl;

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Text(
                                'K.G.S',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.headlineMd,
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        AspectRatio(
                          aspectRatio: 1.2,
                          child: Container(
                            color: Colors.white,
                            child: imageUrl == null
                                ? const Icon(Icons.shopping_basket_outlined,
                                    color: Colors.black26, size: 64)
                                : Image.network(imageUrl, fit: BoxFit.contain),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(product.name, style: AppTextStyles.headlineLg),
                                  ),
                                  const SizedBox(width: AppSpacing.base),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(formatInr(product.sellingPrice),
                                          style: AppTextStyles.priceDisplay),
                                      if (product.hasActiveOffer)
                                        Text(
                                          formatInr(product.price),
                                          style: AppTextStyles.labelMd.copyWith(
                                            decoration: TextDecoration.lineThrough,
                                            color: context.colors.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.base),
                              Text(
                                product.description ?? 'No description available.',
                                style: AppTextStyles.bodyMd
                                    .copyWith(color: context.colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: AppSpacing.gutter),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _toggleFavorite,
                                  icon: Icon(
                                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                                    color: _isFavorite ? context.colors.error : null,
                                  ),
                                  label: Text(_isFavorite
                                      ? 'Saved to Favourites'
                                      : 'Save to Favourites'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.read<CartController>().add(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added ${product.name} to cart')),
                        );
                      },
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: const Text('Add to Cart'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductDetailData {
  _ProductDetailData({required this.product, required this.imageUrl});
  final Product product;
  final String? imageUrl;
}
