import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/referral_eligibility_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Home-tab card that lets a new family enter a friend's referral code
/// before their first session. Hidden once a referrer is attached or
/// the family has any completed session.
class ReferralEntryCard extends ConsumerWidget {
  const ReferralEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligible =
        ref.watch(referralRedeemEligibleProvider).valueOrNull ?? false;
    if (!eligible) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEntryDialog(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsFill.gift,
                color: AppColors.gold,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Have a referral code?',
                      style: AppTextStyles.h3(context, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Get ₹100 off after your first session.',
                      style: AppTextStyles.body(
                        context,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEntryDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _ReferralEntryDialog(parentRef: ref),
    );
  }
}

class _ReferralEntryDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _ReferralEntryDialog({required this.parentRef});

  @override
  ConsumerState<_ReferralEntryDialog> createState() =>
      _ReferralEntryDialogState();
}

class _ReferralEntryDialogState extends ConsumerState<_ReferralEntryDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your friend\'s code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .rpc<dynamic>('referral_attach', params: {'p_code': code});
      widget.parentRef.invalidate(currentFamilyProvider);
      widget.parentRef.invalidate(referralRedeemEligibleProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Code applied. Both wallets get credited after your first session.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[REFERRAL_ATTACH] error: $e (type: ${e.runtimeType})');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e.toString());
      });
    }
  }

  String _friendly(String raw) {
    if (raw.contains('invalid_code')) {
      return 'That code doesn\'t match a Diaries family.';
    }
    if (raw.contains('self_referral')) {
      return 'You can\'t use your own referral code.';
    }
    if (raw.contains('already_attached')) {
      return 'You\'ve already added a referral code.';
    }
    if (raw.contains('already_converted')) {
      return 'Referral codes can only be added before your first session.';
    }
    return 'Couldn\'t apply right now. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter referral code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste the 8-character code your friend shared.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. 0F50ABF8',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            maxLength: 8,
            onSubmitted: (_) => _busy ? null : _apply(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _apply,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Apply'),
        ),
      ],
    );
  }
}
