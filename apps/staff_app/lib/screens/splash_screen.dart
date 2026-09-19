import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: BrandMark(subtitle: 'Staff'),
      ),
    );
  }
}
