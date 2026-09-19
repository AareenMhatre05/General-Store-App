import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/staff_scaffold.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  late Future<_OffersData> _loadFuture;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  DiscountType _discountType = DiscountType.percentage;
  OfferScope _scope = OfferScope.allProducts;
  String? _categoryId;
  String? _productId;
  final DateTime _startsAt = DateTime.now();
  DateTime? _endsAt;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<_OffersData> _load() async {
    final offerRepository = context.read<OfferRepository>();
    final catalogRepository = context.read<CatalogRepository>();
    final offers = await offerRepository.getAllOffers();
    final categories = await catalogRepository.getCategories();
    final products = await catalogRepository.getProducts();
    return _OffersData(offers: offers, categories: categories, products: products);
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _createOffer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await context.read<OfferRepository>().createOffer(
            title: _titleController.text.trim(),
            description:
                _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            discountType: _discountType,
            discountValue: double.parse(_valueController.text),
            scope: _scope,
            categoryId: _categoryId,
            productId: _productId,
            startsAt: _startsAt,
            endsAt: _endsAt,
          );
      _titleController.clear();
      _descriptionController.clear();
      _valueController.clear();
      setState(() {
        _scope = OfferScope.allProducts;
        _categoryId = null;
        _productId = null;
        _endsAt = null;
      });
      await _reload();
    } catch (e) {
      setState(() => _errorMessage = 'Could not create this offer. Check the values and try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StaffScaffold(
      currentIndex: 3,
      title: 'Offer Management',
      body: FutureBuilder<_OffersData>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load offers.', style: TextStyle(color: context.colors.error)),
            );
          }
          final data = snapshot.data!;
          final isWide = MediaQuery.of(context).size.width >= 900;
          final list = _buildOfferList(data);
          final form = _buildCreateForm(data);

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: list),
                      const SizedBox(width: AppSpacing.gutter),
                      Expanded(child: form),
                    ],
                  )
                : ListView(
                    children: [form, const SizedBox(height: AppSpacing.gutter), list],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildOfferList(_OffersData data) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Offers', style: AppTextStyles.headlineSm),
          const Divider(height: AppSpacing.gutter),
          if (data.offers.isEmpty)
            Text(
              'No offers yet.',
              style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
            )
          else
            for (final offer in data.offers)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.base),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: context.colors.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.dp),
                      ),
                      child: Center(
                        child: Text(
                          offer.discountType == DiscountType.percentage
                              ? '-${offer.discountValue.toStringAsFixed(0)}%'
                              : '-${formatInr(offer.discountValue)}',
                          style: AppTextStyles.labelMd.copyWith(color: context.colors.onErrorContainer),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(offer.title, style: AppTextStyles.labelLg),
                          Text(
                            offer.endsAt == null
                                ? 'No end date'
                                : 'Ends ${offer.endsAt!.toLocal()}',
                            style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: offer.isActive,
                      onChanged: (value) async {
                        await context.read<OfferRepository>().setActive(offer.id, value);
                        await _reload();
                      },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(_OffersData data) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draft New Offer', style: AppTextStyles.headlineSm),
            const SizedBox(height: AppSpacing.gutter),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Offer Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.base),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DiscountType>(
                    initialValue: _discountType,
                    decoration: const InputDecoration(labelText: 'Discount Type'),
                    items: const [
                      DropdownMenuItem(value: DiscountType.percentage, child: Text('Percentage (%)')),
                      DropdownMenuItem(value: DiscountType.flat, child: Text('Flat (₹)')),
                    ],
                    onChanged: (value) => setState(() => _discountType = value!),
                  ),
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: TextFormField(
                    controller: _valueController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Value'),
                    validator: (v) => (v == null || double.tryParse(v) == null) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            DropdownButtonFormField<OfferScope>(
              initialValue: _scope,
              decoration: const InputDecoration(labelText: 'Applies To'),
              items: const [
                DropdownMenuItem(value: OfferScope.allProducts, child: Text('All Products')),
                DropdownMenuItem(value: OfferScope.category, child: Text('A Category')),
                DropdownMenuItem(value: OfferScope.product, child: Text('A Product')),
              ],
              onChanged: (value) => setState(() {
                _scope = value!;
                _categoryId = null;
                _productId = null;
              }),
            ),
            if (_scope == OfferScope.category) ...[
              const SizedBox(height: AppSpacing.base),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in data.categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ],
            if (_scope == OfferScope.product) ...[
              const SizedBox(height: AppSpacing.base),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final product in data.products)
                    DropdownMenuItem(value: product.id, child: Text(product.name)),
                ],
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (value) => setState(() => _productId = value),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.base),
              Text(_errorMessage!, style: AppTextStyles.bodySm.copyWith(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.gutter),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _createOffer,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersData {
  _OffersData({required this.offers, required this.categories, required this.products});
  final List<Offer> offers;
  final List<Category> categories;
  final List<Product> products;
}
