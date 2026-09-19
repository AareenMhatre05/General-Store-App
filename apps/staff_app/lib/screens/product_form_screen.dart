import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'categories_screen.dart' show showCategoryEditor;

/// Sentinel for the dropdown's "New category..." row. A real category id
/// is a uuid, so this can never collide with one.
const _newCategoryValue = '__new_category__';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.productId});

  final String? productId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _unitController = TextEditingController(text: 'piece');
  final _priceController = TextEditingController();
  final _mrpController = TextEditingController();
  final _costController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  late Future<void> _loadFuture;
  List<Category> _categories = [];
  String? _categoryId;
  bool _isActive = true;
  bool _isSpecial = false;
  int _currentStock = 0;
  String? _existingImageUrl;
  Uint8List? _pendingImageBytes;
  String? _pendingImageExtension;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.productId != null;

  /// Picking "New category..." opens the same editor the Categories
  /// screen uses, then selects whatever was created -- so you don't have
  /// to abandon a half-filled product form to add one.
  Future<void> _onCategoryChanged(String? value) async {
    if (value != _newCategoryValue) {
      setState(() => _categoryId = value);
      return;
    }

    final created = await showCategoryEditor(context);
    if (created == null) return;
    setState(() {
      _categories = [..._categories, created];
      _categoryId = created.id;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _mrpController.dispose();
    _costController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogRepository>();
    final productRepository = context.read<ProductRepository>();
    _categories = await catalog.getCategories();

    if (_isEditing) {
      // Staff repository, not catalog: only its view carries cost.
      final product = await productRepository.getProduct(widget.productId!);
      final images = await catalog.getPrimaryImageUrls([product.id]);
      _nameController.text = product.name;
      _descriptionController.text = product.description ?? '';
      _unitController.text = product.unit;
      _priceController.text = product.price.toString();
      _mrpController.text = product.mrp?.toString() ?? '';
      _barcodeController.text = product.barcode ?? '';
      _categoryId = product.categoryId;
      _isActive = product.isActive;
      _isSpecial = product.isSpecial;
      _costController.text = product.costPrice?.toString() ?? '';
      _currentStock = product.stockQuantity;
      _existingImageUrl = images[product.id];
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageExtension = picked.name.split('.').last;
    });
  }

  Future<void> _adjustStock(int delta) async {
    if (!_isEditing) {
      final current = int.tryParse(_stockController.text) ?? 0;
      setState(() => _stockController.text = '${(current + delta).clamp(0, 1 << 30)}');
      return;
    }
    await context.read<ProductRepository>().adjustStock(
          productId: widget.productId!,
          changeQuantity: delta,
          reason: InventoryAdjustmentReason.correction,
        );
    setState(() => _currentStock += delta);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final products = context.read<ProductRepository>();
      final price = double.parse(_priceController.text);
      final mrp = _mrpController.text.trim().isEmpty ? null : double.parse(_mrpController.text);
      final costText = _costController.text.trim();
      final cost = costText.isEmpty ? null : double.parse(costText);

      String productId;
      if (_isEditing) {
        await products.updateProduct(
          id: widget.productId!,
          categoryId: _categoryId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          unit: _unitController.text.trim(),
          price: price,
          mrp: mrp,
          barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
          isActive: _isActive,
        );
        productId = widget.productId!;
      } else {
        final created = await products.createProduct(
          categoryId: _categoryId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          unit: _unitController.text.trim(),
          price: price,
          mrp: mrp,
          barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
          initialStock: int.tryParse(_stockController.text) ?? 0,
        );
        productId = created.id;
      }

      // Cost lives in its own staff-only table, so it is written
      // separately from the product row.
      if (cost == null) {
        await products.clearCostPrice(productId);
      } else {
        await products.setCostPrice(productId: productId, costPrice: cost);
      }
      await products.setSpecial(productId: productId, isSpecial: _isSpecial);

      if (_pendingImageBytes != null && _pendingImageExtension != null) {
        await products.uploadProductImage(
          productId: productId,
          bytes: _pendingImageBytes!,
          fileExtension: _pendingImageExtension!,
          isPrimary: true,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = 'Could not save this product. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text(_isEditing ? 'Update Product Details' : 'Add Product')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Product Image', style: AppTextStyles.labelLg),
                      const SizedBox(height: AppSpacing.base),
                      InkWell(
                        onTap: _pickImage,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: context.colors.outlineVariant),
                          ),
                          child: _buildImagePreview(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.gutter),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Product Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(labelText: 'Description (optional)'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              onChanged: (_) => setState(() {}),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Selling price / MRP (₹)',
                                helperText: 'What the customer pays',
                              ),
                              validator: (v) =>
                                  (v == null || double.tryParse(v) == null) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: TextFormField(
                              controller: _mrpController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Was price (optional)',
                                helperText: 'Shown struck through',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _unitController,
                              decoration: const InputDecoration(labelText: 'Unit (e.g. "1 kg")'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: _isEditing
                                ? _StockStepper(value: _currentStock, onChange: _adjustStock)
                                : TextFormField(
                                    controller: _stockController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Initial Stock'),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        controller: _barcodeController,
                        decoration: const InputDecoration(labelText: 'Barcode / SKU (optional)'),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      DropdownButtonFormField<String?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                          for (final category in _categories)
                            DropdownMenuItem(value: category.id, child: Text(category.name)),
                          DropdownMenuItem(
                            value: _newCategoryValue,
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18, color: context.colors.primary),
                                SizedBox(width: 8),
                                Text('New category...',
                                    style: TextStyle(color: context.colors.primary)),
                              ],
                            ),
                          ),
                        ],
                        onChanged: _onCategoryChanged,
                      ),
                      const SizedBox(height: AppSpacing.gutter),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        controller: _costController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Cost price (₹)',
                          helperText:
                              'What you pay the supplier. Never shown to customers.',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          return double.tryParse(value) == null ? 'Enter a number' : null;
                        },
                      ),
                      _MarginPreview(
                        sellingPrice: double.tryParse(_priceController.text),
                        costPrice: double.tryParse(_costController.text),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Special item'),
                        subtitle: const Text(
                          'Announced to customers while it is in stock',
                        ),
                        secondary: Icon(
                          Icons.auto_awesome,
                          color: _isSpecial ? context.colors.primary : context.colors.outline,
                        ),
                        value: _isSpecial,
                        onChanged: (value) => setState(() => _isSpecial = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        subtitle: const Text('Visible to customers in the shop'),
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.base),
                        Text(
                          _errorMessage!,
                          style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.gutter),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _save,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_pendingImageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Image.memory(_pendingImageBytes!, fit: BoxFit.contain),
      );
    }
    if (_existingImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Image.network(_existingImageUrl!, fit: BoxFit.contain),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload, color: Colors.black45, size: 40),
          SizedBox(height: 8),
          Text('Tap to upload an image', style: TextStyle(color: Colors.black45)),
        ],
      ),
    );
  }
}

class _StockStepper extends StatelessWidget {
  const _StockStepper({required this.value, required this.onChange});

  final int value;
  final void Function(int delta) onChange;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Stock Level'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => onChange(-1),
            visualDensity: VisualDensity.compact,
          ),
          Text('$value', style: AppTextStyles.headlineSm),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onChange(1),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}


/// Live profit readout under the cost field, so the margin is visible
/// while typing rather than discovered later on a report.
class _MarginPreview extends StatelessWidget {
  const _MarginPreview({required this.sellingPrice, required this.costPrice});

  final double? sellingPrice;
  final double? costPrice;

  @override
  Widget build(BuildContext context) {
    if (sellingPrice == null || costPrice == null) return const SizedBox.shrink();

    final margin = sellingPrice! - costPrice!;
    final percent = sellingPrice! <= 0 ? 0.0 : (margin / sellingPrice!) * 100;
    final losing = margin < 0;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: Row(
        children: [
          Icon(
            losing ? Icons.trending_down : Icons.trending_up,
            size: 18,
            color: losing ? context.colors.error : context.colors.success,
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Text(
              losing
                  ? 'Selling below cost: ${formatInr(margin.abs())} lost per unit'
                  : 'Profit ${formatInr(margin)} per unit (${percent.toStringAsFixed(0)}%)',
              style: AppTextStyles.bodySm.copyWith(
                color: losing ? context.colors.error : context.colors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
