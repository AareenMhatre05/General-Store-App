import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

class StaffScaffold extends StatelessWidget {
  const StaffScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.actions = const [],
  });

  final int currentIndex; // 0 Dashboard, 1 Orders, 2 Inventory, 3 Offers, 4 Sales
  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  /// Screen-specific buttons, shown in the app bar on narrow layouts and
  /// beside the title on wide ones.
  final List<Widget> actions;

  // Five is the practical ceiling for a bottom bar, so Settings moved to
  // an app-bar action to make room for Sales -- it is consulted daily,
  // whereas settings are touched once in a while.
  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard', path: '/dashboard'),
    (icon: Icons.receipt_long, label: 'Orders', path: '/orders'),
    (icon: Icons.inventory_2, label: 'Inventory', path: '/inventory'),
    (icon: Icons.local_offer, label: 'Offers', path: '/offers'),
    (icon: Icons.bar_chart, label: 'Sales', path: '/sales'),
  ];

  void _onDestinationSelected(BuildContext context, int index) {
    if (index != currentIndex) {
      context.go(_destinations[index].path);
    }
  }

  void _showSettingsSheet(BuildContext context) {
    final profile = context.read<AppAuthState>().profile;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile?.fullName ?? 'Staff account', style: AppTextStyles.headlineSm),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Role: ${profile?.role.name ?? ''}',
              style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
            ),
            Text(
              'Build $kBuildStamp',
              style: AppTextStyles.labelMd.copyWith(color: context.colors.outline),
            ),
            const Divider(height: AppSpacing.gutter),
            // Secondary destinations -- things you set up or consult
            // occasionally, rather than every day.
            for (final item in const [
              (icon: Icons.forum_outlined, label: 'Customer Questions', path: '/chat'),
              (icon: Icons.group_outlined, label: 'Staff & Invites', path: '/team'),
              (icon: Icons.storefront, label: 'Store Settings', path: '/store-settings'),
              (icon: Icons.category_outlined, label: 'Categories', path: '/categories'),
              (icon: Icons.sell_outlined, label: 'Price Tags', path: '/price-tags'),
              (icon: Icons.delete_sweep_outlined, label: 'Expired & Damaged', path: '/writeoffs'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(item.icon, color: context.colors.primary),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(item.path);
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.brightness_6_outlined, color: context.colors.primary),
              title: const Text('Appearance'),
              subtitle: Text(context.watch<ThemeController>().label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showAppearanceSheet(
                context,
                context.read<ThemeController>(),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<AppAuthState>().signOut();
                },
                child: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: context.colors.surfaceContainerLowest,
              selectedIndex: currentIndex,
              onDestinationSelected: (index) => _onDestinationSelected(context, index),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.gutter),
                child: Text('K.G.S', style: AppTextStyles.headlineMd),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.gutter),
                    child: IconButton(
                      onPressed: () => _showSettingsSheet(context),
                      icon: const Icon(Icons.settings),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingDesktop),
                    child: Row(
                      children: [
                        Expanded(child: Text(title, style: AppTextStyles.headlineLg)),
                        ...actions,
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsSheet(context),
          ),
        ],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) => _onDestinationSelected(context, index),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
