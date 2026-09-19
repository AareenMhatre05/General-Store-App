import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon')),
    );
  }

  Future<void> _editProfile(Profile profile) async {
    final nameController = TextEditingController(text: profile.fullName ?? '');
    final phoneController = TextEditingController(text: profile.phone ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.containerPaddingMobile,
          right: AppSpacing.containerPaddingMobile,
          top: AppSpacing.containerPaddingMobile,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.containerPaddingMobile,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Profile', style: AppTextStyles.headlineSm),
            const SizedBox(height: AppSpacing.gutter),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: AppSpacing.base),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
            ),
            const SizedBox(height: AppSpacing.gutter),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final authRepository = context.read<AuthRepository>();
      final authState = context.read<AppAuthState>();
      final messenger = ScaffoldMessenger.of(context);
      try {
        await authRepository.updateProfile(
          fullName: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
          phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
        );
        await authState.refreshProfile();
      } on PhoneTakenException catch (_) {
        messenger.showSnackBar(const SnackBar(
          content: Text('That mobile number belongs to another account.'),
        ));
      } on FormatException catch (_) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Enter a 10-digit mobile number.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppAuthState>().profile;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: profile == null
          ? Center(child: CircularProgressIndicator(color: context.colors.primary))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: context.colors.primaryContainer,
                      child: Text(
                        (profile.fullName?.isNotEmpty ?? false)
                            ? profile.fullName![0].toUpperCase()
                            : '?',
                        style: AppTextStyles.headlineMd
                            .copyWith(color: context.colors.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gutter),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.fullName ?? 'Add your name', style: AppTextStyles.headlineSm),
                          const SizedBox(height: 4),
                          Text(
                            profile.phone ?? 'Add a mobile number',
                            style: AppTextStyles.bodySm
                                .copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _editProfile(profile),
                      icon: Icon(Icons.edit, color: context.colors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.gutter),
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.receipt_long, color: context.colors.primary),
                        title: const Text('My Orders'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/orders'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.favorite_border, color: context.colors.primary),
                        title: const Text('My Favourites'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/favorites'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.location_on_outlined, color: context.colors.primary),
                        title: const Text('Saved Addresses'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/addresses'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.brightness_6_outlined,
                            color: context.colors.primary),
                        title: const Text('Appearance'),
                        subtitle: Text(context.watch<ThemeController>().label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showAppearanceSheet(
                          context,
                          context.read<ThemeController>(),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.support_agent, color: context.colors.primary),
                        title: const Text('Help & Support'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showComingSoon('Help & support'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.gutter),
                Center(
                  child: Text(
                    'Build $kBuildStamp',
                    style: AppTextStyles.labelMd.copyWith(color: context.colors.outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                OutlinedButton.icon(
                  onPressed: () => context.read<AppAuthState>().signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Out'),
                ),
              ],
            ),
    );
  }
}
