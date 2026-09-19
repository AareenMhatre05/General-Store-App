import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the shop when a customer writes in.
///
/// Wraps the whole app via `MaterialApp.builder`, so a question is
/// announced whatever screen the counter phone happens to be showing --
/// a message that only surfaces once you open the Chat inbox is a
/// message nobody sees.
///
/// This works over the Realtime socket the app already holds, so it
/// needs no Firebase. The limitation is honest: it only fires while the
/// app is open. Reaching a phone whose app is closed needs a push
/// service, which is a separate piece of work.
class NewMessageWatcher extends StatefulWidget {
  const NewMessageWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<NewMessageWatcher> createState() => _NewMessageWatcherState();
}

class _NewMessageWatcherState extends State<NewMessageWatcher> {
  RealtimeChannel? _channel;
  bool _isStaffSide = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only listen once somebody is signed in: RLS would return nothing
    // otherwise, and there would be no inbox to send them to.
    final role = context.watch<AppAuthState>().profile?.role;
    final shouldListen = role != null && role.isStaffSide;
    if (shouldListen == _isStaffSide) return;
    _isStaffSide = shouldListen;
    shouldListen ? _subscribe() : _unsubscribe();
  }

  void _subscribe() {
    _channel = supabase.channel('staff-inbound-messages')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'product_inquiries',
        callback: (payload) => _announce(payload.newRecord),
      )
      ..subscribe();
  }

  void _unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) supabase.removeChannel(channel);
  }

  void _announce(Map<String, dynamic> row) {
    if (!mounted) return;
    // Staff replies come through this channel too; announcing those
    // would buzz the phone for what the person just typed.
    if (row['sender_role'] != 'customer') return;

    final customerId = row['customer_id'] as String?;
    if (customerId == null) return;
    final productId = row['product_id'] as String?;
    final message = (row['message'] as String? ?? '').trim();

    // A counter phone is often face-up and unattended; a silent banner
    // is a missed customer.
    HapticFeedback.vibrate();

    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: context.colors.surfaceContainerHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.chat_bubble,
                      size: 16, color: context.colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'New customer message',
                    style: AppTextStyles.labelLg
                        .copyWith(color: context.colors.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                message.length > 90 ? '${message.substring(0, 90)}…' : message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySm
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Open',
            textColor: context.colors.primary,
            onPressed: () => context.push(
              '/chat/$customerId/${ChatThreadRoute.encode(productId)}',
              extra: productId == null ? 'Chat with the shop' : 'Product enquiry',
            ),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
