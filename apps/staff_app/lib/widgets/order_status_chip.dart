import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Pill badge for an order's status. Same colour logic as the customer
/// app's chip, kept separate so each app can diverge without the other
/// noticing.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status, this.compact = false});

  final OrderStatus status;
  final bool compact;

  // Takes a context because the palette depends on the active
  // theme; a getter could not reach one.
  (Color, Color) _colors(BuildContext context) => switch (status) {
        OrderStatus.delivered => (context.colors.success, context.colors.onSuccess),
        OrderStatus.cancelled => (context.colors.errorContainer, context.colors.onErrorContainer),
        OrderStatus.pendingPayment => (context.colors.surfaceContainerHighest, context.colors.onSurfaceVariant),
        OrderStatus.scheduled => (context.colors.secondaryContainer, context.colors.onSecondaryContainer),
        _ => (context.colors.primaryContainer, context.colors.onPrimaryContainer),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.labelMd.copyWith(color: foreground),
      ),
    );
  }
}
