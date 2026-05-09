import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'widgets/staff_pin_sheet.dart';

/// Staff path for redeeming a stage-perk code at the counter. Customer
/// shows their phone with the 8-char code (or reads it out). Staff types
/// it here, PIN-confirms, RPC validates + marks redeemed.
class RedeemPerkScreen extends ConsumerStatefulWidget {
  const RedeemPerkScreen({super.key});

  @override
  ConsumerState<RedeemPerkScreen> createState() =>
      _RedeemPerkScreenState();
}

class _RedeemPerkScreenState extends ConsumerState<RedeemPerkScreen> {
  final _codeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _success;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 8) {
      setState(() => _error = 'Codes are exactly 8 characters.');
      return;
    }

    final verified = await StaffPinSheet.show(
      context,
      actionLabel: 'Redeem perk · $code',
    );
    if (verified == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('stage_perk_redeem', params: {
        'p_code': code,
        'p_staff_pin_id': verified.staffId,
        'p_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = Map<String, dynamic>.from(res);
        _codeCtrl.clear();
        _noteCtrl.clear();
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.message) {
          final m when m.contains('perk_code_not_found') =>
            "We couldn't find that code. Double-check the spelling.",
          final m when m.contains('perk_already_redeemed') =>
            'That perk has already been redeemed.',
          final m when m.contains('perk_expired') =>
            'That perk code has expired.',
          final m when m.contains('staff_not_authorised') =>
            'PIN not authorised on this device.',
          _ => 'Redeem failed: ${e.message}',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Redeem failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem stage perk')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_success != null) _SuccessCard(data: _success!),
              if (_success != null) const SizedBox(height: 24),
              Text('Code from customer\'s phone',
                  style: AppTextStyles.bodyLarge(context)),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(8),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'XXXXXXXX',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional, audit-only)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.adminRed.withValues(alpha: 0.10),
                    border: Border.all(
                      color: AppColors.adminRed.withValues(alpha: 0.40),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsRegular.warningCircle,
                        color: AppColors.adminRed,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: AppTextStyles.body(context)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _redeem,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Confirm with PIN · Redeem'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SuccessCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final perkLabel = (data['perk_label'] as String?) ?? 'Perk';
    final childName = (data['child_name'] as String?) ?? 'kid';
    final stage = (data['stage'] as String?) ?? '';
    final desc = data['perk_description'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.activeGreen.withValues(alpha: 0.10),
        border: Border.all(
          color: AppColors.activeGreen.withValues(alpha: 0.50),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsFill.checkCircle,
            color: AppColors.activeGreen,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Redeemed!',
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.activeGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$perkLabel · for $childName · ${stage.toUpperCase()}',
                  style: AppTextStyles.body(context),
                ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
