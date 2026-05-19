import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';

/// "Type DELETE" gate → calls `family_anonymise(p_family_id, 'DELETE')`,
/// signs the user out, wipes local state, and routes to /farewell.
///
/// Strong friction is intentional per the locked decision (immediate
/// anonymisation, no recovery window).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState
    extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      _confirmController.text == 'DELETE' && !_busy;

  /// Final native-style confirmation before the nuke fires. Apple's
  /// guideline for destructive actions: the primary button must be
  /// destructive-red and the dialog must surface the most expensive
  /// thing the user is about to lose (wallet balance), not just "are
  /// you sure". One typo away from forfeiting real money — we owe the
  /// parent one last unmissable check.
  Future<bool> _confirmDestructive() async {
    final balancePaise = ref.read(walletBalancePaiseProvider) ?? 0;
    final balanceLine = balancePaise > 0
        ? 'Your wallet balance of ${Money.fromPaise(balancePaise)} '
            'will be forfeited and cannot be refunded.\n\n'
        : '';
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete everything?'),
            content: Text(
              '${balanceLine}Every kid, every session, every order, every '
              'card — gone. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.adminRed,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete everything'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _delete() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;

    // Final destructive-action confirm. Parent must explicitly tap
    // "Delete everything" after typing DELETE — guards against a
    // muscle-memory finger slip on the red CTA.
    final ok = await _confirmDestructive();
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('family_anonymise', params: {
        'p_family_id': familyId,
        'p_confirmation_token': 'DELETE',
      });

      // Wipe local state + sign out. Order matters: clear prefs first so a
      // race with auth-state listeners doesn't try to read stale family_id.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await const FlutterSecureStorage().deleteAll();
      } catch (_) {
        // TODO(session-12): replace with Sentry.captureException
        debugPrint('local wipe failed during account deletion');
      }
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;
      context.go('/farewell');
    } catch (e) {
      // TODO(session-12): replace with Sentry.captureException
      debugPrint('family_anonymise failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText =
            "Couldn't delete your account. Please contact support.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.adminRed.withValues(alpha: 0.10),
                  border: Border.all(color: AppColors.adminRed),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      PhosphorIconsFill.warning,
                      color: AppColors.adminRed,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This action is permanent.',
                        style: AppTextStyles.bodyLarge(
                          context,
                          color: AppColors.adminRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('What will happen', style: AppTextStyles.h3(context)),
              const SizedBox(height: 8),
              const _Bullet(
                text: 'Your name, phone, and profile will be removed.',
              ),
              const _Bullet(
                text: "Every child's name, photo and progress will be deleted.",
              ),
              const _Bullet(
                text: 'Your wallet balance will be forfeited.',
              ),
              const _Bullet(
                text: 'All session history, orders and coupons will be erased.',
              ),
              const _Bullet(
                text: 'Character cards and adventure progress will be removed.',
              ),
              const _Bullet(
                text: 'Push notifications to all your devices will stop.',
              ),
              const SizedBox(height: 16),
              Text(
                "Once deleted, your account cannot be recovered. You'd "
                'need to sign up fresh with this phone number.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              if (balance > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningYellow.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.warningYellow.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsRegular.warning,
                        color: AppColors.navy,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You have ${Money.fromPaise(balance)} in your '
                          'wallet that will be lost.',
                          style: AppTextStyles.body(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Use it before deleting →'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Type DELETE to confirm:',
                style: AppTextStyles.body(context),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hintText: 'DELETE',
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
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.adminRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _canDelete ? _delete : null,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Permanently delete my account'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => context.pop(),
                child: const Text('Never mind, take me back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final bool muted;
  const _Bullet({required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: muted
                    ? AppColors.lightTextSecondary
                    : AppColors.adminRed,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                context,
                color: muted
                    ? AppColors.lightTextSecondary
                    : AppColors.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

