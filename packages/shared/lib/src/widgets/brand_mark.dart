import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// The K.G.S mark with a progress ring around it, for splash and other
/// full-screen waits.
///
/// A bare spinner says "something is happening"; this says *whose* app
/// is happening.
///
/// [logoAsset] is passed in rather than hard-coded because the artwork
/// belongs to the app, not to this package: the customer app ships a
/// logo, the staff app does not, and a shared widget should not assume
/// an asset exists in whichever bundle happens to be running. Without
/// one — or if the file is missing — it falls back to the lettered mark
/// drawn from the type and colour tokens.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.subtitle,
    this.showProgress = true,
    this.size = 116,
    this.logoAsset,
  });

  /// Small line under the store name, e.g. "Staff" or a tagline.
  final String? subtitle;
  final bool showProgress;
  final double size;

  /// Path to the app's logo, e.g. `assets/brand/logo.png`.
  final String? logoAsset;

  /// The pre-artwork mark, still used by the staff app and as the
  /// fallback if the logo file is ever missing from a build.
  Widget _letteredMark(BuildContext context, double innerSize) => Container(
        width: innerSize,
        height: innerSize,
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          'K.G.S',
          style: AppTextStyles.headlineMd.copyWith(
            color: context.colors.onPrimaryContainer,
            letterSpacing: 0.5,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final innerSize = size * 0.78;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showProgress)
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: context.colors.primary,
                  ),
                ),
              SizedBox(
                width: innerSize,
                height: innerSize,
                child: logoAsset == null
                    ? _letteredMark(context, innerSize)
                    : Image.asset(
                        logoAsset!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) =>
                            _letteredMark(context, innerSize),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.gutter),
        Text(
          'Kavita General Stores',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSm,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
