import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadius.xl),
                  bottomRight: Radius.circular(AppRadius.xl),
                ),
                // A local asset, not the hot-linked googleusercontent URL
                // this screen shipped with: that was a leftover from the
                // Stitch mockup, it was somebody else's image, and the
                // day the URL expired every new user would have met a
                // grey box on the very first screen.
                child: Image.asset(
                  'assets/brand/welcome.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: context.colors.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const BrandMark(showProgress: false, size: 140),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // No mark, name or slogan here: the artwork above
                    // already carries all three, and repeating them
                    // makes one screen say the same thing twice.
                    Text(
                      'Your neighbourhood general store is now just a tap away.',
                      style: AppTextStyles.bodyLg.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/signup'),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Get Started'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: () => context.push('/login'),
                      // Text.rich, not RichText: RichText does not merge
                      // the ambient DefaultTextStyle, which is how the
                      // enclosing TextButton passes its colour down. The
                      // span was left colourless and painted with a
                      // framework default that ignores the palette --
                      // invisible in light mode. The colour is also set
                      // explicitly here rather than left to inheritance,
                      // so the two halves stay distinguishable.
                      child: Text.rich(
                        TextSpan(
                          style: AppTextStyles.labelMd
                              .copyWith(color: context.colors.onSurfaceVariant),
                          children: [
                            const TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Log in',
                              style: TextStyle(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
