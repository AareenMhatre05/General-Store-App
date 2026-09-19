import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared/shared.dart';

import '../widgets/order_status_chip.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final TableWatcher _watcher;
  late Future<void> _loadFuture;
  Order? _order;
  List<OrderItemDetail> _items = [];
  Address? _address;
  PartnerPosition? _partner;
  Timer? _partnerPoll;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // Watching this screen while the order moves is the point of it.
    _watcher = TableWatcher(
      channelName: 'customer-order-detail',
      tables: const ['orders', 'delivery_assignments', 'delivery_locations'],
      onChange: () {
        if (mounted) setState(() => _loadFuture = _load());
      },
    )..start();
  }

  @override
  void dispose() {
    _partnerPoll?.cancel();
    _watcher.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final orderRepository = context.read<OrderRepository>();
    final addressRepository = context.read<AddressRepository>();
    final order = await orderRepository.getOrder(widget.orderId);
    final items = await orderRepository.getOrderItemsDetailed(widget.orderId);

    Address? address;
    if (order.deliveryAddressId != null) {
      try {
        address = await addressRepository.getAddress(order.deliveryAddressId!);
      } catch (_) {
        // A missing address should not blank the whole order.
      }
    }

    if (!mounted) return;
    setState(() {
      _order = order;
      _items = items;
      _address = address;
    });
    _syncTracking();
  }

  /// The map is only worth drawing while something is actually moving.
  /// Realtime already wakes this screen when a position row changes, but
  /// a slow tick as well means a dot that keeps up even if one event is
  /// missed on a patchy connection.
  void _syncTracking() {
    final isMoving = _order?.status == OrderStatus.outForDelivery;
    if (isMoving && _partnerPoll == null) {
      _refreshPartner();
      _partnerPoll = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _refreshPartner(),
      );
    } else if (!isMoving && _partnerPoll != null) {
      _partnerPoll?.cancel();
      _partnerPoll = null;
      if (mounted) setState(() => _partner = null);
    }
  }

  Future<void> _refreshPartner() async {
    try {
      final position =
          await context.read<DeliveryRepository>().getPartnerPosition();
      if (mounted) setState(() => _partner = position);
    } catch (_) {
      // Position is a nicety; the order still reads fine without it.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Order Details'),
        // Reached by push from the orders list, and by a fresh stack
        // straight after checkout -- so pop when there's something to pop
        // back to, and fall back to the orders list when there isn't.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/orders'),
        ),
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          final order = _order;
          if (snapshot.hasError || order == null) {
            return Center(
              child: Text(
                'Could not load this order.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                _SectionCard(
                  title: 'Order #${order.id.substring(0, 8).toUpperCase()}',
                  trailing: OrderStatusChip(status: order.status),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Placed ${DateFormat('d MMM yyyy, h:mm a').format(order.createdAt.toLocal())}',
                        style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                      if (order.scheduledFor != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Scheduled for '
                          '${DateFormat('d MMM yyyy, h:mm a').format(order.scheduledFor!.toLocal())}',
                          style: AppTextStyles.bodySm.copyWith(color: context.colors.primary),
                        ),
                      ],
                      if (order.status != OrderStatus.cancelled) ...[
                        const SizedBox(height: AppSpacing.gutter),
                        _StatusTimeline(status: order.status),
                      ],
                      if (order.status == OrderStatus.outForDelivery &&
                          _address != null) ...[
                        const SizedBox(height: AppSpacing.gutter),
                        DeliveryMap(
                          destination:
                              LatLng(_address!.latitude, _address!.longitude),
                          partner: _partner == null
                              ? null
                              : LatLng(_partner!.latitude, _partner!.longitude),
                          partnerLabel: _partner?.isStale == true
                              ? 'Last seen a few minutes ago'
                              : 'Your order is on the way',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.gutter),
                _SectionCard(
                  title: 'Items',
                  child: Column(
                    children: [
                      for (final detail in _items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: context.colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(AppRadius.dp),
                                ),
                                child: Text(
                                  '${detail.item.quantity}x',
                                  style: AppTextStyles.labelMd,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.base),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(detail.productName, style: AppTextStyles.labelLg),
                                    Text(
                                      '${detail.productUnit.isEmpty ? '' : '${detail.productUnit}  ·  '}'
                                      '${formatInr(detail.item.unitPrice)} each',
                                      style: AppTextStyles.bodySm
                                          .copyWith(color: context.colors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatInr(detail.item.subtotal),
                                style: AppTextStyles.priceDisplay,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.gutter),
                _SectionCard(
                  title: 'Bill Summary',
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Subtotal', value: formatInr(order.subtotalAmount)),
                      _SummaryRow(
                        label: 'Delivery Fee',
                        value: formatInr(order.deliveryFeeAmount),
                      ),
                      const Divider(height: AppSpacing.gutter),
                      _SummaryRow(
                        label: 'Total Paid',
                        value: formatInr(order.totalAmount),
                        isTotal: true,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Payment: ${order.paymentStatus.name}',
                          style: AppTextStyles.bodySm
                              .copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                if (order.paymentStatus != PaymentStatus.paid &&
                    order.status != OrderStatus.cancelled) ...[
                  const SizedBox(height: AppSpacing.gutter),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.payments_outlined, color: context.colors.primary),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(
                          child: Text(
                            'Pay ${formatInr(order.totalAmount)} in cash when your '
                            'order arrives.',
                            style: AppTextStyles.bodySm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.gutter),
                  _SectionCard(
                    title: 'Notes',
                    child: Text(order.notes!, style: AppTextStyles.bodyMd),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal progress rail through confirmed → out for delivery →
/// delivered. An order still awaiting payment/scheduled sits before the
/// first step, so nothing is filled in yet.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});

  final OrderStatus status;

  static const _icons = {
    OrderStatus.confirmed: Icons.check_circle_outline,
    OrderStatus.outForDelivery: Icons.delivery_dining,
    OrderStatus.delivered: Icons.home_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final steps = OrderStatus.progressSteps;
    final currentIndex = steps.indexOf(status); // -1 while pending/scheduled

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= currentIndex ? context.colors.primary : context.colors.outlineVariant,
              ),
            ),
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: i <= currentIndex
                      ? context.colors.primaryContainer
                      : context.colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _icons[steps[i]],
                  size: 18,
                  color: i <= currentIndex
                      ? context.colors.onPrimaryContainer
                      : context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 64,
                child: Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd.copyWith(
                    color: i <= currentIndex ? context.colors.onSurface : context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.headlineSm)),
              ?trailing,
            ],
          ),
          const Divider(height: AppSpacing.gutter),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.isTotal = false});

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final labelStyle = isTotal
        ? AppTextStyles.headlineSm
        : AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant);
    final valueStyle = isTotal ? AppTextStyles.priceDisplay : AppTextStyles.bodyMd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
