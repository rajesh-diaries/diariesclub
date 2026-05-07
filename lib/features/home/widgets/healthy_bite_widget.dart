import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Informational card shown on home when the latest session has
/// `healthy_bite_earned=true` AND `healthy_bite_distributed=false`.
///
/// CRITICAL: stream subscription is created ONCE in initState and stored
/// on the State. The earlier version constructed it inline inside build()
/// which re-subscribes on every rebuild — within seconds the customer app
/// had dozens of live realtime listeners and went unresponsive on
/// Android (BUG-048).
///
/// Realtime self-clear: the moment staff confirms distribution
/// (healthy_bite_distribute RPC sets distributed=true), the stream emits
/// and the card disappears. No client write — that was always RLS-blocked
/// and would have skipped the card+XP grant.
class HealthyBiteWidget extends ConsumerStatefulWidget {
  const HealthyBiteWidget({super.key});

  @override
  ConsumerState<HealthyBiteWidget> createState() => _HealthyBiteWidgetState();
}

class _HealthyBiteWidgetState extends ConsumerState<HealthyBiteWidget> {
  Stream<List<Map<String, dynamic>>>? _sessionsStream;
  String? _streamFamilyId;
  Set<String> _dismissed = const {};
  String? _childName;
  String? _lastChildId;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('hb_widget_dismissed_'))
        .map((k) => k.substring('hb_widget_dismissed_'.length))
        .toSet();
    if (!mounted) return;
    setState(() => _dismissed = keys);
  }

  // Lazy-build the stream on first build (we need familyId from ref). After
  // that, hold the same instance across rebuilds. Recreates only if the
  // signed-in family changes (e.g. sign-out/sign-in within session).
  Stream<List<Map<String, dynamic>>> _streamFor(String familyId) {
    if (_sessionsStream != null && _streamFamilyId == familyId) {
      return _sessionsStream!;
    }
    _streamFamilyId = familyId;
    _sessionsStream = Supabase.instance.client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('started_at', ascending: false);
    return _sessionsStream!;
  }

  Future<void> _dismiss(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hb_widget_dismissed_$sessionId', true);
    if (!mounted) return;
    setState(() => _dismissed = {..._dismissed, sessionId});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "We'll keep your Healthy Bite ready — show staff at the counter anytime.",
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _resolveChildName(String childId) async {
    if (_lastChildId == childId && _childName != null) return;
    _lastChildId = childId;
    try {
      final row = await Supabase.instance.client
          .from('children')
          .select('name')
          .eq('id', childId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _childName = (row?['name'] as String?) ?? 'Your child');
    } catch (_) {
      if (!mounted) return;
      setState(() => _childName = 'Your child');
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyId = ref.watch(currentFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamFor(familyId),
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        Map<String, dynamic>? row;
        for (final r in rows) {
          if (r['healthy_bite_earned'] != true) continue;
          if (r['healthy_bite_distributed'] == true) continue;
          final id = r['id'] as String?;
          if (id == null || _dismissed.contains(id)) continue;
          final startedRaw = r['started_at'] as String?;
          final started =
              startedRaw == null ? null : DateTime.tryParse(startedRaw);
          if (started == null || started.isBefore(cutoff)) continue;
          row = r;
          break;
        }
        if (row == null) return const SizedBox.shrink();

        final sessionId = row['id'] as String;
        final childId = row['child_id'] as String?;
        if (childId != null && _lastChildId != childId) {
          // Schedule child-name fetch out-of-build to avoid setState
          // during build assertions.
          scheduleMicrotask(() => _resolveChildName(childId));
        }
        final childName = _childName ?? 'Your child';

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            color: AppColors.fitGreen.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.fitGreen),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsFill.carrot,
                color: AppColors.fitGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$childName earned a Healthy Bite!',
                      style: AppTextStyles.bodyLarge(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Show this at the FIT counter — staff will hand it over.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.lightTextSecondary,
                ),
                onPressed: () => _dismiss(sessionId),
              ),
            ],
          ),
        );
      },
    );
  }
}
