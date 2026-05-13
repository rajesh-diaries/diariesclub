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
          final active = sessions.where((s) => s['status'] == 'active').toList();
          final grace = sessions.where((s) => s['status'] == 'grace').toList();
          if (active.isEmpty && grace.isEmpty) {
            return const _EmptyState();
          }
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

/// Empty state — uses CONVENTION-001 hero glyph row (Rafi/Ellie/Gerry/Zena
/// coloured circles) until real artwork lands per the v1.1 deferred item.
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 240, child: _HeroIdleRow()),
              const SizedBox(height: 24),
              Text(
                'The floor is quiet right now.',
                style: AppTextStyles.bodyLarge(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sessions will appear here as soon as a family scans in.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIdleRow extends StatelessWidget {
  const _HeroIdleRow();

  static const _cells = <(IconData, Color)>[
    (PhosphorIconsFill.shieldStar, AppColors.rafiCoral),
    (PhosphorIconsFill.heart, AppColors.ellieBlue),
    (PhosphorIconsFill.magnifyingGlass, AppColors.gerryAmber),
    (PhosphorIconsFill.palette, AppColors.zenaGreen),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, color) in _cells)
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
      ],
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

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.lightTextSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = session['status'] as String?;
    final startedAt =
        DateTime.tryParse(session['started_at'] as String? ?? '')?.toLocal();
    final expiresAt =
        DateTime.tryParse(session['expires_at'] as String? ?? '')?.toLocal();
    final isGrace = status == 'grace';
    final remaining = expiresAt?.difference(DateTime.now());

    final kidName =
        ((session['children'] as Map?)?['name'] as String?) ?? '—';
    final guardianName =
        ((session['families'] as Map?)?['name'] as String?) ?? '—';
    final sessionShort =
        (session['id'] as String).substring(0, 6).toUpperCase();
    final durationMin = session['duration_minutes'] as int?;
    final paymentMethod = session['payment_method'] as String?;

    // Was the session extended? Compare actual window to booked duration.
    int extendedMin = 0;
    if (startedAt != null && expiresAt != null && durationMin != null) {
      final actualMin = expiresAt.difference(startedAt).inMinutes;
      if (actualMin > durationMin) {
        extendedMin = actualMin - durationMin;
      }
    }

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kidName,
                      style: AppTextStyles.bodyLarge(context).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Guardian: $guardianName',
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _remainingLabel(remaining, isGrace: isGrace),
                style: AppTextStyles.bodyLarge(
                  context,
                  color:
                      isGrace ? AppColors.adminRed : AppColors.lightTextPrimary,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _MetaLine(
                icon: PhosphorIconsRegular.timer,
                text: '${durationMin ?? '—'}-min · ${paymentMethod ?? '—'}',
              ),
              if (startedAt != null)
                _MetaLine(
                  icon: PhosphorIconsRegular.play,
                  text: 'Started ${_hhmm(startedAt)}',
                ),
              if (expiresAt != null)
                _MetaLine(
                  icon: PhosphorIconsRegular.flagCheckered,
                  text: 'Ends ${_hhmm(expiresAt)}',
                ),
              if (extendedMin > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Extended +${extendedMin}m',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              Text(
                'ID $sessionShort',
                style: AppTextStyles.caption(
                  context, color: AppColors.lightTextSecondary,
                ),
              ),
            ],
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
              // FEATURE-002: mark complimentary Healthy Bite claimed.
              // Idempotent; button stays clickable and the RPC returns
              // already_claimed=true on retries.
              if (session['healthy_bite_claimed_at'] == null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: const BorderSide(color: AppColors.gold),
                  ),
                  icon: const Icon(PhosphorIconsRegular.gift),
                  label: const Text('Healthy Bite claimed'),
                  onPressed: () => _claimHealthyBite(context),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsFill.checkCircle,
                          color: AppColors.gold, size: 16),
                      SizedBox(width: 6),
                      Text('Healthy Bite given',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
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

  static String _hhmm(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    return '$hour:${dt.minute.toString().padLeft(2, '0')}'
        ' ${dt.hour >= 12 ? 'PM' : 'AM'}';
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

  Future<void> _claimHealthyBite(BuildContext context) async {
    try {
      final raw = await Supabase.instance.client.rpc<dynamic>(
        'claim_healthy_bite',
        params: {'p_session_id': session['id']},
      );
      final result =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final already = result['already_claimed'] == true;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(already
              ? 'Already marked as claimed.'
              : 'Healthy Bite claim recorded.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't mark claimed: ${e.message}")),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't mark claimed.")),
      );
    }
  }

  Future<void> _extend(BuildContext context, WidgetRef ref, int mins) async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Extend session by ${mins}m',
    );
    if (staff == null) return;
    try {
      // RPC signature: p_duration_minutes (not p_extra_minutes).
      await Supabase.instance.client.rpc<dynamic>('session_extend', params: {
        'p_session_id': session['id'],
        'p_duration_minutes': mins,
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
