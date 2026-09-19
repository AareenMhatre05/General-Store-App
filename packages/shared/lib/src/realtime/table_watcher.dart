import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_bootstrap.dart';

/// Calls [onChange] whenever a row in any of [tables] is inserted,
/// updated or deleted.
///
/// Screens here load through `Future`s rather than streams, and there is
/// no appetite for rewriting all of them into stream builders. This is
/// the smaller change that gets the same result: the existing reload
/// runs by itself when the data behind it actually moves, instead of
/// only when somebody pulls to refresh.
///
/// Two details that matter in practice:
///
///  * **Debounced.** One action often writes several rows -- placing an
///    order touches `orders` and every `order_items` row -- and each
///    arrives as its own event. Without a pause they would each trigger
///    a reload, so a five-item order would refetch six times.
///  * **RLS still applies.** Realtime delivers only rows the subscriber
///    is allowed to read, so a delivery partner is not woken by orders
///    that are none of their business.
class TableWatcher {
  TableWatcher({
    required this.channelName,
    required this.tables,
    required this.onChange,
    this.debounce = const Duration(milliseconds: 400),
  });

  /// Must be unique per live subscription: two channels sharing a name
  /// fight over the same topic.
  final String channelName;
  final List<String> tables;
  final void Function() onChange;
  final Duration debounce;

  RealtimeChannel? _channel;
  Timer? _timer;
  bool _disposed = false;

  void start() {
    if (_channel != null || _disposed) return;
    var channel = supabase.channel(channelName);
    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _schedule(),
      );
    }
    _channel = channel..subscribe();
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!_disposed) onChange();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) supabase.removeChannel(channel);
  }
}
