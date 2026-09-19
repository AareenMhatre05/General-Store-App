import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/order_status_chip.dart';

/// Everything needed to pack and hand over one order, plus the buttons
/// that move it through its lifecycle.
class StaffOrderDetailScreen extends StatefulWidget {
  const StaffOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<StaffOrderDetailScreen> createState() => _StaffOrderDetailScreenState();
}

class _StaffOrderDetailScreenState extends State<StaffOrderDetailScreen> {
  late final TableWatcher _watcher;
  late Future<void> _loadFuture;
  StaffOrder? _staffOrder;
  List<OrderItemDetail> _items = [];
  DeliveryPartner? _assignee;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // Reflects a delivery partner marking the drop, or another
    // staff member editing the same order.
    _watcher = TableWatcher(
      channelName: 'staff-order-detail',
      tables: const ['orders', 'order_items', 'delivery_assignments'],
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
    final deliveryRepository = context.read<DeliveryRepository>();
    final staffOrder = await orderRepository.getOrderForStaff(widget.orderId);
    final items = await orderRepository.getOrderItemsDetailed(widget.orderId);
    final assignee = await deliveryRepository.getAssignee(widget.orderId);
    setState(() {
      _staffOrder = staffOrder;
      _items = items;
      _assignee = assignee;
    });
  }

  /// Hands the order to a delivery partner, or takes it back.
  ///
  /// Until this happens the partner cannot see the order at all -- RLS
  /// scopes them to their own assignments -- so this is the moment the
  /// address and the customer's number become visible to them.
  Future<void> _chooseAssignee() async {
    final deliveryRepository = context.read<DeliveryRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final partners = await deliveryRepository.getPartners();

    if (!mounted) return;
    if (partners.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'No delivery partners yet. Invite one from Staff & Invites.',
        ),
      ));
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surfaceContainer,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              child: Text('Who is delivering this?',
                  style: AppTextStyles.headlineSm),
            ),
            for (final partner in partners)
              ListTile(
                leading: Icon(Icons.delivery_dining,
                    color: context.colors.primary),
                title: Text(partner.name),
                subtitle: partner.phone == null ? null : Text(partner.phone!),
                trailing: partner.id == _assignee?.id
                    ? Icon(Icons.check, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(partner.id),
              ),
            if (_assignee != null)
              ListTile(
                leading: Icon(Icons.person_remove_outlined,
                    color: context.colors.error),
                title: Text('Unassign',
                    style: TextStyle(color: context.colors.error)),
                onTap: () => Navigator.of(sheetContext).pop('__unassign__'),
              ),
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      if (choice == '__unassign__') {
        await deliveryRepository.unassign(widget.orderId);
      } else {
        await deliveryRepository.assign(
          orderId: widget.orderId,
          deliveryUserId: choice,
        );
      }
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not assign: $e')));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _advance(OrderStatus next) async {
    final orderRepository = context.read<OrderRepository>();
    setState(() => _isUpdating = true);
    try {
      await orderRepository.updateOrderStatus(widget.orderId, next);
      // Handing goods over in person settles a cash order.
      if (next == OrderStatus.delivered &&
          _staffOrder?.order.paymentStatus == PaymentStatus.pending) {
        await orderRepository.updatePaymentStatus(widget.orderId, PaymentStatus.paid);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markPaid() async {
    final orderRepository = context.read<OrderRepository>();
    setState(() => _isUpdating = true);
    try {
      await orderRepository.updatePaymentStatus(widget.orderId, PaymentStatus.paid);
      await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _cancel() async {
    final orderRepository = context.read<OrderRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Cancel this order?', style: AppTextStyles.headlineSm),
        content: Text(
          'Every item on it goes back into stock automatically. '
          'This cannot be undone.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Cancel Order', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      await orderRepository.updateOrderStatus(widget.orderId, OrderStatus.cancelled);
      await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Order Details')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          final staffOrder = _staffOrder;
          if (snapshot.hasError || staffOrder == null) {
            return Center(
              child: Text(
                'Could not load this order.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final order = staffOrder.order;
          final nextStatus = order.status.nextStatus;
          // An in-store sale is already complete when it's rung up --
          // there is nothing to prepare or deliver.
          final canAdvance = nextStatus != null && order.channel == OrderChannel.delivery;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            children: [
              _Card(
                title: '#${order.id.substring(0, 8).toUpperCase()}',
                trailing: OrderStatusChip(status: order.status),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(
                      icon: Icons.schedule,
                      text: 'Placed ${DateFormat('d MMM yyyy, h:mm a').format(order.createdAt.toLocal())}',
                    ),
                    if (order.scheduledFor != null)
                      _Line(
                        icon: Icons.event,
                        text: 'Scheduled for '
                            '${DateFormat('d MMM yyyy, h:mm a').format(order.scheduledFor!.toLocal())}',
                        color: context.colors.secondary,
                      ),
                    _Line(
                      icon: order.channel == OrderChannel.inStore
                          ? Icons.storefront
                          : Icons.delivery_dining,
                      text: order.channel == OrderChannel.inStore
                          ? 'In-store sale'
                          : 'Home delivery',
                    ),
                    _Line(
                      icon: order.paymentStatus == PaymentStatus.paid
                          ? Icons.check_circle_outline
                          : Icons.payments_outlined,
                      text: 'Payment: ${order.paymentStatus.name}',
                      color: order.paymentStatus == PaymentStatus.paid
                          ? context.colors.success
                          : context.colors.error,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.gutter),
              if (order.channel == OrderChannel.delivery)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.gutter),
                  child: _Card(
                    title: 'Deliver To',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(staffOrder.customerLabel, style: AppTextStyles.labelLg),
                        if (staffOrder.customerPhone != null)
                          _Line(icon: Icons.phone, text: staffOrder.customerPhone!),
                        if (staffOrder.addressSummary != null)
                          _Line(icon: Icons.location_on_outlined, text: staffOrder.addressSummary!),
                        if (order.distanceMeters != null)
                          _Line(
                            icon: Icons.straighten,
                            text: '${(order.distanceMeters! / 1000).toStringAsFixed(1)} km from the store',
                          ),
                      ],
                    ),
                  ),
                ),
              _Card(
                title: 'Items to Pack',
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
                                color: context.colors.primaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.dp),
                              ),
                              child: Text(
                                '${detail.item.quantity}',
                                style: AppTextStyles.labelLg
                                    .copyWith(color: context.colors.onPrimaryContainer),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.base),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(detail.productName, style: AppTextStyles.labelLg),
                                  if (detail.productUnit.isNotEmpty)
                                    Text(
                                      detail.productUnit,
                                      style: AppTextStyles.bodySm
                                          .copyWith(color: context.colors.onSurfaceVariant),
                                    ),
                                ],
                              ),
                            ),
                            Text(formatInr(detail.item.subtotal),
                                style: AppTextStyles.priceDisplay),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.gutter),
              _Card(
                title: 'Bill',
                child: Column(
                  children: [
                    _SummaryRow(label: 'Subtotal', value: formatInr(order.subtotalAmount)),
                    _SummaryRow(
                        label: 'Delivery Fee', value: formatInr(order.deliveryFeeAmount)),
                    const Divider(height: AppSpacing.gutter),
                    _SummaryRow(
                        label: 'Total', value: formatInr(order.totalAmount), isTotal: true),
                  ],
                ),
              ),
              if (order.channel == OrderChannel.delivery) ...[
                const SizedBox(height: AppSpacing.gutter),
                _Card(
                  title: 'Delivery partner',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _assignee == null
                          ? Icons.person_search_outlined
                          : Icons.delivery_dining,
                      color: _assignee == null
                          ? context.colors.onSurfaceVariant
                          : context.colors.primary,
                    ),
                    title: Text(
                      _assignee?.name ?? 'Nobody assigned yet',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurface),
                    ),
                    subtitle: Text(
                      _assignee == null
                          ? 'They see the address and the customer\'s number '
                              'only once assigned.'
                          : (_assignee!.phone ?? 'Carrying this order'),
                      style: AppTextStyles.bodySm
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    trailing: TextButton(
                      onPressed: _isUpdating ? null : _chooseAssignee,
                      child: Text(_assignee == null ? 'Assign' : 'Change'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.gutter),
              if (_isUpdating)
                Center(child: CircularProgressIndicator(color: context.colors.primary))
              else ...[
                if (canAdvance)
                  ElevatedButton.icon(
                    onPressed: () => _advance(nextStatus),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(order.status.advanceLabel!),
                  ),
                if (order.paymentStatus != PaymentStatus.paid &&
                    order.status != OrderStatus.cancelled) ...[
                  const SizedBox(height: AppSpacing.base),
                  OutlinedButton.icon(
                    onPressed: _markPaid,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Mark as Paid (cash)'),
                  ),
                ],
                // Only counter sales are editable: a delivery order the
                // customer placed should be cancelled and re-placed, not
                // silently rewritten underneath them.
                if (order.channel == OrderChannel.inStore &&
                    order.status != OrderStatus.cancelled) ...[
                  const SizedBox(height: AppSpacing.base),
                  OutlinedButton.icon(
                    onPressed: () => context
                        .push('/orders/${order.id}/edit')
                        .then((changed) {
                      if (changed == true) setState(() => _loadFuture = _load());
                    }),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit this sale'),
                  ),
                ],
                if (order.status.isOpen) ...[
                  const SizedBox(height: AppSpacing.base),
                  TextButton.icon(
                    onPressed: _cancel,
                    icon: Icon(Icons.close, color: context.colors.error),
                    label: Text('Cancel Order',
                        style: TextStyle(color: context.colors.error)),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

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

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? context.colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySm.copyWith(color: color ?? context.colors.onSurfaceVariant),
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isTotal
                ? AppTextStyles.headlineSm
                : AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
          ),
          Text(value,
              style: isTotal ? AppTextStyles.priceDisplay : AppTextStyles.bodyMd),
        ],
      ),
    );
  }
}
