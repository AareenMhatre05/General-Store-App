import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import 'special_item_announcer.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.imageUrl,
    required this.onTap,
    required this.onAdd,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final Product product;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final bool isFavorite;

  /// Null hides the heart entirely, for surfaces where saving makes no
  /// sense (the staff app reuses this card).
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    // Two independent reasons to show a struck-through price: an active
    // offer beats the list price, or the list price already beats the
    // printed MRP. Prefer the offer, since that's the live saving.
    final strikeThrough = product.hasActiveOffer
        ? product.price
        : (product.mrp != null && product.mrp! > product.price ? product.mrp : null);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base * 1.5),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: product.isSpecial
                ? context.colors.primary.withValues(alpha: 0.5)
                : context.colors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        // The image takes whatever height is left rather than forcing a
        // square. A fixed AspectRatio(1) here overflowed the grid cell,
        // which pushed the price row and the + button outside the card's
        // bounds -- and a widget painted outside its parent receives no
        // taps, so "add to cart" silently did nothing.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _image(context)),
                  if (product.isSpecial)
                    const Positioned(top: 4, left: 4, child: SpecialBadge()),
                  // Opposite corner to the special badge so the two never
                  // collide on an item that is both.
                  if (onToggleFavorite != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: context.colors.surfaceContainerHighest
                            .withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onToggleFavorite,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color: isFavorite
                                  ? context.colors.error
                                  : context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(product.unit, style: AppTextStyles.labelMd),
            const SizedBox(height: 2),
            Text(
              product.name,
              style: AppTextStyles.labelLg,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.base),
            _priceRow(context, strikeThrough),
          ],
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.dp),
      child: Container(
        width: double.infinity,
        color: Colors.white,
        child: imageUrl == null
            ? const Icon(Icons.shopping_basket_outlined,
                color: Colors.black26, size: 32)
            : Image.network(
                imageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.shopping_basket_outlined,
                  color: Colors.black26,
                  size: 32,
                ),
              ),
      ),
    );
  }

  Widget _priceRow(BuildContext context, double? strikeThrough) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatInr(product.sellingPrice),
                style: AppTextStyles.priceDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (strikeThrough != null)
                Text(
                  formatInr(strikeThrough),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.base),
        // Material + InkWell rather than a bare Container so the ripple
        // lands on the button itself, making it obvious the tap
        // registered on the button and not the card.
        Material(
          color: context.colors.primary,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onAdd,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.add, color: context.colors.onPrimary, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}
