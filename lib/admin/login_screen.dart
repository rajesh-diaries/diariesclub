import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_button.dart';
import 'providers/admin_auth_provider.dart';

/// Admin web sign-in. Email + password against Supabase Auth, then verifies
/// the resulting auth user has an active `admin_users` row before letting
/// the router land on the dashboard. If signed-in-but-not-an-admin, signs
/// out cleanly and surfaces "not authorised".
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Email and password are required.');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        throw const AuthException('No session returned.');
      }

      // Verify admin_users row exists + is_active.
      final adminRow = await Supabase.instance.client
          .from('admin_users')
          .select()
          .eq('auth_user_id', res.user!.id)
          .eq('is_active', true)
          .maybeSingle();

      if (adminRow == null) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errorText =
              'This account is not authorised for admin access.';
        });
        return;
      }

      await Supabase.instance.client
          .from('admin_users')
          .update({'last_login_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', adminRow['id'] as String);

      ref.invalidate(currentAdminUserProvider);
      // Router redirect handles navigation.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('Invalid login credentials')
            ? 'Invalid email or password.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't sign in. Check the network.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_moon, size: 56, color: AppColors.navy),
                const SizedBox(height: 16),
                Text(
                  'Diaries Club Admin',
                  style: AppTextStyles.h1(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in with your founder credentials.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Sign in',
                  loading: _busy,
                  onPressed: _busy ? null : _signIn,
                ),
                const SizedBox(height: 16),
                Text(
                  '2FA arrives in v1.1.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
