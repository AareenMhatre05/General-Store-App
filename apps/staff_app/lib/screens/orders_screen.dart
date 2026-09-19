import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/order_status_chip.dart';
import '../widgets/staff_scaffold.dart';

/// The fulfilment queue: every order, newest first, filtered by status.
/// This is the screen that actually lets the store run -- without it an
/// order can be placed but never progressed.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// "Open" is the default because it's the working view: everything that
/// still needs someone to do something.
enum _OrderFilter { open, all, delivered, cancelled }

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<StaffOrder>> _loadFuture;
  _OrderFilter _filter = _OrderFilter.open;
  late final TableWatcher _watcher;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // A new order should appear on the counter phone by itself. Waiting
    // for someone to pull down is how an order gets missed.
    _watcher = TableWatcher(
      channelName: 'staff-orders-list',
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

  Future<List<StaffOrder>> _load() {
    final orderRepository = context.read<OrderRepository>();
    return switch (_filter) {
      _OrderFilter.delivered =>
        orderRepository.getOrdersForStaff(status: OrderStatus.delivered),
      _OrderFilter.cancelled =>
        orderRepository.getOrdersForStaff(status: OrderStatus.cancelled),
      // Open is a client-side narrowing of "all", because it spans
      // several statuses and PostgREST can't express "in (…)" through
      // the typed filter chain as cleanly as one round trip plus a
      // where().
      _OrderFilter.open || _OrderFilter.all => orderRepository.getOrdersForStaff(),
    };
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  List<StaffOrder> _applyClientFilter(List<StaffOrder> orders) {
    if (_filter != _OrderFilter.open) return orders;
    return orders.where((o) => o.order.status.isOpen).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StaffScaffold(
      currentIndex: 1,
      title: 'Orders',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/in-store-sale').then((_) => _reload()),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('In-Store Sale'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.containerPaddingMobile,
              AppSpacing.base,
              AppSpacing.containerPaddingMobile,
              0,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _OrderFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.base),
                      child: ChoiceChip(
                        label: Text(switch (filter) {
                          _OrderFilter.open => 'Needs action',
                          _OrderFilter.all => 'All',
                          _OrderFilter.delivered => 'Delivered',
                          _OrderFilter.cancelled => 'Cancelled',
                        }),
                        selected: _filter == filter,
                        onSelected: (_) {
                          setState(() {
                            _filter = filter;
                            _loadFuture = _load();
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<StaffOrder>>(
              future: _loadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(
                    child: CircularProgressIndicator(color: context.colors.primary),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load orders.',
                      style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
                    ),
                  );
                }

                final orders = _applyClientFilter(snapshot.data ?? []);
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 48, color: context.colors.outline),
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            _filter == _OrderFilter.open
                                ? 'Nothing needs action right now'
                                : 'No orders here',
                            style: AppTextStyles.headlineSm,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
                    itemBuilder: (context, index) => _OrderCard(
                      staffOrder: orders[index],
                      onTap: () => context
                          .push('/orders/${orders[index].order.id}')
                          .then((_) => _reload()),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.staffOrder, required this.onTap});

  final StaffOrder staffOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final order = staffOrder.order;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: order.status == OrderStatus.pendingPayment
                ? context.colors.primary
                : context.colors.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  order.channel == OrderChannel.inStore
                      ? Icons.storefront
                      : Icons.delivery_dining,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '#${order.id.substring(0, 8).toUpperCase()}  ·  ${staffOrder.customerLabel}',
                    style: AppTextStyles.labelLg,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                OrderStatusChip(status: order.status, compact: true),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('d MMM, h:mm a').format(order.createdAt.toLocal()),
                    style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
                if (order.paymentStatus != PaymentStatus.paid &&
                    order.channel == OrderChannel.delivery)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.base),
                    child: Text(
                      'Unpaid',
                      style: AppTextStyles.labelMd.copyWith(color: context.colors.error),
                    ),
                  ),
                Text(formatInr(order.totalAmount), style: AppTextStyles.priceDisplay),
              ],
            ),
            if (order.scheduledFor != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: context.colors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    'For ${DateFormat('d MMM, h:mm a').format(order.scheduledFor!.toLocal())}',
                    style: AppTextStyles.bodySm.copyWith(color: context.colors.secondary),
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
