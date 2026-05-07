import 'dart:async';

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

/// Sessions where a Healthy Bite has been earned but not yet handed to
/// the child. Tap "Distribute" → PIN sheet → healthy_bite_distribute RPC
/// (rolls a hero card, marks distributed=true, claimed_at=now(), credits
/// +20 XP, fires unbox notification).
///
/// BUG-046 followup: was a StreamProvider that left the body blank when
/// the realtime subscription hung. Now a polling FutureProvider with a
/// 30s tick + manual refresh. Empty state shows diagnostics (venue,
/// count, last-refresh) so any "why is this empty?" question is
/// answerable without dropping into devtools.
class HealthyBiteScreen extends ConsumerStatefulWidget {
  const HealthyBiteScreen({super.key});

  @override
  ConsumerState<HealthyBiteScreen> createState() => _HealthyBiteScreenState();
}

class _HealthyBiteScreenState extends ConsumerState<HealthyBiteScreen> {
  Timer? _ticker;
  DateTime _lastRefreshed = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    ref.invalidate(venuePendingHealthyBitesProvider);
    setState(() => _lastRefreshed = DateTime.now());
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/staff/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(venuePendingHealthyBitesProvider);
    final venueId = ref.watch(currentTabletVenueIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Healthy Bite'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _back,
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: pendingAsync.when(
          loading: () => _LoadingView(venueId: venueId),
          error: (e, _) => _ErrorView(
            error: e,
            onRetry: _refresh,
            onBack: _back,
          ),
          data: (pending) => pending.isEmpty
              ? _EmptyState(
                  venueId: venueId,
                  lastRefreshed: _lastRefreshed,
                  onBack: _back,
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: pending.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _ClaimTile(
                    session: pending[i],
                    onDone: _refresh,
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Loading
// ---------------------------------------------------------------------------
class _LoadingView extends StatelessWidget {
  final String? venueId;
  const _LoadingView({required this.venueId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Loading pending Healthy Bites…',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            venueId == null
                ? '(no venue context)'
                : 'venue: ${venueId!.substring(0, 6)}',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Error
// ---------------------------------------------------------------------------
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        const Icon(
          Icons.error_outline,
          size: 56,
          color: AppColors.adminRed,
        ),
        const SizedBox(height: 12),
        Text(
          "Couldn't load pending Healthy Bites.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLarge(context),
        ),
        const SizedBox(height: 8),
        Text(
          '$error',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
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
    );
  }
}

// ---------------------------------------------------------------------------
//  Empty state with diagnostics
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final String? venueId;
  final DateTime lastRefreshed;
  final VoidCallback onBack;
  const _EmptyState({
    required this.venueId,
    required this.lastRefreshed,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(lastRefreshed).inSeconds;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(
          PhosphorIconsRegular.carrot,
          size: 56,
          color: AppColors.lightTextSecondary,
        ),
        const SizedBox(height: 12),
        Text(
          'No pending Healthy Bites',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLarge(context),
        ),
        const SizedBox(height: 4),
        Text(
          'Bites become eligible 10 minutes before a session ends. '
          'They show up here automatically — pull down or tap refresh '
          'to check now.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            border: Border.all(color: AppColors.lightBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _DiagRow(
                label: 'venue',
                value: venueId == null
                    ? '(none — not signed in as staff?)'
                    : venueId!.substring(0, 8),
              ),
              _DiagRow(
                label: 'last check',
                value: ago < 5 ? 'just now' : '${ago}s ago',
              ),
              const _DiagRow(
                label: 'window',
                value: 'last 4 hours',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to staff home'),
        ),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  const _DiagRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.caption(context),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Single pending tile + Distribute action
// ---------------------------------------------------------------------------
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
      final raw =
          await Supabase.instance.client.rpc<dynamic>('healthy_bite_distribute',
              params: {
            'p_session_id': widget.session['id'],
            'p_child_id': widget.session['child_id'],
            'p_staff_pin_id': staff.staffId,
          });
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
