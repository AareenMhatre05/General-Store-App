import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

/// Adding staff, delivery partners and co-owners.
///
/// The owner never sets anyone's password. They issue a code tied to one
/// email address; that person signs up with it and a database trigger
/// promotes their account. So nobody's password passes through a third
/// party, and an invite that is never used simply expires.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late Future<void> _loadFuture;
  List<StaffInvite> _invites = [];
  List<TeamMember> _team = [];

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final repository = context.read<StaffInviteRepository>();
    final invites = await repository.getInvites();
    final team = await repository.getTeam();
    setState(() {
      _invites = invites;
      _team = team;
    });
  }

  Future<void> _reload() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _createInvite() async {
    final created = await showModalBottomSheet<StaffInvite>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceContainer,
      builder: (_) => const _NewInviteSheet(),
    );
    if (created == null || !mounted) return;
    await _reload();
    if (mounted) await _showCode(created);
  }

  /// Shown immediately after creating, because the code is useless to
  /// the owner until it reaches the person it is for.
  Future<void> _showCode(StaffInvite invite) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Invite for ${invite.email}', style: AppTextStyles.headlineSm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send them this code. They sign up in the staff app with '
              'their own password, using exactly this email address.',
              style: AppTextStyles.bodySm
                  .copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.gutter),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: SelectableText(
                invite.inviteCode,
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineMd.copyWith(
                  color: context.colors.onPrimaryContainer,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Valid until '
              '${DateFormat('d MMM yyyy').format(invite.expiresAt.toLocal())}, '
              'and can be used once.',
              style: AppTextStyles.labelMd
                  .copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.inviteCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          TextButton.icon(
            onPressed: () => Share.share(
              'Your K.G.S ${invite.role.label} invite code is '
              '${invite.inviteCode}. Sign up in the staff app using '
              '${invite.email}. It expires on '
              '${DateFormat('d MMM yyyy').format(invite.expiresAt.toLocal())}.',
            ),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Send'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(StaffInvite invite) async {
    final repository = context.read<StaffInviteRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surfaceContainer,
        title: Text('Cancel this invite?', style: AppTextStyles.headlineSm),
        content: Text(
          '${invite.email} will no longer be able to use the code. You can '
          'always issue a new one.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Cancel invite',
                style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.revokeInvite(invite.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.read<AppAuthState>().profile?.role == UserRole.owner;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Staff & Invites')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: _createInvite,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invite Someone'),
            )
          : null,
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
                child: CircularProgressIndicator(color: context.colors.primary));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load the team.',
                style: AppTextStyles.bodyMd.copyWith(color: context.colors.error),
              ),
            );
          }

          final pending = _invites.where((i) => i.isUsable).toList();
          final past = _invites.where((i) => !i.isUsable).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                AppSpacing.containerPaddingMobile,
                96,
              ),
              children: [
                if (!isOwner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.gutter),
                    child: Text(
                      'Only the owner can invite people.',
                      style: AppTextStyles.bodySm
                          .copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),

                Text('Current team', style: AppTextStyles.headlineSm),
                const SizedBox(height: AppSpacing.base),
                if (_team.isEmpty)
                  Text('Nobody yet.',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: context.colors.onSurfaceVariant))
                else
                  for (final member in _team)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _Row(
                        icon: switch (member.role) {
                          UserRole.owner => Icons.workspace_premium,
                          UserRole.delivery => Icons.delivery_dining,
                          _ => Icons.badge_outlined,
                        },
                        title: member.displayName,
                        subtitle: '${member.role.label}'
                            '${member.phone == null ? '' : ' · ${member.phone}'}',
                      ),
                    ),

                if (pending.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.gutter),
                  Text('Waiting to be used', style: AppTextStyles.headlineSm),
                  const SizedBox(height: AppSpacing.base),
                  for (final invite in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _Row(
                        icon: Icons.mark_email_unread_outlined,
                        title: invite.email,
                        subtitle: '${invite.role.label} · code ${invite.inviteCode} · '
                            'expires ${DateFormat('d MMM').format(invite.expiresAt.toLocal())}',
                        trailing: isOwner
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Show code',
                                    icon: const Icon(Icons.qr_code, size: 20),
                                    onPressed: () => _showCode(invite),
                                  ),
                                  IconButton(
                                    tooltip: 'Cancel invite',
                                    icon: Icon(Icons.close,
                                        size: 20, color: context.colors.error),
                                    onPressed: () => _revoke(invite),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                ],

                if (past.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.gutter),
                  Text('Past invites', style: AppTextStyles.headlineSm),
                  const SizedBox(height: AppSpacing.base),
                  for (final invite in past)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _Row(
                        icon: invite.isUsed
                            ? Icons.check_circle_outline
                            : Icons.schedule,
                        title: invite.email,
                        subtitle: '${invite.role.label} · ${invite.statusLabel}',
                        muted: true,
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

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon,
              color: muted ? context.colors.outline : context.colors.primary),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.labelLg.copyWith(
                      color: muted
                          ? context.colors.onSurfaceVariant
                          : context.colors.onSurface,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTextStyles.bodySm
                        .copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _NewInviteSheet extends StatefulWidget {
  const _NewInviteSheet();

  @override
  State<_NewInviteSheet> createState() => _NewInviteSheetState();
}

class _NewInviteSheetState extends State<_NewInviteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  UserRole _role = UserRole.staff;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<StaffInviteRepository>();
    final navigator = Navigator.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final invite = await repository.createInvite(
        email: _emailController.text.trim(),
        role: _role,
      );
      navigator.pop(invite);
    } catch (e) {
      // The actual server message, not a shrug: "Please try again" sent
      // us hunting through the database for a failure the error itself
      // would have named.
      setState(() {
        _errorMessage = 'Could not create the invite.\n\n$e';
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
              Text('Invite Someone', style: AppTextStyles.headlineSm),
              const SizedBox(height: AppSpacing.base),
              Text(
                'They sign up themselves with this code, choosing their own '
                'password. You never see or set it.',
                style: AppTextStyles.bodySm
                    .copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.gutter),
              TextFormField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Their email address',
                  helperText: 'They must sign up with exactly this address',
                ),
                validator: (value) => (value == null || !value.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: AppSpacing.gutter),
              Text('What can they do?', style: AppTextStyles.labelLg),
              const SizedBox(height: AppSpacing.base),
              for (final option in const [
                (
                  role: UserRole.staff,
                  title: 'Staff',
                  detail: 'Orders, inventory, offers and sales. Cannot invite people.',
                ),
                (
                  role: UserRole.delivery,
                  title: 'Delivery partner',
                  detail: 'Only their assigned deliveries and the map.',
                ),
                (
                  role: UserRole.owner,
                  title: 'Owner',
                  detail: 'Everything, including inviting and removing people.',
                ),
              ])
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.base),
                  color: _role == option.role
                      ? context.colors.primaryContainer
                      : context.colors.surfaceContainerLowest,
                  child: ListTile(
                    onTap: () => setState(() => _role = option.role),
                    title: Text(
                      option.title,
                      style: AppTextStyles.labelLg.copyWith(
                        color: _role == option.role
                            ? context.colors.onPrimaryContainer
                            : context.colors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      option.detail,
                      style: AppTextStyles.bodySm.copyWith(
                        color: _role == option.role
                            ? context.colors.onPrimaryContainer
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
                    trailing: _role == option.role
                        ? Icon(Icons.check_circle,
                            color: context.colors.onPrimaryContainer)
                        : null,
                  ),
                ),
              if (_errorMessage != null) ...[
                Text(_errorMessage!,
                    style: AppTextStyles.bodySm
                        .copyWith(color: context.colors.error)),
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
                    : const Text('Create Invite Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
