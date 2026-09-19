import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    // Captured before the awaits so nothing touches `context` afterwards.
    final authRepository = context.read<AuthRepository>();
    final router = GoRouter.of(context);
    final email = _emailController.text.trim();

    try {
      final outcome = await authRepository.signUpStaff(
        email: email,
        password: _passwordController.text,
        inviteCode: _inviteCodeController.text.trim(),
        fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      );

      // Someone who already had an account is signed in and promoted on
      // the spot -- nothing to confirm, so send them straight in. A brand
      // new account still has to confirm its email first.
      if (outcome == StaffJoinOutcome.existingAccountPromoted) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('You\'re on the team', style: AppTextStyles.headlineSm),
            content: Text(
              'Your existing account has been upgraded. Log in with the same '
              'email and password you already use.',
              style: AppTextStyles.bodyMd,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
        await authRepository.signOut();
        router.go('/login');
        return;
      }

      if (!mounted) return;
      await showSignupCompleteDialog(
        context,
        email: email,
        needsEmailConfirmation: true,
      );
      router.go('/login');
    } on InviteException catch (e) {
      setState(() => _errorMessage = switch (e.reason) {
            InviteFailure.notFound =>
              'That code doesn\'t match an invite for $email. Check both the '
                  'code and that you typed the same email the owner invited.',
            InviteFailure.alreadyUsed =>
              'That invite code has already been used. Ask the owner for a new one.',
            InviteFailure.expired =>
              'That invite code has expired. Ask the owner to send a fresh one.',
          });
    } on SignInException catch (e) {
      setState(() => _errorMessage = e.reason == SignInFailure.invalidCredentials
          ? 'This email already has an account. Enter that account\'s existing '
              'password to join the team with it.'
          : 'Could not reach the server. Check your connection and try again.');
    } catch (e) {
      setState(() => _errorMessage = 'Could not create your account: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Staff Sign Up')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Join the team', style: AppTextStyles.headlineMd),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'You need an invite code from the store owner to create an account here.',
                      style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.gutter),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Full name (optional)'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (value) => (value == null || value.length < 6)
                          ? 'Password must be at least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextFormField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Invite code'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Enter your invite code' : null,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        _errorMessage!,
                        style: AppTextStyles.bodySm.copyWith(color: context.colors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.gutter),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign Up'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/login'),
                      child: const Text('Already have an account? Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
