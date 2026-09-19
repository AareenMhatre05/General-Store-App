import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

/// Reached when an account signs in here that this app does not serve.
///
/// It used to sign the person out from `initState`, before a frame had
/// been painted. The router then bounced straight to /login, so the
/// explanation was never on screen for long enough to read: entering
/// correct credentials just returned you to the login page, over and
/// over, with no clue why. It now says which role the account has and
/// waits for the person to act.
class WrongRoleScreen extends StatelessWidget {
  const WrongRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppAuthState>().profile?.role;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_person_outlined,
                    size: 48, color: context.colors.onSurfaceVariant),
                const SizedBox(height: AppSpacing.gutter),
                Text(
                  'This app is for staff and owners',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineSm,
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  // Naming the role is the whole point: "wrong account"
                  // is not something you can act on.
                  role == null
                      ? 'Your password was correct, but this account is not '
                          'set up for the staff app.'
                      : 'Your password was correct, but this is a '
                          '${role.label.toLowerCase()} account, which the '
                          'staff app does not open yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.gutter),
                ElevatedButton(
                  onPressed: () => context.read<AppAuthState>().signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
