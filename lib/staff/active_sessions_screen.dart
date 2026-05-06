import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Realtime list of all sessions at this venue in active or grace state.
/// Each card shows time-remaining (or +overage for grace), with two PIN-
/// gated actions: extend (session_extend) and force_close
/// (session_force_close).
class ActiveSessionsScreen extends ConsumerWidget {
  const ActiveSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(venueActiveSessionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active sessions')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't load: $e")),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const _EmptyState();
          }
          final active = sessions.where((s) => s['status'] == 'active').toList();
          final grace = sessions.where((s) => s['status'] == 'grace').toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader(label: 'ACTIVE (${active.length})'),
                for (final s in active) _SessionTile(session: s),
              ],
              if (grace.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader(label: 'GRACE — over time (${grace.length})'),
                for (final s in grace) _SessionTile(session: s),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              PhosphorIconsRegular.clock,
              size: 56,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text('No active sessions',
                style: AppTextStyles.bodyLarge(context)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
        ),
      );
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = session['status'] as String?;
    final expiresAt =
        DateTime.tryParse(session['expires_at'] as String? ?? '')?.toLocal();
    final isGrace = status == 'grace';
    final remaining = expiresAt?.difference(DateTime.now());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGrace
            ? AppColors.warningYellow.withValues(alpha: 0.10)
            : AppColors.lightSurface,
        border: Border.all(
          color: isGrace ? AppColors.warningYellow : AppColors.lightBorder,
          width: isGrace ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session ${(session['id'] as String).substring(0, 6).toUpperCase()}',
                  style: AppTextStyles.bodyLarge(context),
                ),
              ),
              Text(
                _remainingLabel(remaining, isGrace: isGrace),
                style: AppTextStyles.bodyLarge(
                  context,
                  color:
                      isGrace ? AppColors.adminRed : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${session['duration_minutes']}-min · ${session['payment_method']}',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(PhosphorIconsRegular.plusCircle),
                label: const Text('Extend 1hr'),
                onPressed: () => _extend(context, ref, 60),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.adminRed,
                ),
                icon: const Icon(PhosphorIconsRegular.xCircle),
                label: const Text('Force close'),
                onPressed: () => _forceClose(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _remainingLabel(Duration? r, {required bool isGrace}) {
    if (r == null) return '—';
    if (isGrace) {
      final over = -r.inMinutes;
      return '+${over}m over';
    }
    final m = r.inMinutes;
    if (m <= 0) return 'ending';
    return '${m}m left';
  }

  Future<void> _extend(BuildContext context, WidgetRef ref, int mins) async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Extend session by ${mins}m',
    );
    if (staff == null) return;
    try {
      await Supabase.instance.client.rpc<dynamic>('session_extend', params: {
        'p_session_id': session['id'],
        'p_extra_minutes': mins,
        'p_payment_method': 'cash',
        'p_initiated_by': 'staff_on_behalf',
        'p_staff_pin_id': staff.staffId,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extended ${mins}m.')),
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't extend: ${e.message}")),
      );
    }
  }

  Future<void> _forceClose(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Force close session?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This ends the session immediately. Reason is required.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Force close'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (reasonCtrl.text.trim().isEmpty) return;
    if (!context.mounted) return;

    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Force close session',
    );
    if (staff == null) return;
    try {
      await Supabase.instance.client
          .rpc<dynamic>('session_force_close', params: {
        'p_session_id': session['id'],
        'p_staff_pin_id': staff.staffId,
        'p_reason': reasonCtrl.text.trim(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed.')),
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't close: ${e.message}")),
      );
    }
  }
}
