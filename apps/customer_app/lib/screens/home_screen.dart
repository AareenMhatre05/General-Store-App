import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../cart/cart_controller.dart';
import '../widgets/closed_banner_strip.dart';
import '../widgets/product_card.dart';
import '../widgets/special_item_announcer.dart';
import 'categories_screen.dart';

/// The app's root. Shop and Categories are two pages of one horizontally
/// swipeable view rather than separate routes: swipe left for Categories,
/// right to come back, with the bottom bar staying in sync either way.
///
/// Chat and Profile stay as pushed routes -- they are destinations you
/// visit and leave, not surfaces you flick between while shopping.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartController>().itemCount;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(cartCount: cartCount, onCartTap: () => context.push('/cart')),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                children: const [
                  // Wrapped here rather than at app root so the dialog
                  // only appears once someone is actually shopping.
                  SpecialItemAnnouncer(child: _ShopPage()),
                  CategoriesView(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Categories'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
            case 1:
              // Swipeable siblings -- animate rather than navigate, so the
              // bar and the gesture drive the same thing.
              _goToPage(index);
            case 2:
              context.push('/chat');
            case 3:
              context.push('/profile');
          }
        },
      ),
    );
  }
}

/// The shop itself: search, offers banner, category chips, product grid.
class _ShopPage extends StatefulWidget {
  const _ShopPage();

  @override
  State<_ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<_ShopPage> {
  Timer? _searchDebounce;
  List<Product>? _searchResults;
  bool _searching = false;

  /// Debounced so a five-letter word is one query, not five. The search
  /// runs in Postgres, which is what makes it tolerate typos -- a local
  /// `contains` filter never could.
  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    final catalog = context.read<CatalogRepository>();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await catalog.searchProducts(value);
        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  late Future<void> _loadFuture;
  List<Category> _categories = [];
  List<Product> _products = [];
  List<Offer> _offers = [];
  Map<String, String> _imageUrls = {};

  String? _selectedCategoryId;
  String _searchQuery = '';
  Set<String> _favoriteIds = {};
  StoreSettings? _store;

  Future<void> _toggleFavorite(Product product) async {
    final favorites = context.read<FavoritesRepository>();
    final wasFavorite = _favoriteIds.contains(product.id);
    // Optimistic: the heart flips now, and reverts only if the write
    // fails. Waiting on the network makes it feel unresponsive.
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(product.id);
      } else {
        _favoriteIds.add(product.id);
      }
    });
    try {
      await favorites.toggle(product.id, isFavorite: wasFavorite);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(product.id);
        } else {
          _favoriteIds.remove(product.id);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    // Both repositories read before any await, so nothing touches a
    // possibly-disposed context afterwards (Decisions.md D22).
    final catalog = context.read<CatalogRepository>();
    final favorites = context.read<FavoritesRepository>();
    final categories = await catalog.getCategories();
    final products = await catalog.getProducts();
    final offers = await catalog.getActiveOffers();
    final imageUrls = await catalog.getPrimaryImageUrls(products.map((p) => p.id).toList());
    final favoriteIds = await favorites.getFavoriteIds();
    final store = await catalog.getStoreSettings();
    setState(() {
      _store = store;
      _favoriteIds = favoriteIds;
      _categories = categories;
      _products = products;
      _offers = offers;
      _imageUrls = imageUrls;
    });
  }

  /// With a search term, the server's ranked results win outright --
  /// re-filtering them by category would drop good matches for no
  /// reason. Without one, this is the plain category filter.
  List<Product> get _filteredProducts {
    final results = _searchResults;
    if (results != null) return results;
    return _products
        .where((p) =>
            _selectedCategoryId == null || p.categoryId == _selectedCategoryId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
                future: _loadFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
                      child: CircularProgressIndicator(color: context.colors.primary),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load products.',
                        style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _loadFuture = _load());
                      await _loadFuture;
                    },
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.gutter),
                      children: [
                        ClosedBannerStrip(store: _store),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.containerPaddingMobile,
                          ),
                          child: TextField(
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search for fresh groceries...',
                              prefixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(AppRadius.full)),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        if (_offers.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.gutter),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.containerPaddingMobile,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                              decoration: BoxDecoration(
                                color: context.colors.primaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Daily Offers',
                                          style: TextStyle(
                                            color: context.colors.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _offers.first.title,
                                          style: TextStyle(color: context.colors.onPrimaryContainer),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.local_offer, color: context.colors.onPrimaryContainer),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.gutter),
                        SizedBox(
                          height: 88,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.containerPaddingMobile,
                            ),
                            children: [
                              _CategoryChip(
                                label: 'All',
                                selected: _selectedCategoryId == null,
                                onTap: () => setState(() => _selectedCategoryId = null),
                              ),
                              for (final category in _categories)
                                _CategoryChip(
                                  label: category.name,
                                  selected: _selectedCategoryId == category.id,
                                  onTap: () => setState(() => _selectedCategoryId = category.id),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.base),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.containerPaddingMobile,
                          ),
                          child: Text(
                            _searchResults != null
                                ? 'Results for "$_searchQuery"'
                                : 'Popular Right Now',
                            style: AppTextStyles.headlineSm,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.base),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.containerPaddingMobile,
                          ),
                          child: _filteredProducts.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.gutter),
                                  child: Text(
                                    _searchResults != null
                                        ? 'Nothing matched "$_searchQuery". Try a shorter word.'
                                        : 'No products found.',
                                    style: AppTextStyles.bodyMd
                                        .copyWith(color: context.colors.onSurfaceVariant),
                                  ),
                                )
                              : GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: AppSpacing.gutter,
                                    crossAxisSpacing: AppSpacing.gutter,
                                    // Taller cells so the image still has
                                    // room once the text and button below
                                    // have taken theirs.
                                    childAspectRatio: 0.62,
                                  ),
                                  itemCount: _filteredProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = _filteredProducts[index];
                                    return ProductCard(
                                      product: product,
                                      imageUrl: _imageUrls[product.id],
                                      isFavorite: _favoriteIds.contains(product.id),
                                      onToggleFavorite: () => _toggleFavorite(product),
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
                        ),
                      ],
                    ),
                  );
                },
              );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cartCount, required this.onCartTap});

  final int cartCount;
  final VoidCallback onCartTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPaddingMobile,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: context.colors.primary),
          const SizedBox(width: AppSpacing.base),
          Text('K.G.S', style: AppTextStyles.headlineMd),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: onCartTap,
                icon: Icon(Icons.shopping_cart, color: context.colors.primary),
              ),
              if (cartCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.colors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$cartCount',
                      style: TextStyle(
                        color: context.colors.onSecondaryContainer,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.base),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryContainer : context.colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.category,
                color: selected ? context.colors.onPrimaryContainer : context.colors.tertiary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(
                  color: selected ? context.colors.onPrimaryContainer : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
