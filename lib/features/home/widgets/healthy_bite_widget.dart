import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Informational card shown on home when a session has
/// `healthy_bite_earned=true` AND `healthy_bite_distributed=false`.
///
/// Three ways the card can disappear:
///   1. Staff confirms distribution → realtime stream sees
///      `healthy_bite_distributed=true` and the row drops out.
///   2. Customer taps the close X → local SharedPreferences flag
///      `hb_widget_dismissed_<sessionId>` set; widget filters out
///      that session for this device only. (Backend state untouched
///      so they can still claim at the counter.)
///   3. The session is older than 24h — auto-stale, stops showing.
///
/// History note: this used to have an "I got it" button that flipped
/// `distributed=true` client-side. That was RLS-blocked AND wrong
/// architecturally — under v2 (BUG-044), distribution is a staff RPC
/// that mints a card and credits +20 XP. The button is gone; tapping
/// the close X is local-dismiss only and leaves the actual claim
/// state intact so the customer can still walk to the counter.
class HealthyBiteWidget extends ConsumerStatefulWidget {
  const HealthyBiteWidget({super.key});

  @override
  ConsumerState<HealthyBiteWidget> createState() => _HealthyBiteWidgetState();
}

class _HealthyBiteWidgetState extends ConsumerState<HealthyBiteWidget> {
  Set<String> _dismissed = const {};

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys()
        .where((k) => k.startsWith('hb_widget_dismissed_'))
        .map((k) => k.substring('hb_widget_dismissed_'.length))
        .toSet();
    if (!mounted) return;
    setState(() => _dismissed = keys);
  }

  Future<void> _dismiss(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hb_widget_dismissed_$sessionId', true);
    if (!mounted) return;
    setState(() => _dismissed = {..._dismissed, sessionId});
    // Subtle confirmation — reassures customer they can still claim.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "We'll keep your Healthy Bite ready — show staff at the counter anytime.",
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyId = ref.watch(currentFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('sessions')
          .stream(primaryKey: ['id'])
          .eq('family_id', familyId)
          .order('started_at', ascending: false),
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
          final started = startedRaw == null
              ? null
              : DateTime.tryParse(startedRaw);
          if (started == null || started.isBefore(cutoff)) continue;
          row = r;
          break;
        }
        if (row == null) return const SizedBox.shrink();

        final sessionId = row['id'] as String;
        final childId = row['child_id'] as String?;
        return _Body(
          sessionId: sessionId,
          childId: childId,
          onDismiss: () => _dismiss(sessionId),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final String sessionId;
  final String? childId;
  final VoidCallback onDismiss;
  const _Body({
    required this.sessionId,
    required this.childId,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: childId == null
          ? Future.value(null)
          : Supabase.instance.client
              .from('children')
              .select('name')
              .eq('id', childId!)
              .maybeSingle(),
      builder: (context, snap) {
        final childName = (snap.data?['name'] as String?) ?? 'Your child';
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
                onPressed: onDismiss,
              ),
            ],
          ),
        );
      },
    );
  }
}
