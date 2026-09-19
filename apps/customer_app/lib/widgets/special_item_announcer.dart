import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Announces special items the shop has put in stock.
///
/// Shown once per item, tracked locally: the point is "look what just
/// arrived", and an app that repeats itself every launch trains people
/// to dismiss it without reading. Local storage is the right home for
/// that -- it is a per-install preference, not shop data.
///
/// This is the in-app half of the feature. Reaching someone whose app is
/// closed needs push notifications, which need a Firebase project set up
/// first (see RELEASE.md).
class SpecialItemAnnouncer extends StatefulWidget {
  const SpecialItemAnnouncer({super.key, required this.child});

  final Widget child;

  @override
  State<SpecialItemAnnouncer> createState() => _SpecialItemAnnouncerState();
}

class _SpecialItemAnnouncerState extends State<SpecialItemAnnouncer> {
  static const _seenKey = 'announced_special_product_ids';

  @override
  void initState() {
    super.initState();
    // After the first frame: this runs inside the widget tree that owns
    // the navigator the dialog needs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final catalog = context.read<CatalogRepository>();

    try {
      final specials = await catalog.getSpecialProducts();
      if (specials.isEmpty || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_seenKey) ?? const <String>[];

      final fresh = specials.where((p) => !seen.contains(p.id)).toList();
      if (fresh.isEmpty || !mounted) return;

      // Remember before showing: a dialog dismissed by a back gesture
      // still counts as seen, and nagging is worse than missing one.
      await prefs.setStringList(
        _seenKey,
        // Keep only ids that are still special, so the list cannot grow
        // without bound as the shop's specials rotate.
        {...specials.map((p) => p.id)}.toList(),
      );

      if (!mounted) return;
      // Tapping outside dismisses: an announcement should never trap
      // someone who just wants to get on with shopping.
      final goTo = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _SpecialItemDialog(products: fresh),
      );
      if (goTo != null && mounted) context.push('/product/$goTo');
    } catch (_) {
      // An announcement is a nicety. If it fails, the shop still works.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SpecialItemDialog extends StatelessWidget {
  const _SpecialItemDialog({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final headline = products.first;

    return AlertDialog(
      backgroundColor: context.colors.surfaceContainer,
      icon: Icon(Icons.auto_awesome, color: context.colors.primary, size: 32),
      title: Text(
        products.length == 1 ? 'Just in!' : '${products.length} specials just in!',
        style: AppTextStyles.headlineSm,
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                Text(
                  headline.name,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineSm
                      .copyWith(color: context.colors.onPrimaryContainer),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatInr(headline.sellingPrice)} · ${headline.unit}',
                  style: AppTextStyles.bodySm
                      .copyWith(color: context.colors.onPrimaryContainer),
                ),
              ],
            ),
          ),
          if (products.length > 1) ...[
            const SizedBox(height: AppSpacing.base),
            Text(
              'Also in: ${products.skip(1).take(3).map((p) => p.name).join(', ')}'
              '${products.length > 4 ? ' and more' : ''}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm
                  .copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            // Returns the product id so the caller can navigate; the
            // dialog does not push routes itself, which keeps it usable
            // from anywhere.
            onPressed: () => Navigator.of(context).pop(headline.id),
            child: const Text('Take me there'),
          ),
        ),
      ],
    );
  }
}

/// Ribbon on a product card for a special item.
class SpecialBadge extends StatelessWidget {
  const SpecialBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 11, color: context.colors.onPrimary),
          const SizedBox(width: 3),
          Text(
            'Special',
            style: AppTextStyles.labelMd.copyWith(
              color: context.colors.onPrimary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
