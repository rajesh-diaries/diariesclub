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

/// Sessions where Healthy Bite is earned but not yet distributed. Tap
/// "Distribute" → PIN sheet → healthy_bite_distribute RPC.
///
/// Stripped back to the bare minimum after BUG-048: previous version
/// had Timer.periodic firing ref.invalidate every 30s + a RefreshIndicator
/// wrapping ListView-based loading/empty/error states, and rendered as a
/// completely black screen on Android with no recoverable back button.
/// This version is plain ConsumerWidget + when() + Center widgets — no
/// timers, no refresh wrappers, no list-style loading layouts. Refresh
/// is the AppBar action only.
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
        error: (e, _) => _ErrorView(
          error: e,
          onRetry: () => ref.invalidate(venuePendingHealthyBitesProvider),
          onBack: () => _back(context),
        ),
        data: (pending) => pending.isEmpty
            ? _EmptyState(venueId: venueId, onBack: () => _back(context))
            : _PendingList(
                items: pending,
                onAfterDistribute: () =>
                    ref.invalidate(venuePendingHealthyBitesProvider),
              ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: AppColors.adminRed),
            const SizedBox(height: 12),
            Text("Couldn't load pending Healthy Bites.",
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 8),
            Text('$error',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                )),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onBack,
              child: const Text('Back to staff home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? venueId;
  final VoidCallback onBack;
  const _EmptyState({required this.venueId, required this.onBack});

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
            Text('No pending Healthy Bites',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 4),
            Text(
              'Bites become eligible 10 minutes before a session ends. '
              'Tap refresh to check.',
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

class _PendingList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onAfterDistribute;
  const _PendingList({required this.items, required this.onAfterDistribute});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) =>
          _ClaimTile(session: items[i], onDone: onAfterDistribute),
    );
  }
}

class _ClaimTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onDone;
  const _ClaimTile({required this.session, required this.onDone});

  @override
  ConsumerState<_ClaimTile> createState() => _ClaimTileState();
}

class _ClaimTileState extends ConsumerState<_ClaimTile> {
  bool _busy = false;

  Future<void> _distribute() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Distribute Healthy Bite + hero card',
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
          content: Text(
            cardName == null
                ? 'Hero card given.'
                : 'Card given: $cardName${isRare ? ' (RARE!)' : ''}',
          ),
        ),
      );
      widget.onDone();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't distribute: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.gold,
            child: Icon(PhosphorIconsFill.carrot, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session ${(s['id'] as String).substring(0, 6).toUpperCase()}',
                  style: AppTextStyles.bodyLarge(context),
                ),
                Text(
                  '${s['duration_minutes']}-min · started ${_started(s)} · '
                  '${s['status']}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _distribute,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('Distribute'),
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
