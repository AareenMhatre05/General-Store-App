import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Ringing up a customer standing at the counter. Creates an order on
/// the `in_store` channel, which is born already delivered and paid --
/// there is nothing to deliver and the money is in the till.
///
/// The same stock triggers fire as for a delivery order, so a counter
/// sale decrements inventory exactly like an online one.
class InStoreSaleScreen extends StatefulWidget {
  const InStoreSaleScreen({super.key});

  @override
  State<InStoreSaleScreen> createState() => _InStoreSaleScreenState();
}

class _InStoreSaleScreenState extends State<InStoreSaleScreen> {
  late Future<List<Product>> _loadFuture;
  final Map<String, int> _quantities = {};
  Map<String, Product> _productsById = {};
  String _search = '';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<List<Product>> _load() async {
    final products = await context.read<CatalogRepository>().getProducts();
    _productsById = {for (final p in products) p.id: p};
    return products;
  }

  double get _total => _quantities.entries.fold(0.0, (sum, entry) {
        final product = _productsById[entry.key];
        return sum + (product?.sellingPrice ?? 0) * entry.value;
      });

  int get _lineCount => _quantities.values.where((q) => q > 0).length;

  void _setQuantity(String productId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = quantity;
      }
    });
  }

  Future<void> _completeSale() async {
    if (_quantities.isEmpty) return;

    final orderRepository = context.read<OrderRepository>();
    final router = GoRouter.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final order = await orderRepository.createInStoreSale(
        items: [
          for (final entry in _quantities.entries)
            OrderLineInput(
              productId: entry.key,
              quantity: entry.value,
              unitPrice: _productsById[entry.key]!.sellingPrice,
            ),
        ],
      );
      // In-store money is collected at the counter, so the sale is
      // settled the moment it's rung up.
      await orderRepository.updatePaymentStatus(order.id, PaymentStatus.paid);
      router.go('/orders/${order.id}');
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not record the sale. Check stock levels and try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('New In-Store Sale')),
      bottomNavigationBar: _quantities.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                      ),
                      const SizedBox(height: AppSpacing.base),
                    ],
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _completeSale,
                      icon: const Icon(Icons.point_of_sale),
                      label: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Complete Sale · $_lineCount item'
                              '${_lineCount == 1 ? '' : 's'} · ${formatInr(_total)}'),
                    ),
                  ],
                ),
              ),
            ),
      body: FutureBuilder<List<Product>>(
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

          final products = (snapshot.data ?? [])
              .where((p) =>
                  _search.isEmpty ||
                  p.name.toLowerCase().contains(_search.toLowerCase()) ||
                  (p.barcode?.contains(_search) ?? false))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Search by name or barcode...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Text(
                          'No matching products.',
                          style: AppTextStyles.bodyMd
                              .copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.containerPaddingMobile,
                        ),
                        itemCount: products.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final quantity = _quantities[product.id] ?? 0;
                          final outOfStock = product.stockQuantity <= 0;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(product.name, style: AppTextStyles.labelLg),
                            subtitle: Text(
                              '${formatInr(product.sellingPrice)} · ${product.unit} · '
                              '${outOfStock ? 'OUT OF STOCK' : '${product.stockQuantity} in stock'}',
                              style: AppTextStyles.bodySm.copyWith(
                                color: outOfStock
                                    ? context.colors.error
                                    : context.colors.onSurfaceVariant,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: quantity == 0
                                      ? null
                                      : () => _setQuantity(product.id, quantity - 1),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '$quantity',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.headlineSm,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline),
                                  // Stock is enforced by the DB anyway;
                                  // blocking here just avoids a pointless
                                  // round trip and a confusing error.
                                  onPressed: quantity >= product.stockQuantity
                                      ? null
                                      : () => _setQuantity(product.id, quantity + 1),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
