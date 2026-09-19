import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared/shared.dart';

/// The "Already have an account? Log in" link was invisible in light mode.
///
/// Cause: it was built with [RichText], which -- unlike [Text] and
/// [Text.rich] -- does not merge the ambient [DefaultTextStyle]. The
/// enclosing [TextButton] publishes its foreground colour through
/// exactly that mechanism, so the span kept the colourless
/// [AppTextStyles.labelMd] and was painted with the framework's default
/// rather than anything the palette chose.
///
/// These assert on the colour each *run of text* actually resolves to,
/// after merging parent styles the way the painter does -- not on the
/// outermost span, which belongs to the button rather than to us.

/// Every leaf run of text, paired with the colour it will be painted in.
List<(String, Color?)> _runs(WidgetTester tester) {
  final paragraph =
      tester.renderObject<RenderParagraph>(find.byType(RichText).first);
  final runs = <(String, Color?)>[];

  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final merged = inherited?.merge(span.style) ?? span.style;
    if (span.text != null && span.text!.isNotEmpty) {
      runs.add((span.text!, merged?.color));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, merged);
    }
  }

  walk(paragraph.text, null);
  return runs;
}

void main() {
  // The text styles come from google_fonts, which tries to fetch over
  // HTTP; a widget test has no network and throws. The metrics do not
  // matter here -- only the colour resolved onto each run does.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(child: TextButton(onPressed: () {}, child: child)),
        ),
      ),
    );
  }

  testWidgets('RichText in a TextButton resolves to no colour -- the bug',
      (tester) async {
    await pump(
      tester,
      AppTheme.light,
      RichText(
        text: TextSpan(
          style: AppTextStyles.labelMd,
          children: const [TextSpan(text: 'Already have an account? ')],
        ),
      ),
    );
    // Nothing in the chain supplies one: the button's foreground travels
    // by DefaultTextStyle, which RichText does not read.
    expect(_runs(tester).single.$2, isNull);
  });

  for (final (name, isDark) in [('light', false), ('dark', true)]) {
    testWidgets('every run of the link is coloured in $name mode',
        (tester) async {
      // Resolved inside the test: AppTheme.light touches google_fonts,
      // and building these in a top-level list would run that during
      // main(), before setUpAll can switch fetching off.
      final palette = isDark ? AppPalette.dark : AppPalette.light;
      await pump(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        Builder(
          builder: (context) => Text.rich(
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
      );

      final runs = _runs(tester);
      expect(runs.map((r) => r.$2), everyElement(isNotNull),
          reason: 'a run with no colour is at the mercy of a framework '
              'default that knows nothing about the palette');

      final question =
          runs.firstWhere((r) => r.$1.contains('Already have an account'));
      final link = runs.firstWhere((r) => r.$1.contains('Log in'));
      expect(question.$2, palette.onSurfaceVariant);
      expect(link.$2, palette.primary);
    });
  }
}
