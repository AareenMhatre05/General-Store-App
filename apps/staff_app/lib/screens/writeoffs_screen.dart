import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Expired and damaged stock, and whether the supplier made it good.
///
/// Two outcomes that look identical on the shelf but are opposite on the
/// books: a refunded batch costs the shop nothing, an unrefunded one is
/// money gone. The screen keeps them visibly apart so the loss figure is
/// the real one.
class WriteoffsScreen extends StatefulWidget {
  const WriteoffsScreen({super.key});

  @override
  State<WriteoffsScreen> createState() => _WriteoffsScreenState();
}

class _WriteoffsScreenState extends State<WriteoffsScreen> {
  late Future<void> _loadFuture;
  List<StockWriteoff> _writeoffs = [];
  WriteoffTotals? _totals;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final repository = context.read<WriteoffRepository>();
    final now = DateTime.now();
    final entries = await repository.getRecent();
    final totals = await repository.totalsBetween(
      from: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      to: now.add(const Duration(days: 1)),
    );
    setState(() {
      _writeoffs = entries;
      _totals = totals;
    });
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _recordWriteoff() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (_) => const _RecordWriteoffSheet(),
    );
    if (saved == true) await _reload();
  }

  Future<void> _delete(StockWriteoff writeoff) async {
    final repository = context.read<WriteoffRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Remove this entry?', style: AppTextStyles.headlineSm),
        content: Text(
          'The stock it removed is NOT added back automatically — if the '
          'goods are still on the shelf, correct the count in Inventory.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.delete(writeoff.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Expired & Damaged')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _recordWriteoff,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Write Off Stock'),
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load write-offs.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final totals = _totals;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                96,
              ),
              children: [
                if (totals != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                    decoration: BoxDecoration(
                      color: totals.netLoss > 0
                          ? context.colors.errorContainer
                          : context.colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lost in the last 30 days',
                          style: AppTextStyles.labelMd.copyWith(
                            color: totals.netLoss > 0
                                ? context.colors.onErrorContainer
                                : context.colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatInr(totals.netLoss),
                          style: AppTextStyles.headlineLg.copyWith(
                            color: totals.netLoss > 0
                                ? context.colors.onErrorContainer
                                : context.colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${totals.units} unit${totals.units == 1 ? '' : 's'} written off · '
                          '${formatInr(totals.costOfGoods)} of goods · '
                          '${formatInr(totals.refundedAmount)} refunded',
                          style: AppTextStyles.bodySm.copyWith(
                            color: totals.netLoss > 0
                                ? context.colors.onErrorContainer
                                : context.colors.onSurfaceVariant,
                          ),
                        ),
                        if (totals.costOfGoods > 0) ...[
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            'Suppliers made good ${totals.recoveredPercent.toStringAsFixed(0)}% '
                            'of what expired.',
                            style: AppTextStyles.labelMd.copyWith(
                              color: totals.netLoss > 0
                                  ? context.colors.onErrorContainer
                                  : context.colors.success,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.gutter),
                ],
                Text('Recent write-offs', style: AppTextStyles.headlineSm),
                const SizedBox(height: AppSpacing.base),
                if (_writeoffs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.gutter),
                    child: Text(
                      'Nothing written off yet. Use the button below when '
                      'stock expires or is damaged.',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  )
                else
                  for (final writeoff in _writeoffs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: context.colors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${writeoff.quantity} × ${writeoff.productName}',
                                    style: AppTextStyles.labelLg,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${writeoff.reason} · '
                                    '${DateFormat('d MMM').format(writeoff.createdAt.toLocal())}'
                                    '${writeoff.notes == null ? '' : ' · ${writeoff.notes}'}',
                                    style: AppTextStyles.bodySm
                                        .copyWith(color: context.colors.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 6),
                                  // The distinction that matters, stated
                                  // rather than left to be inferred.
                                  Row(
                                    children: [
                                      Icon(
                                        writeoff.refunded
                                            ? Icons.check_circle_outline
                                            : Icons.trending_down,
                                        size: 16,
                                        color: writeoff.refunded
                                            ? context.colors.success
                                            : context.colors.error,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          writeoff.refunded
                                              ? 'Supplier refunded ${formatInr(writeoff.refundAmount)}'
                                              : 'Loss of ${formatInr(writeoff.netLoss)}',
                                          style: AppTextStyles.labelMd.copyWith(
                                            color: writeoff.refunded
                                                ? context.colors.success
                                                : context.colors.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: context.colors.error, size: 20),
                              onPressed: () => _delete(writeoff),
                            ),
                          ],
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

class _RecordWriteoffSheet extends StatefulWidget {
  const _RecordWriteoffSheet();

  @override
  State<_RecordWriteoffSheet> createState() => _RecordWriteoffSheetState();
}

class _RecordWriteoffSheetState extends State<_RecordWriteoffSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _refundController = TextEditingController();
  final _notesController = TextEditingController();

  late Future<List<Product>> _productsFuture;
  Product? _product;
  String _reason = 'expired';
  bool _refunded = false;
  bool _isSaving = false;
  String? _errorMessage;

  static const _reasons = ['expired', 'damaged', 'spoiled', 'lost'];

  @override
  void initState() {
    super.initState();
    _productsFuture = context.read<ProductRepository>().getProductsWithCosts();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _refundController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// What this batch cost the shop, so the consequence is visible before
  /// it is recorded rather than discovered on a report later.
  double get _costOfGoods {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    return (_product?.costPrice ?? 0) * quantity;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_product == null) {
      setState(() => _errorMessage = 'Choose which product.');
      return;
    }

    final repository = context.read<WriteoffRepository>();
    final navigator = Navigator.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await repository.record(
        productId: _product!.id,
        quantity: int.parse(_quantityController.text),
        refunded: _refunded,
        refundAmount:
            _refunded ? (double.tryParse(_refundController.text) ?? 0) : 0,
        reason: _reason,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      navigator.pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not record it. Please try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.containerPaddingMobile,
        right: AppSpacing.containerPaddingMobile,
        top: AppSpacing.containerPaddingMobile,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            AppSpacing.containerPaddingMobile,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Write Off Stock', style: AppTextStyles.headlineSm),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Removes it from stock and records what it cost you.',
                style: AppTextStyles.bodySm
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.gutter),
              FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  final products = snapshot.data ?? [];
                  return DropdownButtonFormField<Product>(
                    initialValue: _product,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: [
                      for (final product in products)
                        DropdownMenuItem(
                          value: product,
                          child: Text(
                            '${product.name} (${product.stockQuantity} in stock)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _product = value),
                    validator: (value) => value == null ? 'Required' : null,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      validator: (value) {
                        final quantity = int.tryParse(value ?? '');
                        if (quantity == null || quantity <= 0) return 'Enter a number';
                        if (_product != null && quantity > _product!.stockQuantity) {
                          return 'Only ${_product!.stockQuantity} in stock';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: [
                        for (final reason in _reasons)
                          DropdownMenuItem(value: reason, child: Text(reason)),
                      ],
                      onChanged: (value) => setState(() => _reason = value ?? 'expired'),
                    ),
                  ),
                ],
              ),
              if (_product != null) ...[
                const SizedBox(height: AppSpacing.base),
                Text(
                  _product!.costPrice == null
                      ? 'No cost price recorded for this product, so the loss '
                          'cannot be valued. Add one in Inventory.'
                      : 'These goods cost you ${formatInr(_costOfGoods)}.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: _product!.costPrice == null
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.gutter),
              // The question that decides loss versus wash.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Supplier refunded this'),
                subtitle: Text(
                  _refunded
                      ? 'Recorded as recovered, not as a loss'
                      : 'Recorded as a loss to the shop',
                  style: AppTextStyles.bodySm.copyWith(
                    color: _refunded ? context.colors.success : context.colors.error,
                  ),
                ),
                value: _refunded,
                onChanged: (value) => setState(() {
                  _refunded = value;
                  if (value && _refundController.text.trim().isEmpty) {
                    // Full credit is the common case; staff can lower it.
                    _refundController.text = _costOfGoods.toStringAsFixed(2);
                  }
                }),
              ),
              if (_refunded) ...[
                TextFormField(
                  controller: _refundController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Refund amount (₹)',
                    helperText: 'Partial credit is fine — enter what you got back',
                  ),
                  validator: (value) {
                    if (!_refunded) return null;
                    final amount = double.tryParse(value ?? '');
                    if (amount == null || amount <= 0) return 'Enter an amount';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.base),
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.gutter),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record Write-Off'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
