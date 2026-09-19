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
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
    // Captured before the awaits so nothing touches `context` afterwards.
    final authRepository = context.read<AuthRepository>();
    final router = GoRouter.of(context);
    final email = _emailController.text.trim();

    try {
      final response = await authRepository.signUpCustomer(
            email: email,
            password: _passwordController.text,
            fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );


      // With email confirmation switched off, Supabase signs the new user
      // straight in and returns a session -- which would make the router
      // skip past /login into the app. Sign back out so account creation
      // always ends at the login screen.
      final needsEmailConfirmation = response.session == null;
      if (!needsEmailConfirmation) {
        await authRepository.signOut();
      }

      if (!mounted) return;
      await showSignupCompleteDialog(
        context,
        email: email,
        needsEmailConfirmation: needsEmailConfirmation,
      );
      router.go('/login');
    } on PhoneTakenException catch (_) {
      setState(() => _errorMessage =
          'That mobile number is already registered. Each number can have '
          'one account — log in instead, or use "Forgot password" if you '
          'can\'t get in.');
    } on FormatException catch (_) {
      setState(() => _errorMessage = 'That mobile number doesn\'t look right.');
    } catch (e) {
      setState(() => _errorMessage = 'Could not create your account. Try a different email.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.containerPaddingMobile),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.gutter),
                Text('Join K.G.S', style: AppTextStyles.headlineMd),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'Create an account to start ordering.',
                  style: AppTextStyles.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.gutter),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full name (optional)'),
                ),
                const SizedBox(height: AppSpacing.base),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    prefixText: '+91 ',
                  ),
                  validator: (value) =>
                      AuthRepository.isValidMobile(value ?? '')
                          ? null
                          : 'Enter a 10-digit mobile number',
                  // Deliberately no "(optional)": one account per number
                  // is the rule, and the database will not accept a
                  // customer without one.
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
                  onPressed: () => context.pushReplacement('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
