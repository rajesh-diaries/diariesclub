import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/primary_button.dart';

/// Confirmation screen shown after qr_scan_validate succeeds. Shows the
/// child + duration + start/end times. Auto-dismisses after 5 seconds back
/// to /staff/home so the front desk doesn't have to tap.
class ScanSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const ScanSuccessScreen({super.key, required this.result});

  @override
  State<ScanSuccessScreen> createState() => _ScanSuccessScreenState();
}

class _ScanSuccessScreenState extends State<ScanSuccessScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      context.go('/staff/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final childName = (r['child_name'] as String?) ?? '—';
    final mins = (r['duration_minutes'] as int?) ?? 0;
    final expires = r['expires_at'] as String?;
    final hbEarned = r['healthy_bite_earned'] == true;

    return Scaffold(
      backgroundColor: AppColors.activeGreen.withValues(alpha: 0.10),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.activeGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsFill.checkCircle,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Checked in',
                  style: AppTextStyles.h1(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  childName,
                  style: AppTextStyles.h2(context, color: AppColors.navy),
                ),
                const SizedBox(height: 8),
                Text(
                  '$mins-min session',
                  style: AppTextStyles.body(context),
                ),
                if (expires != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ends at ${_formatTime(expires)}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                if (hbEarned) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Healthy Bite earned ✓',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                PrimaryButton(
                  label: 'Done',
                  onPressed: () => context.go('/staff/home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
    } catch (_) {
      return iso;
    }
  }
}
