import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../cart/cart_controller.dart';
import 'addresses_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Future<void> _loadFuture;
  List<Address> _addresses = [];
  Address? _selected;

  double? _deliveryFee;
  bool _resolvingFee = false;
  DateTime? _scheduledFor;
  bool _isPlacingOrder = false;
  String? _errorMessage;
  LocationFailure? _settingsFailure;

  StoreSettings? _store;
  late final TableWatcher _watcher;

  bool get _isClosed => _store?.isOpen == false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadAddresses();
    // So the checkout unlocks the moment the shop flips the switch,
    // rather than leaving someone staring at a disabled button that is
    // no longer telling the truth.
    _watcher = TableWatcher(
      channelName: 'cart-store-state',
      tables: const ['store_settings'],
      onChange: _refreshStoreState,
    )..start();
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  Future<void> _refreshStoreState() async {
    try {
      final store = await context.read<CatalogRepository>().getStoreSettings();
      if (mounted) setState(() => _store = store);
    } catch (_) {
      // Leave the last known state rather than guessing; the server
      // refuses an out-of-hours order regardless of what this says.
    }
  }

  Future<void> _loadAddresses() async {
    final addresses = await context.read<AddressRepository>().getMyAddresses();
    setState(() => _addresses = addresses);
    await _refreshStoreState();
    // getMyAddresses() sorts defaults first, so the first row is the
    // one to pre-select.
    if (addresses.isNotEmpty) await _select(addresses.first);
  }

  /// Selecting an address prices the delivery for it. The fee shown
  /// here is an estimate -- the authoritative number is recomputed by a
  /// trigger when the order is inserted.
  Future<void> _select(Address address) async {
    final catalog = context.read<CatalogRepository>();
    setState(() {
      _selected = address;
      _resolvingFee = true;
      _errorMessage = null;
    });
    try {
      final fee = await catalog.getDeliveryFeeForCoords(
            latitude: address.latitude,
            longitude: address.longitude,
          );
      setState(() => _deliveryFee = fee);
    } catch (e) {
      setState(() => _deliveryFee = null);
    } finally {
      if (mounted) setState(() => _resolvingFee = false);
    }
  }

  /// Opens the map picker, which starts at wherever the customer is
  /// standing. Checkout used to have a second "use current" shortcut
  /// that saved an address outright as "Current Location, Current
  /// Location, 000000" -- useless to a delivery person looking for a
  /// door. Both paths now go through the pin + details flow.
  Future<void> _addAddress() async {
    final addressRepository = context.read<AddressRepository>();
    final saved = await context.push<Address>('/address/pick');
    if (saved == null) return;
    final addresses = await addressRepository.getMyAddresses();
    setState(() => _addresses = addresses);
    await _select(saved);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  static String _formatSchedule(DateTime when) {
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final period = when.hour < 12 ? 'AM' : 'PM';
    return '${when.day}/${when.month}, $hour:$minute $period';
  }

  /// Picks a slot and places the order in one go, so "schedule" is a
  /// single action rather than a checkbox you might forget to tick.
  ///
  /// A scheduled order is a request, not a booking: it lands as
  /// `scheduled` and the shop confirms or declines it, because only they
  /// know whether that slot is workable.
  Future<void> _scheduleOrder() async {
    await _pickSchedule();
    if (!mounted || _scheduledFor == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Schedule this order?', style: AppTextStyles.headlineSm),
        content: Text(
          'You are asking for delivery around '
          '${_formatSchedule(_scheduledFor!)}. The shop will confirm whether '
          'that time works, and you will see the answer on the order.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Change time'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Request this slot'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _placeOrder();
  }

  Future<void> _placeOrder() async {
    final cart = context.read<CartController>();
    final orderRepository = context.read<OrderRepository>();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_selected == null) {
      setState(() => _errorMessage = 'Choose where this should be delivered.');
      return;
    }
    // Belt and braces: the button is hidden while closed, and the
    // database refuses the row anyway. This is only so the person gets a
    // sentence instead of a raised exception.
    if (_isClosed && _scheduledFor == null) {
      setState(() => _errorMessage =
          'The shop is closed right now. You can schedule this order for '
          'later instead.');
      return;
    }
    setState(() {
      _isPlacingOrder = true;
      _errorMessage = null;
    });
    try {
      final order = await orderRepository.placeDeliveryOrder(
        deliveryAddressId: _selected!.id,
        items: cart.lines
            .map((line) => OrderLineInput(
                  productId: line.product.id,
                  quantity: line.quantity,
                  unitPrice: line.product.sellingPrice,
                ))
            .toList(),
        scheduledFor: _scheduledFor,
      );
      cart.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Order placed!')));
      // Reset to Home and then open the new order on top of it: the cart
      // is finished with, and backing out of the order should land on
      // Home rather than an emptied cart.
      router.go('/home');
      router.push('/orders/${order.id}');
    } on OrderException catch (e) {
      // The server's own words: usually a constraint or policy name that
      // says exactly what went wrong. A bare "try again" sends people
      // round the same loop with nothing new to go on. The one case
      // worth translating is the shop closing between opening the cart
      // and pressing the button.
      final closed = e.message.contains('STORE_CLOSED');
      if (closed) _refreshStoreState();
      setState(() => _errorMessage = closed
          ? 'The shop closed just now. You can still schedule this order '
              'for later.'
          : 'Could not place the order — ${e.message}');
    } catch (e) {
      setState(() => _errorMessage = 'Could not place the order. Please try again.');
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final subtotal = cart.subtotal;
    final deliveryFee = _deliveryFee ?? 0;
    final total = subtotal + deliveryFee;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Your Cart')),
      // "Empty" is a claim, and it would be a false one while the saved
      // cart is still being fetched back from the last session.
      body: cart.isRestoring && cart.isEmpty
          ? Center(child: CircularProgressIndicator(color: context.colors.primary))
          : cart.isEmpty
          ? Center(
              child: Text(
                'Your cart is empty.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      title: 'Order Items',
                      child: Column(
                        children: [
                          for (final line in cart.lines)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: context.colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(AppRadius.dp),
                                    ),
                                    child: Icon(Icons.shopping_basket_outlined,
                                        color: context.colors.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: AppSpacing.base),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(line.product.name, style: AppTextStyles.labelLg),
                                        Text(
                                          line.product.unit,
                                          style: AppTextStyles.bodySm
                                              .copyWith(color: context.colors.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () => context
                                        .read<CartController>()
                                        .updateQuantity(line.product.id, line.quantity - 1),
                                  ),
                                  Text('${line.quantity}', style: AppTextStyles.bodyMd),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => context
                                        .read<CartController>()
                                        .updateQuantity(line.product.id, line.quantity + 1),
                                  ),
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      formatInr(line.subtotal),
                                      textAlign: TextAlign.end,
                                      style: AppTextStyles.priceDisplay,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    _SectionCard(
                      title: 'Deliver To',
                      child: FutureBuilder<void>(
                        future: _loadFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
                              child: Center(
                                child: CircularProgressIndicator(color: context.colors.primary),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_addresses.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                                  child: Text(
                                    'No saved addresses yet.',
                                    style: AppTextStyles.bodySm
                                        .copyWith(color: context.colors.onSurfaceVariant),
                                  ),
                                )
                              else
                                for (final address in _addresses)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                                    child: AddressCard(
                                      address: address,
                                      selected: _selected?.id == address.id,
                                      onTap: () => _select(address),
                                    ),
                                  ),
                              // One action, not two: both used to open
                              // different flows, and the quick one produced
                              // unusable placeholder addresses.
                              TextButton.icon(
                                onPressed: _addAddress,
                                icon: const Icon(Icons.add_location_alt_outlined),
                                label: Text(_addresses.isEmpty
                                    ? 'Add your delivery address'
                                    : 'Add another address'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    _SectionCard(
                      title: 'When',
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: context.colors.primary),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: Text(
                              _scheduledFor == null
                                  ? 'Deliver as soon as possible'
                                  : 'Scheduled for ${_scheduledFor!.toLocal()}',
                              style: AppTextStyles.bodyMd,
                            ),
                          ),
                          TextButton(
                            onPressed: _pickSchedule,
                            child: Text(_scheduledFor == null ? 'Schedule' : 'Change'),
                          ),
                          if (_scheduledFor != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _scheduledFor = null),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    _SectionCard(
                      title: 'Order Summary',
                      child: Column(
                        children: [
                          _SummaryRow(label: 'Subtotal', value: formatInr(subtotal)),
                          _SummaryRow(
                            label: 'Delivery Fee',
                            value: _resolvingFee
                                ? '...'
                                : (_selected == null ? '—' : formatInr(deliveryFee)),
                          ),
                          const Divider(height: AppSpacing.gutter),
                          _SummaryRow(
                            label: 'Total',
                            value: formatInr(total),
                            isTotal: true,
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        _errorMessage!,
                        style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                      ),
                      if (_settingsFailure != null)
                        TextButton.icon(
                          onPressed: () => const LocationService()
                              .openRelevantSettings(_settingsFailure!),
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('Open settings'),
                        ),
                    ],
                    const SizedBox(height: AppSpacing.gutter),
                    if (_isClosed) ...[
                      _ClosedNotice(message: _store!.closedBanner),
                      const SizedBox(height: AppSpacing.base),
                    ],
                    // Ordering for right now is off while the shop is
                    // shut; scheduling stays available, because ordering
                    // tonight for tomorrow morning is exactly what it is
                    // for. The shop confirms or declines the slot.
                    ElevatedButton.icon(
                      onPressed:
                          (_isPlacingOrder || _isClosed) ? null : _placeOrder,
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: _isPlacingOrder && _scheduledFor == null
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isClosed
                              ? 'Shop closed'
                              : 'Place Order - ${formatInr(total)}'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    OutlinedButton.icon(
                      onPressed: _isPlacingOrder ? null : _scheduleOrder,
                      icon: const Icon(Icons.schedule),
                      label: Text(_scheduledFor == null
                          ? 'Schedule for later'
                          : 'Schedule for ${_formatSchedule(_scheduledFor!)}'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: () {
                        cart.clear();
                        context.canPop() ? context.pop() : context.go('/home');
                      },
                      child: const Text('Cancel Order'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

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
          Text(title, style: AppTextStyles.headlineSm),
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

/// Shown at checkout when the shop is shut: says so plainly, and points
/// at the thing that still works rather than leaving a dead button with
/// no explanation.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storefront_outlined, color: context.colors.error),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The shop is closed right now',
                  style: AppTextStyles.labelLg
                      .copyWith(color: context.colors.onErrorContainer),
                ),
                const SizedBox(height: 2),
                Text(
                  '$message\n\nYou can schedule this order for later, and the '
                  'shop will confirm the time.',
                  style: AppTextStyles.bodySm
                      .copyWith(color: context.colors.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
