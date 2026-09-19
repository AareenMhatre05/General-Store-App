import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Reached when a staff/owner account somehow signs in here. Signs
/// them out immediately; the router's redirect then bounces to
/// /welcome once the auth state settles to unauthenticated.
class WrongRoleScreen extends StatefulWidget {
  const WrongRoleScreen({super.key});

  @override
  State<WrongRoleScreen> createState() => _WrongRoleScreenState();
}

class _WrongRoleScreenState extends State<WrongRoleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppAuthState>().signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This app is for customers only', style: AppTextStyles.headlineSm),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Signing you out...',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.gutter),
              CircularProgressIndicator(color: context.colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
