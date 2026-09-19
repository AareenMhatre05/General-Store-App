import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Pill badge for an order's status, coloured by what the status means
/// to the customer: in-flight (primary), done (success), stalled or
/// cancelled (error), waiting (neutral).
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  // Takes a context because the palette depends on the active
  // theme; a getter could not reach one.
  (Color, Color) _colors(BuildContext context) => switch (status) {
        OrderStatus.delivered => (context.colors.success, context.colors.onSuccess),
        OrderStatus.cancelled => (context.colors.errorContainer, context.colors.onErrorContainer),
        OrderStatus.pendingPayment => (context.colors.surfaceContainerHighest, context.colors.onSurfaceVariant),
        _ => (context.colors.primaryContainer, context.colors.onPrimaryContainer),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
