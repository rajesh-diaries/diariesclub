import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Sessions where a Healthy Bite has been earned but not yet handed to
/// the child. Tap "Distribute" → PIN sheet → healthy_bite_distribute RPC
/// (rolls a hero card, marks session.healthy_bite_distributed=true).
class HealthyBiteScreen extends ConsumerWidget {
  const HealthyBiteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(venuePendingHealthyBitesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Healthy Bite')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text("Couldn't load pending list.\n$e"),
          ),
        ),
        data: (pending) => pending.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ClaimTile(session: pending[i]),
              ),
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
              PhosphorIconsRegular.carrot,
              size: 56,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text('No pending Healthy Bites',
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 4),
            Text(
              'Bites become eligible 10 minutes before a session ends.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const _ClaimTile({required this.session});

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
      final raw = await Supabase.instance.client
          .rpc<dynamic>('healthy_bite_distribute', params: {
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
                  '${s['duration_minutes']}-min · started ${_started(s)}',
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
