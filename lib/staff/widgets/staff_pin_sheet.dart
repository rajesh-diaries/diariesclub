import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/staff_pin_provider.dart';

/// 4-digit PIN entry sheet. Calls verify_staff_pin RPC; on success returns
/// the verified staff identity through the modal result so the caller can
/// pass staff_id into the action's RPC.
///
/// If verify_staff_pin returns force_pin_change=true, this sheet aborts
/// the calling action: it dismisses with `null` and pushes the user to
/// the PIN-change screen. The bootstrap super_admin (PIN 0000) hits this
/// path on first sign-in.
class StaffPinSheet extends ConsumerStatefulWidget {
  final String actionLabel;
  const StaffPinSheet({super.key, required this.actionLabel});

  /// Convenience: opens the sheet, returns the verified staff (or null on
  /// cancel). Caller should also handle force_pin_change via the returned
  /// VerifiedStaff.forcePinChange flag.
  static Future<VerifiedStaff?> show(
    BuildContext context, {
    required String actionLabel,
  }) {
    return showModalBottomSheet<VerifiedStaff>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StaffPinSheet(actionLabel: actionLabel),
    );
  }

  @override
  ConsumerState<StaffPinSheet> createState() => _StaffPinSheetState();
}

class _StaffPinSheetState extends ConsumerState<StaffPinSheet> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _focusNodes = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final pin = _controllers.map((c) => c.text).join();
    if (pin.length != 4) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final raw = await Supabase.instance.client
          .rpc<dynamic>('verify_staff_pin', params: {'p_pin': pin});
      final result = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (result == null || result['staff_id'] == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errorText = 'Invalid PIN. Try again.';
          for (final c in _controllers) {
            c.clear();
          }
        });
        _focusNodes.first.requestFocus();
        return;
      }
      final staff = VerifiedStaff.fromRpc(result);
      ref.read(lastVerifiedStaffProvider.notifier).state = staff;
      if (!mounted) return;
      if (staff.forcePinChange) {
        // Abort the parent action and route to PIN rotation. We pass the
        // typed PIN forward so staff_pin_change can re-verify it
        // server-side without re-prompting.
        Navigator.of(context).pop(null);
        context.push(
          '/staff/pin-change',
          extra: {'staffId': staff.staffId, 'currentPin': pin},
        );
        return;
      }
      Navigator.of(context).pop(staff);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('tablet_not_authorised')
            ? 'This tablet is not registered.'
            : "Couldn't verify PIN.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't verify PIN. Check the network.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text('Enter your PIN', style: AppTextStyles.h2(context)),
            const SizedBox(height: 6),
            Text(
              widget.actionLabel,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 56,
                    height: 72,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      autofocus: i == 0,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      obscureText: true,
                      obscuringCharacter: '●',
                      enabled: !_busy,
                      style: AppTextStyles.h1(context),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 3) {
                          _focusNodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) {
                          _focusNodes[i - 1].requestFocus();
                        }
                        if (i == 3 && v.isNotEmpty) {
                          _verify();
                        }
                      },
                    ),
                  ),
                );
              }),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.adminRed,
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
