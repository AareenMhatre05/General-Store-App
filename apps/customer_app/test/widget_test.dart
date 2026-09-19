import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'package:customer/screens/welcome_screen.dart';

void main() {
  testWidgets('Welcome screen shows the Get Started CTA', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const WelcomeScreen()),
    );

    expect(find.text('Get Started'), findsOneWidget);
    expect(find.textContaining('Log in'), findsOneWidget);
  });
}
