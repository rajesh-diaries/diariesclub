import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/staff_auth_provider.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Healthy Bite decision screen (BUG-049 redesign).
///
/// One row per undecided session in the last 4 hours. Two buttons:
///   * Gave bite  → healthy_bite_distribute RPC (+25 XP, card unlock)
///   * Didn't give → healthy_bite_decline RPC (just records the decision)
///
/// Both flows go through StaffPinSheet so every action is attributable.
/// Once a session has a decision, it drops off the list automatically
/// after the next refresh (provider invalidate).
///
/// Implementation deliberately uses plain ListTile rows + FilledButtons
/// to avoid any fancy hit-test widgets after BUG-048's tap-reliability
/// problems on Android.
class HealthyBiteScreen extends ConsumerWidget {
  const HealthyBiteScreen({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/staff/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(venuePendingHealthyBitesProvider);
    final venueId = ref.watch(currentTabletVenueIdProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: const Text('Healthy Bite'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => _back(context),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.invalidate(venuePendingHealthyBitesProvider),
          ),
        ],
      ),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 56, color: AppColors.adminRed),
                const SizedBox(height: 12),
                Text("Couldn't load pending list",
                    style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 8),
                Text('$e',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    )),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(venuePendingHealthyBitesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _back(context),
                  child: const Text('Back to staff home'),
                ),
              ],
            ),
          ),
        ),
        data: (pending) => pending.isEmpty
            ? _Empty(venueId: venueId, onBack: () => _back(context))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _DecisionTile(
                  session: pending[i],
                  onDone: () =>
                      ref.invalidate(venuePendingHealthyBitesProvider),
                ),
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String? venueId;
  final VoidCallback onBack;
  const _Empty({required this.venueId, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.carrot,
                size: 56, color: AppColors.lightTextSecondary),
            const SizedBox(height: 12),
            Text('No pending Healthy Bite decisions',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 4),
            Text(
              'Sessions appear here while they are running and for 4 hours '
              'after they end. Tap refresh to check.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              venueId == null
                  ? 'venue: (none — not signed in as staff?)'
                  : 'venue: ${venueId!.substring(0, 8)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to staff home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onDone;
  const _DecisionTile({required this.session, required this.onDone});

  @override
  ConsumerState<_DecisionTile> createState() => _DecisionTileState();
}

class _DecisionTileState extends ConsumerState<_DecisionTile> {
  bool _busy = false;

  Future<void> _gave() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Give Healthy Bite + hero card (+25 XP)',
    );
    if (staff == null) return;
    setState(() => _busy = true);
    try {
      final raw = await Supabase.instance.client.rpc<dynamic>(
        'healthy_bite_distribute',
        params: {
          'p_session_id': widget.session['id'],
          'p_child_id': widget.session['child_id'],
          'p_staff_pin_id': staff.staffId,
        },
      );
      final result =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final cardName = result['card_name'] as String?;
      final isRare = result['is_rare'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.fitGreen,
          content: Text(
            cardName == null
                ? 'Healthy Bite given. +25 XP credited.'
                : 'Card given: $cardName${isRare ? ' (RARE!)' : ''}. +25 XP.',
          ),
        ),
      );
      widget.onDone();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't give bite: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _didnt() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Mark "did not take" — no XP, no card',
    );
    if (staff == null) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'healthy_bite_decline',
        params: {
          'p_session_id': widget.session['id'],
          'p_staff_pin_id': staff.staffId,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as not taken.')),
      );
      widget.onDone();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't update: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final childName =
        ((s['children'] as Map?)?['name'] as String?) ?? 'Child';
    final sessionShort =
        (s['id'] as String).substring(0, 6).toUpperCase();
    final status = s['status'] as String? ?? '?';
    final duration = s['duration_minutes'];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const CircleAvatar(
              backgroundColor: AppColors.gold,
              child: Icon(PhosphorIconsFill.carrot, color: Colors.white),
            ),
            title: Text(
              childName,
              style: AppTextStyles.bodyLarge(context),
            ),
            subtitle: Text(
              'Session $sessionShort · $duration-min · $status · '
              'started ${_started(s)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.lightBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _gave,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.fitGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Gave bite'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _didnt,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.lightTextSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side:
                          const BorderSide(color: AppColors.lightBorder),
                    ),
                    child: const Text("Didn't give"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _started(Map<String, dynamic> s) {
    final dt = DateTime.tryParse(s['started_at'] as String? ?? '')?.toLocal();
    if (dt == null) return '—';
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    return '$hour:${dt.minute.toString().padLeft(2, '0')}'
        ' ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }
}
