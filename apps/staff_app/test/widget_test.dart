import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'package:staff/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows the invite-code signup link', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Have an invite code? Sign up'), findsOneWidget);
  });
}
