import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// The delivery partner's whole app: the drops assigned to them.
///
/// They see nothing else. That is enforced in the database, not here --
/// RLS scopes orders, addresses and profiles to rows with an assignment
/// naming this account, so an unassigned order is invisible rather than
/// merely unlisted.
class MyDeliveriesScreen extends StatefulWidget {
  const MyDeliveriesScreen({super.key});

  @override
  State<MyDeliveriesScreen> createState() => _MyDeliveriesScreenState();
}

class _MyDeliveriesScreenState extends State<MyDeliveriesScreen> {
  late Future<void> _loadFuture;
  late final TableWatcher _watcher;
  List<DeliveryJob> _jobs = [];

  Timer? _locationTimer;
  bool _sharingLocation = false;
  String? _locationProblem;
  LatLng? _myPosition;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    // A drop assigned while the phone is in a pocket should be there
    // when it comes out.
    _watcher = TableWatcher(
      channelName: 'my-deliveries',
      tables: const ['delivery_assignments', 'orders'],
      onChange: () {
        if (mounted) setState(() => _loadFuture = _load());
      },
    )..start();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _watcher.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final jobs = await context.read<DeliveryRepository>().getMyDeliveries();
    if (!mounted) return;
    setState(() => _jobs = jobs);
    _syncLocationSharing();
  }

  bool get _hasActiveDrop => _jobs.any((j) => !j.isDone);

  /// Location is shared only while there is a drop in hand, and stops by
  /// itself when the last one is delivered. Tracking somebody who is not
  /// currently working is not something this app should do.
  void _syncLocationSharing() {
    if (_hasActiveDrop && !_sharingLocation) {
      _startSharing();
    } else if (!_hasActiveDrop && _sharingLocation) {
      _stopSharing();
    }
  }

  Future<void> _startSharing() async {
    _sharingLocation = true;
    await _pushOnce();
    // Every 20 seconds: frequent enough for a customer watching a van
    // approach, gentle enough not to flatten the phone mid-round.
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _pushOnce(),
    );
  }

  void _stopSharing() {
    _sharingLocation = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    if (mounted) setState(() => _locationProblem = null);
  }

  Future<void> _pushOnce() async {
    final locationService = context.read<LocationService>();
    final deliveryRepository = context.read<DeliveryRepository>();
    try {
      final position = await locationService.current();
      if (mounted) {
        setState(() =>
            _myPosition = LatLng(position.latitude, position.longitude));
      }
      await deliveryRepository.pushLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
      if (mounted && _locationProblem != null) {
        setState(() => _locationProblem = null);
      }
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() => _locationProblem = switch (failure.kind) {
            LocationFailureKind.serviceDisabled =>
              'Location is switched off. The shop and the customer cannot '
                  'see where you are.',
            LocationFailureKind.permissionDenied ||
            LocationFailureKind.permissionPermanentlyDenied =>
              'This app needs location permission while you are delivering.',
            _ => 'Could not read your location just now.',
          });
    } catch (_) {
      // A single failed upload is not worth interrupting a round over;
      // the next tick tries again.
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Opens the drop on the app's own map.
  ///
  /// The map answers "where is it, and where am I relative to it", which
  /// is what you need standing outside a building. It does not attempt
  /// turn-by-turn: that is a job a dedicated navigation app does far
  /// better, so the sheet offers a hand-off for the drive itself.
  Future<void> _showOnMap(DeliveryJob job) async {
    final address = job.address;
    if (address == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order ${job.reference}', style: AppTextStyles.headlineSm),
              const SizedBox(height: AppSpacing.base),
              DeliveryMap(
                destination: LatLng(address.latitude, address.longitude),
                partner: _myPosition,
                partnerLabel: 'You',
                height: 320,
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                [
                  address.label,
                  address.line1,
                  address.line2,
                  address.city,
                  address.pincode,
                ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
                style: AppTextStyles.bodySm
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.base),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openInMapsApp(address),
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Turn-by-turn in a maps app'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInMapsApp(Address address) async {
    // geo: hands off to whichever maps app the phone actually has,
    // rather than assuming Google Maps is installed.
    final uri = Uri.parse(
      'geo:${address.latitude},${address.longitude}'
      '?q=${address.latitude},${address.longitude}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Cash taken at the door. Kept separate from "Delivered" on purpose:
  /// an order can be handed over and paid for at different moments, and
  /// the shop's outstanding-cash figure should reflect what actually
  /// happened rather than assuming the two always coincide.
  Future<void> _markPaid(DeliveryJob job) async {
    final deliveryRepository = context.read<DeliveryRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Payment received?', style: AppTextStyles.headlineSm),
        content: Text(
          'Confirm you have taken ${formatInr(job.totalAmount)} in cash for '
          'order ${job.reference}. This cannot be undone from here.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, received'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deliveryRepository.markPaid(job);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not record: $e')));
    }
  }

  Future<void> _advance(DeliveryJob job) async {
    final deliveryRepository = context.read<DeliveryRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (job.pickedUpAt == null) {
        await deliveryRepository.markPickedUp(job);
      } else {
        await deliveryRepository.markDelivered(job);
      }
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _jobs.where((j) => !j.isDone).toList();
    final done = _jobs.where((j) => j.isDone).toList();

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('My Deliveries'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppAuthState>().signOut(),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done && _jobs.isEmpty) {
            return Center(
                child: CircularProgressIndicator(color: context.colors.primary));
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _loadFuture = _load());
              await _loadFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              children: [
                _LocationBanner(
                  sharing: _sharingLocation,
                  problem: _locationProblem,
                  hasWork: _hasActiveDrop,
                ),
                const SizedBox(height: AppSpacing.gutter),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      'Nothing to deliver right now.\nThe shop will assign '
                      'orders to you here.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  )
                else
                  for (final job in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _JobCard(
                        job: job,
                        onCall: job.customerPhone == null
                            ? null
                            : () => _call(job.customerPhone!),
                        onNavigate:
                            job.address == null ? null : () => _showOnMap(job),
                        onAdvance: () => _advance(job),
                        onMarkPaid:
                            job.isPaid ? null : () => _markPaid(job),
                      ),
                    ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.gutter),
                  Text('Completed', style: AppTextStyles.headlineSm),
                  const SizedBox(height: AppSpacing.base),
                  for (final job in done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _JobCard(
                        job: job,
                        onMarkPaid:
                            job.isPaid ? null : () => _markPaid(job),
                      ),
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

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({
    required this.sharing,
    required this.problem,
    required this.hasWork,
  });

  final bool sharing;
  final String? problem;
  final bool hasWork;

  @override
  Widget build(BuildContext context) {
    final isProblem = problem != null;
    final isIdle = !hasWork;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: isProblem
            ? context.colors.errorContainer
            : context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isProblem ? context.colors.error : context.colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isProblem
                ? Icons.location_off
                : (sharing ? Icons.my_location : Icons.location_searching),
            color: isProblem ? context.colors.error : context.colors.primary,
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Text(
              problem ??
                  (isIdle
                      ? 'Location sharing is off. It turns on by itself when '
                          'you have a delivery.'
                      : 'Sharing your location so the shop and the customer '
                          'can follow the delivery.'),
              style: AppTextStyles.bodySm.copyWith(
                color: isProblem
                    ? context.colors.onErrorContainer
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    this.onCall,
    this.onNavigate,
    this.onAdvance,
    this.onMarkPaid,
  });

  final DeliveryJob job;
  final VoidCallback? onCall;
  final VoidCallback? onNavigate;
  final VoidCallback? onAdvance;
  final VoidCallback? onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final address = job.address;
    final muted = job.isDone;

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
              Expanded(
                child: Text(
                  'Order ${job.reference}',
                  style: AppTextStyles.labelLg.copyWith(
                    color: muted
                        ? context.colors.onSurfaceVariant
                        : context.colors.onSurface,
                  ),
                ),
              ),
              Text(
                formatInr(job.totalAmount),
                style: AppTextStyles.labelLg.copyWith(
                  color: job.isPaid
                      ? context.colors.onSurfaceVariant
                      : context.colors.primary,
                ),
              ),
              if (job.isPaid) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified, size: 16, color: context.colors.success),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          _Line(icon: Icons.person_outline, text: job.customerName),
          if (job.customerPhone != null)
            _Line(icon: Icons.phone_outlined, text: job.customerPhone!),
          if (address != null)
            _Line(
              icon: Icons.location_on_outlined,
              text: [
                address.label,
                address.line1,
                address.line2,
                address.city,
                address.pincode,
              ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', '),
            ),
          if (job.notes != null && job.notes!.trim().isNotEmpty)
            _Line(icon: Icons.sticky_note_2_outlined, text: job.notes!),
          if (!muted) ...[
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                if (onCall != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCall,
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('Call'),
                    ),
                  ),
                if (onCall != null && onNavigate != null)
                  const SizedBox(width: AppSpacing.base),
                if (onNavigate != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onNavigate,
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: const Text('Navigate'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAdvance,
                icon: Icon(job.pickedUpAt == null
                    ? Icons.shopping_bag_outlined
                    : Icons.check_circle_outline),
                label: Text(job.pickedUpAt == null
                    ? 'Picked up from shop'
                    : 'Delivered'),
              ),
            ),
          ],
          // Outside the "still active" block on purpose: cash is often
          // handed over after the goods, and a delivered-but-unpaid
          // order is the one the shop most needs recorded.
          if (onMarkPaid != null) ...[
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMarkPaid,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Payment received - ${formatInr(job.totalAmount)}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: SelectableText(
              text,
              style: AppTextStyles.bodySm
                  .copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
