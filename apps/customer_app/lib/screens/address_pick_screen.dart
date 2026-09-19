import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Zomato-style address capture, in two steps.
///
/// Step 1 (this screen): move the map under a fixed centre pin. The
/// pin's coordinates are reverse-geocoded into a readable area name, so
/// you confirm a *place*, not a pair of numbers.
///
/// Step 2 ([_AddressDetailsSheet]): the bits a map can never know --
/// flat number, floor, landmark -- plus a Home/Work/Other tag.
///
/// Tiles come from OpenStreetMap: no API key, no billing account. The
/// trade-off is OSM's usage policy, which is fine at one shop's volume
/// but expects the identifying user agent set below.
class AddressPickScreen extends StatefulWidget {
  const AddressPickScreen({super.key, this.existing});

  /// When editing, the map opens on the saved pin and the form starts
  /// pre-filled.
  final Address? existing;

  @override
  State<AddressPickScreen> createState() => _AddressPickScreenState();
}

class _AddressPickScreenState extends State<AddressPickScreen> {
  final _mapController = MapController();
  final _geocoder = Geocoding();

  /// Falls back to the shop itself, so a first-time user with location
  /// off still opens somewhere meaningful rather than mid-ocean.
  static const _storeFallback = LatLng(19.3473375, 72.8118594);

  LatLng _pin = _storeFallback;
  bool _locating = false;
  bool _resolvingAddress = false;
  String? _areaLabel;
  String? _pincode;
  String? _city;
  String? _errorMessage;
  LocationFailure? _settingsFailure;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _pin = LatLng(existing.latitude, existing.longitude);
      _city = existing.city;
      _pincode = existing.pincode;
      _resolveAddress();
    } else {
      // No saved pin: jump to where the user actually is.
      WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Reverse-geocode the pin. Debounced, because the map fires a stream
  /// of positions while a finger is dragging and each lookup is a
  /// platform call.
  void _scheduleResolve() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _resolveAddress);
  }

  Future<void> _resolveAddress() async {
    setState(() => _resolvingAddress = true);
    try {
      // geocoding 5.x is instance-based; the old top-level
      // placemarkFromCoordinates() was removed in 4.0.
      final places =
          await _geocoder.placemarkFromCoordinates(_pin.latitude, _pin.longitude);
      if (!mounted) return;
      final place = places.isEmpty ? null : places.first;
      setState(() {
        _areaLabel = place == null
            ? null
            : <String?>[
                place.name,
                place.subLocality,
                place.locality,
              ].where((p) => (p ?? '').trim().isNotEmpty).join(', ');
        _city = (place?.locality?.trim().isNotEmpty ?? false)
            ? place!.locality
            : _city;
        _pincode = (place?.postalCode?.trim().isNotEmpty ?? false)
            ? place!.postalCode
            : _pincode;
      });
    } catch (e) {
      // Geocoding is a convenience: without it we still have exact
      // coordinates, which is what delivery pricing actually needs.
      if (mounted) setState(() => _areaLabel = null);
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _errorMessage = null;
      _settingsFailure = null;
    });
    try {
      final position = await const LocationService().current();
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      setState(() => _pin = target);
      _mapController.move(target, 17);
      await _resolveAddress();
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _settingsFailure = e.canOpenSettings ? e : null;
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirm() async {
    final saved = await showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (_) => _AddressDetailsSheet(
        existing: widget.existing,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        areaLabel: _areaLabel,
        city: _city,
        pincode: _pincode,
      ),
    );
    if (saved != null && mounted) context.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Set Location' : 'Edit Location'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 17,
                    onPositionChanged: (position, hasGesture) {
                      if (!hasGesture) return;
                      _pin = position.center;
                      _scheduleResolve();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.kavitageneralstores.customer',
                    ),
                  ],
                ),
                // The pin is fixed to the centre of the viewport and the
                // map moves beneath it -- the same interaction Zomato and
                // Blinkit use, and far easier one-handed than dragging a
                // marker onto a target.
                IgnorePointer(
                  child: Padding(
                    // Lift it so the point sits at the centre, not the
                    // icon's middle.
                    padding: EdgeInsets.only(bottom: 36),
                    child: Icon(Icons.location_on, size: 44, color: context.colors.primary),
                  ),
                ),
                Positioned(
                  right: AppSpacing.containerPaddingMobile,
                  bottom: AppSpacing.containerPaddingMobile,
                  child: FloatingActionButton.extended(
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(_locating ? 'Finding you...' : 'Use current'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLowest,
              border: Border(top: BorderSide(color: context.colors.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place, color: context.colors.primary),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Delivering to this pin', style: AppTextStyles.labelLg),
                            const SizedBox(height: 2),
                            Text(
                              _resolvingAddress
                                  ? 'Finding this place...'
                                  : (_areaLabel ??
                                      '${_pin.latitude.toStringAsFixed(5)}, '
                                          '${_pin.longitude.toStringAsFixed(5)}'),
                              style: AppTextStyles.bodySm
                                  .copyWith(color: context.colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    'Move the map to place the pin at your door.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelMd
                        .copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  ElevatedButton(
                    onPressed: _confirm,
                    child: const Text('Confirm Location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: the details a map cannot supply.
class _AddressDetailsSheet extends StatefulWidget {
  const _AddressDetailsSheet({
    required this.existing,
    required this.latitude,
    required this.longitude,
    required this.areaLabel,
    required this.city,
    required this.pincode,
  });

  final Address? existing;
  final double latitude;
  final double longitude;
  final String? areaLabel;
  final String? city;
  final String? pincode;

  @override
  State<_AddressDetailsSheet> createState() => _AddressDetailsSheetState();
}

class _AddressDetailsSheetState extends State<_AddressDetailsSheet> {
  static const _tags = ['Home', 'Work', 'Other'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _houseController;
  late final TextEditingController _landmarkController;
  late final TextEditingController _cityController;
  late final TextEditingController _pincodeController;

  late String _tag;
  late bool _isDefault;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _houseController = TextEditingController(text: existing?.line1 ?? '');
    _landmarkController = TextEditingController(text: existing?.line2 ?? '');
    _cityController =
        TextEditingController(text: existing?.city ?? widget.city ?? '');
    _pincodeController =
        TextEditingController(text: existing?.pincode ?? widget.pincode ?? '');
    _tag = _tags.contains(existing?.label) ? existing!.label! : _tags.first;
    _isDefault = existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    _houseController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<AddressRepository>();
    final navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await repository.upsertAddress(
        id: widget.existing?.id,
        label: _tag,
        line1: _houseController.text.trim(),
        line2: _landmarkController.text.trim().isEmpty
            ? widget.areaLabel
            : '${_landmarkController.text.trim()}'
                '${widget.areaLabel == null ? '' : ', ${widget.areaLabel}'}',
        city: _cityController.text.trim(),
        pincode: _pincodeController.text.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        isDefault: _isDefault,
      );
      navigator.pop(saved);
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not save this address. Please try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.containerPaddingMobile,
        right: AppSpacing.containerPaddingMobile,
        top: AppSpacing.containerPaddingMobile,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            AppSpacing.containerPaddingMobile,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Address Details', style: AppTextStyles.headlineSm),
              if (widget.areaLabel != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: context.colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.areaLabel!,
                        style: AppTextStyles.bodySm
                            .copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.gutter),
              TextFormField(
                controller: _houseController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'House / Flat / Building',
                  hintText: 'e.g. 302, Shanti Apartments',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _landmarkController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Landmark (optional)',
                  hintText: 'e.g. opposite the school',
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: TextFormField(
                      controller: _pincodeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Pincode'),
                      validator: (value) =>
                          (value == null || value.trim().length < 6) ? '6 digits' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.gutter),
              Text('Save as', style: AppTextStyles.labelLg),
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  for (final tag in _tags)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.base),
                      child: ChoiceChip(
                        avatar: Icon(
                          switch (tag) {
                            'Home' => Icons.home_outlined,
                            'Work' => Icons.work_outline,
                            _ => Icons.place_outlined,
                          },
                          size: 18,
                        ),
                        label: Text(tag),
                        selected: _tag == tag,
                        onSelected: (_) => setState(() => _tag = tag),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Make this my default address'),
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
              ),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                ),
                const SizedBox(height: AppSpacing.base),
              ],
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
