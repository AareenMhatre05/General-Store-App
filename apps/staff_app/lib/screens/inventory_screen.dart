import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/staff_scaffold.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _loadFuture;
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Product>? _searchResults;
  bool _searching = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

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
    final products = context.read<ProductRepository>();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await products.searchProductsWithCosts(value);
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

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<ProductRepository>().getProductsWithCosts();
  }

  Future<void> _reload() async {
    setState(() =>
        _loadFuture = context.read<ProductRepository>().getProductsWithCosts());
    await _loadFuture;
  }

  /// Deleting is only offered when it is actually possible. A product
  /// that has sold cannot be removed (order_items -> products is ON
  /// DELETE RESTRICT, so past orders keep their lines), and the honest
  /// answer there is to hide it rather than fail with a database error.
  Future<void> _confirmDelete(Product product) async {
    final products = context.read<ProductRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final salesCount = await products.countSales(product.id);
    if (!mounted) return;

    final sold = salesCount > 0;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text(
          sold ? 'Cannot delete "${product.name}"' : 'Delete "${product.name}"?',
          style: AppTextStyles.headlineSm,
        ),
        content: Text(
          sold
              ? 'It appears on $salesCount past order line'
                  '${salesCount == 1 ? '' : 's'}. Deleting it would leave a '
                  'hole in those orders, so it is kept. Hiding it removes it '
                  'from the customer app while your records stay intact.'
              : 'This product has never been sold, so it can be removed '
                  'completely, along with its photo, cost price and stock '
                  'history. This cannot be undone.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          if (product.isActive)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('hide'),
              child: const Text('Hide from customers'),
            ),
          if (!sold)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: Text('Delete', style: TextStyle(color: context.colors.error)),
            ),
        ],
      ),
    );

    if (choice == 'delete') {
      try {
        await products.deleteProduct(product.id);
        messenger.showSnackBar(SnackBar(content: Text('Deleted ${product.name}')));
      } on ProductInUseException {
        messenger.showSnackBar(
          const SnackBar(content: Text('It has just been sold, so it was kept.')),
        );
      }
      await _reload();
    } else if (choice == 'hide') {
      await products.setActive(productId: product.id, isActive: false);
      messenger.showSnackBar(
        SnackBar(content: Text('${product.name} is now hidden from customers')),
      );
      await _reload();
    }
  }

  Future<void> _unhide(Product product) async {
    await context
        .read<ProductRepository>()
        .setActive(productId: product.id, isActive: true);
    await _reload();
  }

  Future<void> _adjustStock(Product product, int delta) async {
    await context.read<ProductRepository>().adjustStock(
          productId: product.id,
          changeQuantity: delta,
          reason: InventoryAdjustmentReason.correction,
        );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return StaffScaffold(
      currentIndex: 2,
      title: 'Inventory',
      actions: [
        IconButton(
          tooltip: 'Categories',
          icon: const Icon(Icons.category_outlined),
          onPressed: () => context.push('/categories'),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/product/new').then((_) => _reload()),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Product>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load inventory.', style: TextStyle(color: context.colors.error)),
            );
          }
          // Fuzzy matches come from the server; without a query this is
          // the plain list. Staff mistype as often as customers, and the
          // barcode field makes a scanned code searchable too.
          final products = _searchResults ?? (snapshot.data ?? []);
          final lowStockCount = (snapshot.data ?? []).where((p) => p.stockQuantity < 10).length;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search name, barcode, category...',
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
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    if (lowStockCount > 0)
                      Chip(
                        label: Text('$lowStockCount low'),
                        backgroundColor: context.colors.errorContainer,
                        labelStyle: TextStyle(color: context.colors.onErrorContainer),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.gutter),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.gutter),
                    child: Text(
                      _searchQuery.trim().isEmpty
                          ? 'No products yet. Tap + to add one.'
                          : 'Nothing matched "$_searchQuery".',
                      style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 360,
                      mainAxisSpacing: AppSpacing.gutter,
                      crossAxisSpacing: AppSpacing.gutter,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final lowStock = product.stockQuantity < 10;
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.base * 1.5),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: context.colors.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: context.colors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(AppRadius.dp),
                                  ),
                                  child: Icon(Icons.shopping_basket_outlined,
                                      color: context.colors.onSurfaceVariant),
                                ),
                                const SizedBox(width: AppSpacing.base),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: AppTextStyles.headlineSm,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        product.barcode == null
                                            ? product.unit
                                            : '${product.unit} • SKU: ${product.barcode}',
                                        style: AppTextStyles.bodySm
                                            .copyWith(color: context.colors.onSurfaceVariant),
                                      ),
                                      if (product.marginPerUnit != null)
                                        Text(
                                          'Margin ${formatInr(product.marginPerUnit!)}'
                                          ' (${product.marginPercent!.toStringAsFixed(0)}%)',
                                          style: AppTextStyles.labelMd.copyWith(
                                            color: product.marginPerUnit! < 0
                                                ? context.colors.error
                                                : context.colors.success,
                                          ),
                                        )
                                      else
                                        Text(
                                          'No cost price set',
                                          style: AppTextStyles.labelMd
                                              .copyWith(color: context.colors.outline),
                                        ),
                                    ],
                                  ),
                                ),
                                if (product.isSpecial)
                                  Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.auto_awesome,
                                        size: 18, color: context.colors.primary),
                                  ),
                                if (!product.isActive)
                                  IconButton(
                                    tooltip: 'Hidden from customers - tap to show',
                                    onPressed: () => _unhide(product),
                                    icon: Icon(Icons.visibility_off,
                                        color: context.colors.outline),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => context
                                      .push('/product/${product.id}/edit')
                                      .then((_) => _reload()),
                                  icon: Icon(Icons.edit, color: context.colors.primary),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Delete or hide',
                                  onPressed: () => _confirmDelete(product),
                                  icon: Icon(Icons.delete_outline,
                                      color: context.colors.error),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current Price',
                                      style: AppTextStyles.labelMd
                                          .copyWith(color: context.colors.onSurfaceVariant),
                                    ),
                                    Text(formatInr(product.price), style: AppTextStyles.priceDisplay),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      lowStock ? 'Low Stock' : 'In Stock',
                                      style: AppTextStyles.labelMd.copyWith(
                                        color: lowStock ? context.colors.error : context.colors.onSurfaceVariant,
                                        fontWeight: lowStock ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.remove, size: 18),
                                          onPressed: () => _adjustStock(product, -1),
                                        ),
                                        Text('${product.stockQuantity}',
                                            style: AppTextStyles.headlineSm),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.add, size: 18),
                                          onPressed: () => _adjustStock(product, 1),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
