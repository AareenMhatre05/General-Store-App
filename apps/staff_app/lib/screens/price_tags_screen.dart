import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import 'package:provider/provider.dart';

/// Printable shelf tags. Pick products, get a sheet of tags sized for
/// cutting out.
///
/// No PDF library involved: the sheet is laid out on screen and printed
/// with the device's own print/share function (browser print on the web
/// build, screenshot/share on Android). That keeps a printing dependency
/// and its platform channels out of the app for a feature used
/// occasionally.
class PriceTagsScreen extends StatefulWidget {
  const PriceTagsScreen({super.key});

  @override
  State<PriceTagsScreen> createState() => _PriceTagsScreenState();
}

class _PriceTagsScreenState extends State<PriceTagsScreen> {
  late Future<List<Product>> _loadFuture;
  final Set<String> _selected = {};
  String _search = '';
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<CatalogRepository>().getProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_previewing ? 'Tag Sheet' : 'Price Tags'),
        actions: [
          if (_previewing)
            TextButton(
              onPressed: () => setState(() => _previewing = false),
              child: const Text('Edit selection'),
            ),
        ],
      ),
      floatingActionButton: _selected.isEmpty || _previewing
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _previewing = true),
              icon: const Icon(Icons.print_outlined),
              label: Text('Preview ${_selected.length} tag'
                  '${_selected.length == 1 ? '' : 's'}'),
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

          final all = snapshot.data ?? [];
          if (_previewing) {
            return _TagSheet(
              products: all.where((p) => _selected.contains(p.id)).toList(),
            );
          }

          final products = all
              .where((p) =>
                  _search.isEmpty || p.name.toLowerCase().contains(_search.toLowerCase()))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) => setState(() => _search = value),
                        decoration: const InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_selected.length == products.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(products.map((p) => p.id));
                        }
                      }),
                      child: Text(
                        _selected.length == products.length ? 'None' : 'All',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return CheckboxListTile(
                      value: _selected.contains(product.id),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(product.id);
                        } else {
                          _selected.remove(product.id);
                        }
                      }),
                      title: Text(product.name, style: AppTextStyles.labelLg),
                      subtitle: Text(
                        '${formatInr(product.sellingPrice)} · ${product.unit}',
                        style: AppTextStyles.bodySm
                            .copyWith(color: context.colors.onSurfaceVariant),
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

/// The printable sheet itself. Deliberately white-on-black-free: tags
/// are printed on paper, so this section ignores the app's dark theme
/// and uses black on white to avoid flooding an inkjet.
class _TagSheet extends StatelessWidget {
  const _TagSheet({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        child: Wrap(
          spacing: AppSpacing.base,
          runSpacing: AppSpacing.base,
          children: [
            for (final product in products)
              Container(
                width: 180,
                padding: const EdgeInsets.all(AppSpacing.base * 1.5),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(AppRadius.dp),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'K.G.S',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      product.unit,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatInr(product.sellingPrice),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (product.hasActiveOffer || (product.mrp ?? 0) > product.price)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              formatInr(product.hasActiveOffer
                                  ? product.price
                                  : product.mrp!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (product.barcode != null)
                      Text(
                        product.barcode!,
                        style: const TextStyle(fontSize: 9, color: Colors.black38),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
