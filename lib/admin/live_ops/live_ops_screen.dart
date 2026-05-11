import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';

/// Live Ops dashboard. 4 stat cards + active sessions table + a
/// "things needing attention" panel (pending refunds count).
class LiveOpsScreen extends ConsumerWidget {
  const LiveOpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions =
        ref.watch(adminActiveSessionsProvider).valueOrNull ?? const [];
    final pendingRefunds =
        ref.watch(adminPendingRefundsProvider).valueOrNull ?? const [];
    final todaySessions =
        ref.watch(adminTodaySessionCountProvider).valueOrNull ?? 0;
    final todayCash = ref.watch(adminTodayCashProvider).valueOrNull ?? 0;
    final todayBites =
        ref.watch(adminTodayHealthyBitesProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Live Ops'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(
              activeSessions: activeSessions.length,
              todaySessions: todaySessions,
              pendingRefunds: pendingRefunds.length,
              todayCashPaise: todayCash,
              todayBites: todayBites,
            ),
            const SizedBox(height: 24),
            _ActiveSessionsCard(sessions: activeSessions),
            const SizedBox(height: 24),
            if (pendingRefunds.isNotEmpty)
              _NeedsAttentionCard(pendingRefunds: pendingRefunds.length),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final int activeSessions;
  final int todaySessions;
  final int pendingRefunds;
  final int todayCashPaise;
  final int todayBites;
  const _StatRow({
    required this.activeSessions,
    required this.todaySessions,
    required this.pendingRefunds,
    required this.todayCashPaise,
    required this.todayBites,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _StatCard(
          label: 'Active sessions',
          value: '$activeSessions',
          icon: PhosphorIconsFill.pulse,
          color: AppColors.activeGreen,
        ),
        _StatCard(
          label: 'Today',
          value: '$todaySessions',
          icon: PhosphorIconsFill.calendar,
          color: AppColors.navy,
        ),
        _StatCard(
          label: 'Healthy bites today',
          value: '$todayBites',
          icon: PhosphorIconsFill.cookie,
          color: AppColors.xpPurple,
        ),
        _StatCard(
          label: 'Pending refunds',
          value: '$pendingRefunds',
          icon: PhosphorIconsFill.arrowUUpLeft,
          color: pendingRefunds > 0
              ? AppColors.adminRed
              : AppColors.lightTextSecondary,
        ),
        _StatCard(
          label: 'Cash today',
          value: Money.fromPaise(todayCashPaise),
          icon: PhosphorIconsFill.coins,
          color: AppColors.gold,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.h1(context, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionsCard extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const _ActiveSessionsCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Active sessions',
              style: AppTextStyles.h3(context),
            ),
          ),
          const Divider(height: 1, color: AppColors.lightBorder),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No active sessions right now.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            )
          else
            DataTable(
              columns: const [
                DataColumn(label: Text('Session')),
                DataColumn(label: Text('Duration')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Started')),
                DataColumn(label: Text('Payment')),
              ],
              rows: [
                for (final s in sessions)
                  DataRow(cells: [
                    DataCell(Text(
                      (s['id'] as String).substring(0, 8).toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    )),
                    DataCell(Text('${s['duration_minutes']} min')),
                    DataCell(_StatusChip(status: s['status'] as String? ?? '')),
                    DataCell(Text(_formatTime(s['started_at'] as String?))),
                    DataCell(Text(s['payment_method'] as String? ?? '—')),
                  ]),
              ],
            ),
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour =
          dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      return '$hour:${dt.minute.toString().padLeft(2, '0')}'
          ' ${dt.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = status == 'grace' ? AppColors.warningYellow : AppColors.activeGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}

class _NeedsAttentionCard extends StatelessWidget {
  final int pendingRefunds;
  const _NeedsAttentionCard({required this.pendingRefunds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.adminRed.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.adminRed.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.warning, color: AppColors.adminRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$pendingRefunds refund${pendingRefunds == 1 ? '' : 's'} pending approval — review on the Refunds tab.',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}
