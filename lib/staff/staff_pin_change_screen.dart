import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_button.dart';

/// Forced PIN rotation. Reached when verify_staff_pin returns
/// force_pin_change=true (e.g., the bootstrap super_admin signing in with
/// PIN 0000). Calls staff_pin_change RPC, which bcrypts the new PIN
/// server-side and clears the force_pin_change flag.
///
/// Inputs (route extra): { staffId, currentPin } — staffId comes from
/// the verified-PIN result; currentPin is what the user just typed in
/// the PIN sheet. We re-verify it server-side as defence in depth.
class StaffPinChangeScreen extends ConsumerStatefulWidget {
  final String staffId;
  final String currentPin;
  const StaffPinChangeScreen({
    super.key,
    required this.staffId,
    required this.currentPin,
  });

  @override
  ConsumerState<StaffPinChangeScreen> createState() =>
      _StaffPinChangeScreenState();
}

class _StaffPinChangeScreenState extends ConsumerState<StaffPinChangeScreen> {
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPin = _newPin.text;
    final confirm = _confirmPin.text;

    if (newPin.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(newPin)) {
      setState(() => _errorText = 'PIN must be 4 digits.');
      return;
    }
    if (newPin == '0000') {
      setState(() => _errorText = 'PIN cannot be 0000.');
      return;
    }
    if (newPin != confirm) {
      setState(() => _errorText = "PINs don't match.");
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client.rpc<dynamic>('staff_pin_change', params: {
        'p_staff_id': widget.staffId,
        'p_current_pin': widget.currentPin,
        'p_new_pin': newPin,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated.')),
      );
      context.go('/staff/home');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('pin_too_weak')
            ? 'PIN cannot be 0000.'
            : e.message.contains('current_pin_incorrect')
                ? 'Current PIN check failed. Sign in again.'
                : "Couldn't update PIN.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't update PIN. Check the network.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new PIN'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pick a new 4-digit PIN',
                  style: AppTextStyles.h2(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Avoid 0000, 1234, or anything obvious. You will use this for every PIN-gated action.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _newPin,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPin,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
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
                  label: 'Save PIN',
                  loading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
