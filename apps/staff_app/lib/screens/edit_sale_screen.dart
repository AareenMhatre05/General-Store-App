import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Correcting a sale that was rung up wrong.
///
/// Rather than patching individual lines, the whole basket is rebuilt and
/// saved: the database triggers put stock back for anything removed or
/// reduced and take it out again for anything added, so the ledger stays
/// truthful without this screen doing any arithmetic.
class EditSaleScreen extends StatefulWidget {
  const EditSaleScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  late Future<void> _loadFuture;

  /// productId -> quantity, seeded from the sale as it currently stands.
  final Map<String, int> _quantities = {};
  Map<String, Product> _productsById = {};
  Order? _order;
  String _search = '';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final orders = context.read<OrderRepository>();
    final catalog = context.read<CatalogRepository>();

    final order = await orders.getOrder(widget.orderId);
    final items = await orders.getOrderItems(widget.orderId);
    final products = await catalog.getProducts();

    setState(() {
      _order = order;
      _productsById = {for (final p in products) p.id: p};
      _quantities
        ..clear()
        ..addEntries(items.map((i) => MapEntry(i.productId, i.quantity)));
    });
  }

  double get _total => _quantities.entries.fold(0.0, (sum, entry) {
        final product = _productsById[entry.key];
        return sum + (product?.sellingPrice ?? 0) * entry.value;
      });

  /// Stock available to this edit: what is on the shelf, plus what this
  /// sale already holds. Raising a line from 2 to 3 needs only one more
  /// unit, not three.
  int _availableFor(Product product) =>
      product.stockQuantity + (_quantities[product.id] ?? 0);

  Future<void> _save() async {
    final orders = context.read<OrderRepository>();
    final router = GoRouter.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await orders.replaceOrderItems(
        orderId: widget.orderId,
        items: [
          for (final entry in _quantities.entries)
            OrderLineInput(
              productId: entry.key,
              quantity: entry.value,
              unitPrice: _productsById[entry.key]!.sellingPrice,
            ),
        ],
      );
      router.pop(true);
    } on OrderException catch (e) {
      setState(() {
        _errorMessage = 'Could not save the changes - ${e.message}';
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not save the changes. Please try again.';
        _isSaving = false;
      });
    }
  }

  Future<void> _void() async {
    final orders = context.read<OrderRepository>();
    final router = GoRouter.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Void this sale?', style: AppTextStyles.headlineSm),
        content: Text(
          'Every item goes back into stock and the sale stops counting '
          'towards takings. It stays on record as cancelled rather than '
          'vanishing, so the day still adds up.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Void sale', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    await orders.updateOrderStatus(widget.orderId, OrderStatus.cancelled);
    router.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Edit Sale'),
        actions: [
          IconButton(
            tooltip: 'Void sale',
            icon: Icon(Icons.delete_outline, color: context.colors.error),
            onPressed: _isSaving ? null : _void,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
                onPressed: _isSaving || _quantities.isEmpty ? null : _save,
                icon: const Icon(Icons.check),
                label: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Save changes - ${formatInr(_total)}'),
              ),
              if (_quantities.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.base),
                  child: Text(
                    'A sale needs at least one item. Void it instead.',
                    style: AppTextStyles.labelMd
                        .copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError || _order == null) {
            return Center(
              child: Text(
                'Could not load this sale.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final products = _productsById.values
              .where((p) =>
                  (_quantities[p.id] ?? 0) > 0 ||
                  _search.isEmpty ||
                  p.name.toLowerCase().contains(_search.toLowerCase()))
              .toList()
            // Items already on the sale float to the top, so what you are
            // correcting is in front of you.
            ..sort((a, b) {
              final onA = (_quantities[a.id] ?? 0) > 0 ? 0 : 1;
              final onB = (_quantities[b.id] ?? 0) > 0 ? 0 : 1;
              return onA != onB ? onA - onB : a.name.compareTo(b.name);
            });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    hintText: 'Search to add an item...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.containerPaddingMobile,
                  ),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final quantity = _quantities[product.id] ?? 0;
                    final available = _availableFor(product);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        product.name,
                        style: AppTextStyles.labelLg.copyWith(
                          color: quantity > 0
                              ? context.colors.onSurface
                              : context.colors.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        '${formatInr(product.sellingPrice)} - $available available',
                        style: AppTextStyles.bodySm
                            .copyWith(color: context.colors.onSurfaceVariant),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: quantity == 0
                                ? null
                                : () => setState(() {
                                      if (quantity - 1 <= 0) {
                                        _quantities.remove(product.id);
                                      } else {
                                        _quantities[product.id] = quantity - 1;
                                      }
                                    }),
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
                            onPressed: quantity >= available
                                ? null
                                : () => setState(
                                      () => _quantities[product.id] = quantity + 1,
                                    ),
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
