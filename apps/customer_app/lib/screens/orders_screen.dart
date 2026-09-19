import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/order_status_chip.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final TableWatcher _watcher;
  late Future<void> _loadFuture;
  List<Order> _orders = [];
  Map<String, int> _itemCounts = {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // The shop confirming or dispatching shows up without a pull.
    _watcher = TableWatcher(
      channelName: 'customer-orders-list',
      tables: const ['orders'],
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

  Future<void> _load() async {
    final orderRepository = context.read<OrderRepository>();
    final orders = await orderRepository.getMyOrders();
    final counts =
        await orderRepository.getItemCounts(orders.map((o) => o.id).toList());
    setState(() {
      _orders = orders;
      _itemCounts = counts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('My Orders')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load your orders.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }
          if (_orders.isEmpty) {
            return const _EmptyOrders();
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              itemCount: _orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, index) {
                final order = _orders[index];
                return _OrderCard(
                  order: order,
                  itemCount: _itemCounts[order.id] ?? 0,
                  onTap: () => context.push('/orders/${order.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: context.colors.outline),
            const SizedBox(height: AppSpacing.base),
            Text('No orders yet', style: AppTextStyles.headlineSm),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Your past and ongoing orders will show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.gutter),
            ElevatedButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
              child: const Text('Start Shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.itemCount,
    required this.onTap,
  });

  final Order order;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${order.id.substring(0, 8).toUpperCase()}',
                    style: AppTextStyles.labelLg,
                  ),
                ),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('d MMM yyyy, h:mm a').format(order.createdAt.toLocal())}'
                    '${itemCount > 0 ? '  ·  $itemCount item${itemCount == 1 ? '' : 's'}' : ''}',
                    style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
                Text(formatInr(order.totalAmount), style: AppTextStyles.priceDisplay),
              ],
            ),
            if (order.scheduledFor != null) ...[
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: context.colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Scheduled for '
                    '${DateFormat('d MMM, h:mm a').format(order.scheduledFor!.toLocal())}',
                    style: AppTextStyles.bodySm.copyWith(color: context.colors.primary),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
