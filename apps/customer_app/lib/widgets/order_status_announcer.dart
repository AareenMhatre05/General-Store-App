import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the customer the moment the shop accepts their order.
///
/// Wraps the whole app through `MaterialApp.builder`, so the news
/// arrives wherever they happen to be -- still shopping, in the cart, or
/// looking at something else entirely. Waiting on the order screen to
/// watch a chip change is not something anyone should have to do.
///
/// Only two transitions are worth interrupting someone for: the shop
/// saying yes, and the shop saying no. A declined order matters more
/// than most -- a scheduled slot the shop cannot work is something the
/// customer needs to know about while there is still time to reorder.
/// Everything else (packed, on its way) is visible on the order screen
/// and does not warrant a dialog.
class OrderStatusAnnouncer extends StatefulWidget {
  const OrderStatusAnnouncer({super.key, required this.child});

  final Widget child;

  @override
  State<OrderStatusAnnouncer> createState() => _OrderStatusAnnouncerState();
}

class _OrderStatusAnnouncerState extends State<OrderStatusAnnouncer> {
  RealtimeChannel? _channel;
  String? _userId;

  /// Orders already announced, so a reconnect or a second event for the
  /// same change cannot show the dialog twice.
  final _announced = <String>{};
  bool _dialogOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AppAuthState>().profile?.id;
    if (userId == _userId) return;
    _userId = userId;
    _unsubscribe();
    if (userId != null) _subscribe(userId);
  }

  void _subscribe(String userId) {
    _channel = supabase.channel('customer-order-status:$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'customer_id',
          value: userId,
        ),
        callback: (payload) => _onUpdate(payload.oldRecord, payload.newRecord),
      )
      ..subscribe();
  }

  void _unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) supabase.removeChannel(channel);
  }

  void _onUpdate(Map<String, dynamic> before, Map<String, dynamic> after) {
    if (!mounted || _dialogOpen) return;

    final orderId = after['id'] as String?;
    final now = after['status'] as String?;
    // `orders` is REPLICA IDENTITY FULL, so this is the real previous
    // status rather than an empty placeholder. Without the comparison,
    // every later edit to a confirmed order would re-announce it.
    final was = before['status'] as String?;
    if (orderId == null || now == null || now == was) return;

    final accepted = now == 'confirmed';
    final declined = now == 'declined';
    if (!accepted && !declined) return;
    if (!_announced.add('$orderId:$now')) return;

    _show(orderId: orderId, accepted: accepted);
  }

  Future<void> _show({required String orderId, required bool accepted}) async {
    _dialogOpen = true;
    HapticFeedback.mediumImpact();

    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        icon: Icon(
          accepted ? Icons.check_circle : Icons.cancel_outlined,
          size: 40,
          color: accepted ? context.colors.success : context.colors.error,
        ),
        title: Text(
          accepted ? 'Your order is accepted' : 'The shop could not take this order',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSm,
        ),
        content: Text(
          accepted
              ? 'K.G.S has confirmed your order and is getting it ready. '
                  'You can follow it on the order screen.'
              : 'This usually means the time you asked for was not workable. '
                  'Nothing has been charged — you can place it again for '
                  'another time.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd
              .copyWith(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('View order'),
          ),
        ],
      ),
    );

    _dialogOpen = false;
    if (open == true && mounted) context.push('/orders/$orderId');
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
