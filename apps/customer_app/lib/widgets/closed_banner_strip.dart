import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// The strip between the header and the search field.
///
/// It occupies the same height whether the shop is open or shut, so the
/// search bar never jumps as the status changes — and the gap it leaves
/// when open is deliberate breathing room under the K.G.S header rather
/// than wasted space.
class ClosedBannerStrip extends StatelessWidget {
  const ClosedBannerStrip({super.key, required this.store});

  final StoreSettings? store;

  /// Tall enough for the banner; reserved in both states.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final isOpen = store?.isOpen ?? true;

    // Unknown status (still loading) is treated as open: flashing
    // "closed" at someone for half a second while the row loads is worse
    // than showing nothing.
    if (isOpen) {
      return const SizedBox(height: height);
    }

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.containerPaddingMobile,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: context.colors.onErrorContainer),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: MarqueeText(
              text: store!.closedBanner,
              style: AppTextStyles.labelLg
                  .copyWith(color: context.colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
