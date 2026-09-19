import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Where the store is, and what delivery costs by distance.
///
/// No map widget on purpose: an embedded map needs a billed Google Maps
/// API key, and for a single fixed shop "stand at the counter and press
/// Use My Current Location" is both accurate and free. Manual lat/lng
/// entry covers setting it from elsewhere.
class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  late Future<void> _loadFuture;
  StoreSettings? _settings;
  List<DeliveryFeeTier> _tiers = [];

  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _addressController = TextEditingController();

  bool _isSaving = false;
  String? _message;
  bool _messageIsError = false;
  LocationFailure? _settingsFailure;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storeRepository = context.read<StoreRepository>();
    final settings = await storeRepository.getSettings();
    final tiers = await storeRepository.getFeeTiers();
    setState(() {
      _settings = settings;
      _tiers = tiers;
      _latController.text = settings.latitude?.toString() ?? '';
      _lngController.text = settings.longitude?.toString() ?? '';
      _addressController.text = settings.address ?? '';
    });
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      final position = await const LocationService().current();
      setState(() {
        _latController.text = position.latitude.toString();
        _lngController.text = position.longitude.toString();
        _message = 'Location captured. Press Save to store it.';
        _messageIsError = false;
        _settingsFailure = null;
      });
    } on LocationFailure catch (e) {
      setState(() {
        _message = e.message;
        _messageIsError = true;
        _settingsFailure = e.canOpenSettings ? e : null;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveLocation() async {
    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lngController.text.trim());
    if (latitude == null || longitude == null) {
      setState(() {
        _message = 'Enter a valid latitude and longitude.';
        _messageIsError = true;
      });
      return;
    }

    final storeRepository = context.read<StoreRepository>();
    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      await storeRepository.setLocation(latitude: latitude, longitude: longitude);
      await storeRepository.setStoreDetails(address: _addressController.text.trim());
      await _reload();
      setState(() {
        _message = 'Store location saved.';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Could not save. Check your connection and try again.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addTier() async {
    final minController = TextEditingController(
      text: _tiers.isEmpty
          ? '0'
          : (_tiers.last.maxDistanceMeters ?? _tiers.last.minDistanceMeters)
              .toStringAsFixed(0),
    );
    final maxController = TextEditingController();
    final feeController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final storeRepository = context.read<StoreRepository>();

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.containerPaddingMobile,
          right: AppSpacing.containerPaddingMobile,
          top: AppSpacing.containerPaddingMobile,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
              AppSpacing.containerPaddingMobile,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Distance Band', style: AppTextStyles.headlineSm),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Distances are straight-line metres from the store.',
                style: AppTextStyles.bodySm.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.gutter),
              TextFormField(
                controller: minController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'From (metres)'),
                validator: (value) =>
                    double.tryParse(value ?? '') == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'To (metres)',
                  helperText: 'Leave empty for "and beyond"',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final max = double.tryParse(value);
                  final min = double.tryParse(minController.text);
                  if (max == null) return 'Enter a number';
                  if (min != null && max <= min) return 'Must be more than "From"';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Delivery fee (₹)'),
                validator: (value) =>
                    double.tryParse(value ?? '') == null ? 'Enter an amount' : null,
              ),
              const SizedBox(height: AppSpacing.gutter),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    await storeRepository.createFeeTier(
                      minDistanceMeters: double.parse(minController.text),
                      maxDistanceMeters: maxController.text.trim().isEmpty
                          ? null
                          : double.parse(maxController.text),
                      feeAmount: double.parse(feeController.text),
                    );
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
                  },
                  child: const Text('Add Band'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (added == true) await _reload();
  }

  Future<void> _deleteTier(DeliveryFeeTier tier) async {
    final storeRepository = context.read<StoreRepository>();
    await storeRepository.deleteFeeTier(tier.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Store Settings')),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load store settings.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final hasLocation = _settings?.latitude != null;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            children: [
              if (!hasLocation)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.gutter),
                  padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
                  decoration: BoxDecoration(
                    color: context.colors.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: context.colors.onErrorContainer),
                      const SizedBox(width: AppSpacing.base),
                      Expanded(
                        child: Text(
                          'No store location set. Until you set one, every delivery '
                          'is charged ₹0 because the distance cannot be measured.',
                          style: AppTextStyles.bodySm
                              .copyWith(color: context.colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              _Card(
                title: 'Store Location',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _useCurrentLocation,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Use My Current Location'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _latController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(
                          child: TextField(
                            controller: _lngController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Shop address (shown to customers)',
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        _message!,
                        style: AppTextStyles.bodySm.copyWith(
                          color: _messageIsError ? context.colors.error : context.colors.success,
                        ),
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
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveLocation,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Location'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.gutter),
              _Card(
                title: 'Delivery Fees',
                trailing: IconButton(
                  icon: Icon(Icons.add, color: context.colors.primary),
                  onPressed: _addTier,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tiers.isEmpty)
                      Text(
                        'No distance bands yet, so delivery is free at every '
                        'distance. Add a band to start charging.',
                        style: AppTextStyles.bodySm
                            .copyWith(color: context.colors.onSurfaceVariant),
                      )
                    else
                      for (final tier in _tiers)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.straighten,
                                  size: 18, color: context.colors.onSurfaceVariant),
                              const SizedBox(width: AppSpacing.base),
                              Expanded(
                                child: Text(
                                  tier.maxDistanceMeters == null
                                      ? '${_km(tier.minDistanceMeters)} km and beyond'
                                      : '${_km(tier.minDistanceMeters)} – '
                                          '${_km(tier.maxDistanceMeters!)} km',
                                  style: AppTextStyles.bodyMd,
                                ),
                              ),
                              Text(formatInr(tier.feeAmount),
                                  style: AppTextStyles.priceDisplay),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: context.colors.error, size: 20),
                                onPressed: () => _deleteTier(tier),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'A distance no band covers is charged nothing — that is how '
                      'you say "we do not deliver that far".',
                      style: AppTextStyles.bodySm
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _km(double meters) => (meters / 1000).toStringAsFixed(1);
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
