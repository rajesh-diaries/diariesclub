import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One reflection-moment card as returned by `reflection_moments_for_recap`.
class ReflectionMoment {
  final String id;
  final String tag;
  final String displayText;
  final String primaryTrait;
  final String? icon;
  final double xpWeight;
  final int sortOrder;

  const ReflectionMoment({
    required this.id,
    required this.tag,
    required this.displayText,
    required this.primaryTrait,
    required this.icon,
    required this.xpWeight,
    required this.sortOrder,
  });

  factory ReflectionMoment.fromJson(Map<String, dynamic> j) =>
      ReflectionMoment(
        id: j['id'] as String,
        tag: j['tag'] as String,
        displayText: j['display_text'] as String,
        primaryTrait: j['primary_trait'] as String,
        icon: j['icon'] as String?,
        xpWeight: (j['xp_weight'] as num).toDouble(),
        sortOrder: (j['sort_order'] as num).toInt(),
      );
}

/// 12-card sample for a session's recap. Looks up the recap by session_id,
/// then calls `reflection_moments_for_recap(p_recap_id)` — the server
/// hashes recap_id + tag to give a stable per-recap ordering, so closing
/// and reopening the reflection screen shows the same 12 cards.
final reflectionMomentsProvider = FutureProvider.family<
    List<ReflectionMoment>, String>((ref, sessionId) async {
  final recap = await Supabase.instance.client
      .from('hero_recaps')
      .select('id')
      .eq('session_id', sessionId)
      .maybeSingle();
  if (recap == null) return const [];

  final rows = await Supabase.instance.client.rpc<List<dynamic>>(
    'reflection_moments_for_recap',
    params: {'p_recap_id': recap['id']},
  );

  return rows
      .map((r) => ReflectionMoment.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();
});

/// Extended-tier moments per character — the wider pool shown via the
/// "+ More moments" sheet on the reflection screen AND the standalone
/// Adventure-tab "My kid did this" sheet. Admin-managed via the same
/// Reflection moments screen (filter by tier='extended').
final extendedReflectionMomentsProvider = FutureProvider.family<
    List<ReflectionMoment>, String>((ref, trait) async {
  final rows = await Supabase.instance.client
      .from('reflection_moments')
      .select(
        'id, tag, display_text, primary_trait, icon, xp_weight, sort_order',
      )
      .eq('primary_trait', trait)
      .eq('tier', 'extended')
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List)
      .map((r) => ReflectionMoment.fromJson(Map<String, dynamic>.from(r as Map)))
      .toList();
});
