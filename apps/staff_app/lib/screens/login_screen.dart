import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await context.read<AuthRepository>().signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on SignInException catch (e) {
      setState(() => _errorMessage = switch (e.reason) {
            SignInFailure.emailNotConfirmed =>
              'Confirm your email first — open the link we sent you, then log in.',
            SignInFailure.network =>
              'Cannot reach the server. Check your internet connection and try again.',
            _ => 'Could not sign in. Check your email and password.',
          });
    } catch (e) {
      setState(() => _errorMessage = 'Could not sign in. Check your email and password.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
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
                    Text('K.G.S Staff', style: AppTextStyles.headlineLg, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'Sign in with the account created for you.',
                      style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.gutter),
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
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Enter your password' : null,
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
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    TextButton(
                      onPressed: () => context.push('/signup'),
                      child: const Text('Have an invite code? Sign up'),
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
