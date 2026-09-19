import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_text_theme.dart';

/// Shown after a successful signup in either app, before sending the
/// user to the login screen.
///
/// A dialog rather than a SnackBar on purpose: when Supabase's "Confirm
/// email" setting is on, the user *cannot* log in until they act on
/// this, so it must not be a message that quietly fades away.
Future<void> showSignupCompleteDialog(
  BuildContext context, {
  required String email,
  required bool needsEmailConfirmation,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.surfaceContainer,
      icon: Icon(
        needsEmailConfirmation
            ? Icons.mark_email_unread_outlined
            : Icons.check_circle_outline,
        color: context.colors.primary,
        size: 32,
      ),
      title: Text(
        needsEmailConfirmation ? 'Confirm your email' : 'Account created',
        style: AppTextStyles.headlineSm,
        textAlign: TextAlign.center,
      ),
      content: Text(
        needsEmailConfirmation
            ? "We've sent a confirmation link to $email.\n\n"
                'Open that link, then come back and log in.'
            : 'Your account is ready. Log in to get started.',
        style: AppTextStyles.bodyMd,
        textAlign: TextAlign.center,
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Go to Login'),
          ),
        ),
      ],
    ),
  );
}
