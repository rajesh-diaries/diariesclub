import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_button.dart';
import 'providers/staff_auth_provider.dart';

/// One-time per-phone sign-in. Email/password against the long-lived
/// staff auth user. Session persists across app kills via Supabase's
/// default refresh-token flow.
///
/// On success we invalidate currentTabletDeviceProvider so the venue id
/// resolves immediately; the router redirects to /staff/home.
class TabletLoginScreen extends ConsumerStatefulWidget {
  const TabletLoginScreen({super.key});

  @override
  ConsumerState<TabletLoginScreen> createState() => _TabletLoginScreenState();
}

class _TabletLoginScreenState extends ConsumerState<TabletLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Email and password are required.');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      // Confirm the device row is active before letting the router land.
      ref.invalidate(currentTabletDeviceProvider);
      final device =
          await ref.read(currentTabletDeviceProvider.future);
      if (!mounted) return;
      if (device == null) {
        await Supabase.instance.client.auth.signOut();
        setState(() {
          _busy = false;
          _errorText =
              'This phone is not registered (or has been revoked). Contact admin.';
        });
        return;
      }
      // Router redirect handles the navigation.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message;
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.phone_iphone, size: 56, color: AppColors.navy),
                const SizedBox(height: 16),
                Text(
                  'Diaries Staff',
                  style: AppTextStyles.h1(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "One-time sign-in per phone. You'll still tap your PIN for each action.",
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'staff@diariesclub.local',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
