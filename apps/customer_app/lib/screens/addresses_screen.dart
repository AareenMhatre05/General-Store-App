import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Saved delivery addresses. Adding or editing one goes through the map
/// picker at /address/pick, which captures the coordinates the delivery
/// fee is calculated from -- they are not derived from the typed text.
class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late Future<List<Address>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<AddressRepository>().getMyAddresses();
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = context.read<AddressRepository>().getMyAddresses());
    await _loadFuture;
  }

  Future<void> _edit({Address? existing}) async {
    final saved = await context.push<Address>('/address/pick', extra: existing);
    if (saved != null) await _reload();
  }

  Future<void> _delete(Address address) async {
    final repository = context.read<AddressRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Delete this address?', style: AppTextStyles.headlineSm),
        content: Text(
          'Past orders keep the address they were delivered to.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.deleteAddress(address.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Saved Addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add Address'),
      ),
      body: FutureBuilder<List<Address>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load your addresses.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final addresses = snapshot.data ?? [];
          if (addresses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off_outlined,
                        size: 48, color: context.colors.outline),
                    const SizedBox(height: AppSpacing.base),
                    Text('No saved addresses', style: AppTextStyles.headlineSm),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'Add one so checkout is a single tap next time.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                96,
              ),
              itemCount: addresses.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
              itemBuilder: (context, index) {
                final address = addresses[index];
                return AddressCard(
                  address: address,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: context.colors.primary, size: 20),
                        onPressed: () => _edit(existing: address),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: context.colors.error, size: 20),
                        onPressed: () => _delete(address),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// One address, rendered the same way on the address book and at
/// checkout so the two never drift apart.
class AddressCard extends StatelessWidget {
  const AddressCard({
    super.key,
    required this.address,
    this.trailing,
    this.selected = false,
    this.onTap,
  });

  final Address address;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? context.colors.primary : context.colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.location_on_outlined,
              color: selected ? context.colors.primary : context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(address.label ?? 'Address', style: AppTextStyles.labelLg),
                      if (address.isDefault) ...[
                        const SizedBox(width: AppSpacing.base),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            'Default',
                            style: AppTextStyles.labelMd
                                .copyWith(color: context.colors.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      address.line1,
                      if (address.line2?.isNotEmpty ?? false) address.line2!,
                      address.city,
                      address.pincode,
                    ].join(', '),
                    style: AppTextStyles.bodySm
                        .copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
