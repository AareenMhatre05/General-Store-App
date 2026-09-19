import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Category management. Reached from the Inventory screen rather than
/// the main nav -- it's something you set up occasionally, not a daily
/// destination.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<void> _loadFuture;
  List<Category> _categories = [];
  Map<String, int> _productCounts = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final repository = context.read<CategoryRepository>();
    final categories = await repository.getAllCategories();
    final counts = await repository.getProductCounts();
    setState(() {
      _categories = categories;
      _productCounts = counts;
    });
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _showEditor({Category? existing}) async {
    final saved = await showCategoryEditor(context, existing: existing);
    if (saved != null) await _reload();
  }

  /// Category pictures make the customer's grid scannable -- six text
  /// tiles look alike, six photos do not.
  Future<void> _pickImage(Category category) async {
    final repository = context.read<CategoryRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    try {
      await repository.uploadCategoryImage(
        categoryId: category.id,
        bytes: await picked.readAsBytes(),
        fileExtension: picked.name.split('.').last,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Photo added to ${category.name}')),
      );
      await _reload();
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not upload that photo.')),
      );
    }
  }

  Future<void> _toggleActive(Category category, bool isActive) async {
    final repository = context.read<CategoryRepository>();
    await repository.updateCategory(id: category.id, isActive: isActive);
    await _reload();
  }

  Future<void> _confirmDelete(Category category) async {
    final productCount = _productCounts[category.id] ?? 0;
    final repository = context.read<CategoryRepository>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Delete "${category.name}"?', style: AppTextStyles.headlineSm),
        content: Text(
          productCount == 0
              ? 'This category has no products in it.'
              : '$productCount product${productCount == 1 ? '' : 's'} will become '
                  'uncategorized. The product${productCount == 1 ? '' : 's'} '
                  'will NOT be deleted.\n\nIf you only want to hide this '
                  'category from customers, turn it off instead.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await repository.deleteCategory(category.id);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Category'),
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
                'Could not load categories.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }
          if (_categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_outlined, size: 48, color: context.colors.outline),
                    const SizedBox(height: AppSpacing.base),
                    Text('No categories yet', style: AppTextStyles.headlineSm),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'Categories group products on the customer home screen. '
                      'Add one to get started.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                96, // clear of the FAB
              ),
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final productCount = _productCounts[category.id] ?? 0;

                return Container(
                  padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => _pickImage(category),
                        borderRadius: BorderRadius.circular(AppRadius.dp),
                        child: Container(
                          width: 44,
                          height: 44,
                          clipBehavior: Clip.antiAlias,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadius.dp),
                          ),
                          child: () {
                            final url = context
                                .read<CatalogRepository>()
                                .categoryImageUrl(category);
                            if (url == null) {
                              return Icon(Icons.add_a_photo_outlined,
                                  size: 18, color: context.colors.onSurfaceVariant);
                            }
                            return Image.network(
                              url,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Icon(
                                Icons.broken_image_outlined,
                                size: 18,
                                color: context.colors.onSurfaceVariant,
                              ),
                            );
                          }(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.name,
                              style: AppTextStyles.headlineSm.copyWith(
                                color: category.isActive
                                    ? context.colors.onSurface
                                    : context.colors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Order ${category.sortOrder} · '
                              '$productCount product${productCount == 1 ? '' : 's'}'
                              '${category.isActive ? '' : '  ·  Hidden from customers'}',
                              style: AppTextStyles.bodySm
                                  .copyWith(color: context.colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: category.isActive,
                        onChanged: (value) => _toggleActive(category, value),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, color: context.colors.primary),
                        onPressed: () => _showEditor(existing: category),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: context.colors.error),
                        onPressed: () => _confirmDelete(category),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Create/edit sheet, shared with the product form's inline "New
/// category" shortcut. Returns the saved category, or null if the sheet
/// was dismissed without saving.
Future<Category?> showCategoryEditor(BuildContext context, {Category? existing}) {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final sortController =
      TextEditingController(text: (existing?.sortOrder ?? 0).toString());
  final formKey = GlobalKey<FormState>();
  final repository = context.read<CategoryRepository>();

  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surfaceContainer,
    builder: (sheetContext) {
      var isSaving = false;
      String? errorMessage;

      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.containerPaddingMobile,
            right: AppSpacing.containerPaddingMobile,
            top: AppSpacing.containerPaddingMobile,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                AppSpacing.containerPaddingMobile,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'New Category' : 'Edit Category',
                  style: AppTextStyles.headlineSm,
                ),
                const SizedBox(height: AppSpacing.gutter),
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Dairy & Eggs',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: AppSpacing.base),
                TextFormField(
                  controller: sortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    helperText: 'Lower numbers show first on the customer home screen',
                  ),
                  validator: (value) => int.tryParse(value ?? '') == null
                      ? 'Enter a whole number'
                      : null,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    errorMessage!,
                    style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.gutter),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() {
                              isSaving = true;
                              errorMessage = null;
                            });
                            try {
                              final name = nameController.text.trim();
                              final sortOrder = int.parse(sortController.text);
                              final saved = existing == null
                                  ? await repository.createCategory(
                                      name: name,
                                      sortOrder: sortOrder,
                                    )
                                  : await repository.updateCategory(
                                      id: existing.id,
                                      name: name,
                                      sortOrder: sortOrder,
                                    );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(saved);
                              }
                            } catch (e) {
                              setSheetState(() {
                                isSaving = false;
                                errorMessage =
                                    'Could not save the category. Check your connection and try again.';
                              });
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
