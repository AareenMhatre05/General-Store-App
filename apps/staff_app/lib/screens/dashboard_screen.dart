import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/staff_scaffold.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TableWatcher _watcher;
  late Future<_DashboardData> _loadFuture;
  StoreSettings? _store;
  bool _togglingOpen = false;

  /// Open/closed sits on the Dashboard rather than buried in settings:
  /// it is flipped twice a day, which makes it the most-used control in
  /// the app.
  Future<void> _setOpen(bool isOpen) async {
    final storeRepository = context.read<StoreRepository>();
    setState(() => _togglingOpen = true);
    try {
      await storeRepository.setOpen(isOpen: isOpen);
      final refreshed = await storeRepository.getSettings();
      if (mounted) setState(() => _store = refreshed);
    } finally {
      if (mounted) setState(() => _togglingOpen = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // Today's totals and the low-stock count move on their own.
    _watcher = TableWatcher(
      channelName: 'staff-dashboard',
      tables: const ['orders', 'products'],
      onChange: () {
        if (mounted) setState(() => _loadFuture = _load());
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  Future<_DashboardData> _load() async {
    final orderRepository = context.read<OrderRepository>();
    final catalogRepository = context.read<CatalogRepository>();
    // Read before the awaits, per Decisions.md D22.
    final storeRepository = context.read<StoreRepository>();
    final orders = await orderRepository.getAllOrders();
    final products = await catalogRepository.getProducts();
    _store = await storeRepository.getSettings();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final todaysOrders = orders.where((o) => o.createdAt.isAfter(startOfToday));
    final totalSalesToday = todaysOrders.fold(0.0, (sum, o) => sum + o.totalAmount);
    final pendingDeliveries = orders
        .where((o) =>
            o.channel == OrderChannel.delivery &&
            (o.status == OrderStatus.confirmed ||
                o.status == OrderStatus.outForDelivery))
        .length;
    final lowStockCount = products.where((p) => p.stockQuantity < 10).length;

    return _DashboardData(
      totalSalesToday: totalSalesToday,
      pendingDeliveries: pendingDeliveries,
      lowStockCount: lowStockCount,
      recentOrders: orders.take(10).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StaffScaffold(
      currentIndex: 0,
      title: 'Dashboard',
      body: FutureBuilder<_DashboardData>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load dashboard.', style: TextStyle(color: context.colors.error)),
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                _OpenClosedCard(
                  store: _store,
                  busy: _togglingOpen,
                  onChanged: _setOpen,
                ),
                const SizedBox(height: AppSpacing.gutter),
                Wrap(
                  spacing: AppSpacing.gutter,
                  runSpacing: AppSpacing.gutter,
                  children: [
                    _SummaryCard(
                      icon: Icons.payments,
                      label: 'Total Sales Today',
                      value: formatInr(data.totalSalesToday),
                    ),
                    _SummaryCard(
                      icon: Icons.local_shipping,
                      label: 'Pending Deliveries',
                      value: '${data.pendingDeliveries} Orders',
                      isAlert: data.pendingDeliveries > 0,
                    ),
                    _SummaryCard(
                      icon: Icons.inventory_2,
                      label: 'Low Stock Items',
                      value: '${data.lowStockCount} Alerts',
                      isAlert: data.lowStockCount > 0,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                        child: Text('Recent Sales', style: AppTextStyles.headlineSm),
                      ),
                      const Divider(height: 1),
                      if (data.recentOrders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                          child: Text(
                            'No sales yet.',
                            style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        )
                      else
                        for (final order in data.recentOrders)
                          _RecentSaleTile(order: order),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardData {
  _DashboardData({
    required this.totalSalesToday,
    required this.pendingDeliveries,
    required this.lowStockCount,
    required this.recentOrders,
  });

  final double totalSalesToday;
  final int pendingDeliveries;
  final int lowStockCount;
  final List<Order> recentOrders;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    this.isAlert = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: context.colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.dp),
            ),
            child: Icon(icon, color: context.colors.onTertiaryContainer),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(label, style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            value,
            style: isAlert
                ? AppTextStyles.headlineMd.copyWith(color: context.colors.error)
                : AppTextStyles.headlineMd,
          ),
        ],
      ),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final isDelivery = order.channel == OrderChannel.delivery;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colors.surfaceContainerHighest,
        child: Icon(
          isDelivery ? Icons.directions_bike : Icons.storefront,
          color: context.colors.primary,
        ),
      ),
      title: Text(
        isDelivery ? 'Delivery Order' : 'Store Purchase',
        style: AppTextStyles.labelLg,
      ),
      subtitle: Text(
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
        style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatInr(order.totalAmount), style: AppTextStyles.priceDisplay),
          Text(
            order.status.name,
            style: AppTextStyles.labelMd.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}


/// The shop's open/closed switch.
///
/// Deliberately loud: staff need to see the current state without
/// reading, because forgetting to reopen is the failure that quietly
/// costs a morning's orders.
class _OpenClosedCard extends StatelessWidget {
  const _OpenClosedCard({
    required this.store,
    required this.busy,
    required this.onChanged,
  });

  final StoreSettings? store;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isOpen = store?.isOpen ?? true;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: isOpen ? context.colors.primaryContainer : context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(
            isOpen ? Icons.storefront : Icons.no_meals,
            color: isOpen
                ? context.colors.onPrimaryContainer
                : context.colors.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOpen ? 'Shop is OPEN' : 'Shop is CLOSED',
                  style: AppTextStyles.headlineSm.copyWith(
                    color: isOpen
                        ? context.colors.onPrimaryContainer
                        : context.colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOpen
                      ? 'Customers can browse and order'
                      : 'Customers see a closed banner',
                  style: AppTextStyles.bodySm.copyWith(
                    color: isOpen
                        ? context.colors.onPrimaryContainer
                        : context.colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: isOpen, onChanged: onChanged),
        ],
      ),
    );
  }
}
