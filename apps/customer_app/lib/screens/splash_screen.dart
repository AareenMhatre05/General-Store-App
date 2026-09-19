import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Shown only while the initial session/profile check is in flight.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: BrandMark(
          logoAsset: 'assets/brand/logo_transparent.png',
          subtitle: 'Daily Essentials At your Doorstep',
        ),
      ),
    );
  }
}
