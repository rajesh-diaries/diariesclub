import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row from `hero_card_definitions` joined with the (optional)
/// `hero_card_collection` row for the current child. Carries the earned
/// timestamp + session reference when the child has the card; nulls
/// otherwise so the grid can render the silhouette state.
class HeroCardRow {
  final Map<String, dynamic> definition;
  final Map<String, dynamic>? collection;

  const HeroCardRow({required this.definition, this.collection});

  String get id => definition['id'] as String;
  String get name => (definition['name'] as String?) ?? '';
  String get hero => (definition['hero'] as String?) ?? '';
  bool get isRare => definition['is_rare'] == true;
  bool get isBirthdayExclusive => definition['is_birthday_exclusive'] == true;
  String? get imageUrl => definition['image_url'] as String?;
  String? get description => definition['description'] as String?;
  String get unlockMethod =>
      (definition['unlock_method'] as String?) ?? 'random_drop';
  String? get unlockStage => definition['unlock_stage'] as String?;
  bool get isSurprise => unlockMethod == 'surprise';
  bool get isStageCard => unlockMethod == 'stage';

  bool get isEarned => collection != null;
  DateTime? get earnedAt => collection == null
      ? null
      : DateTime.tryParse(collection!['earned_at'] as String? ?? '');
  String? get sessionId => collection?['session_id'] as String?;
  String? get birthdayBookingId =>
      collection?['birthday_booking_id'] as String?;
}

/// One-shot fetch of every hero_card_definition. Definitions don't mutate
/// at runtime so a Realtime stream is overkill.
final allHeroCardDefinitionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('hero_card_definitions')
      .select()
      .eq('is_active', true)
      .order('hero', ascending: true)
      .order('is_rare', ascending: true)
      .order('name', ascending: true);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

/// Realtime stream of THIS child's hero_card_collection rows. Lets the
/// dashboard light up the moment a healthy_bite_distribute or birthday
/// completion lands. `hero_card_collection` is in supabase_realtime per
/// migration 0013.
final earnedCardsStreamProvider = StreamProvider.family<
    List<Map<String, dynamic>>, String>((ref, childId) async* {
  final stream = Supabase.instance.client
      .from('hero_card_collection')
      .stream(primaryKey: ['id'])
      .eq('child_id', childId)
      .order('earned_at', ascending: false);
  await for (final rows in stream) {
    yield rows;
  }
});

/// Composed view: definitions × earned-status for one child. Used by the
/// master grid + the per-trait detail screen. Watching this provider
/// implicitly subscribes to both inputs — definitions reload only at
/// invalidate time, earned rows update live.
final heroCardsForChildProvider =
    Provider.family<List<HeroCardRow>, String>((ref, childId) {
  final defs =
      ref.watch(allHeroCardDefinitionsProvider).valueOrNull ?? const [];
  final earned =
      ref.watch(earnedCardsStreamProvider(childId)).valueOrNull ?? const [];
  final byCardId = <String, Map<String, dynamic>>{
    for (final r in earned) r['card_id'] as String: r,
  };
  return defs
      .map((d) => HeroCardRow(
            definition: d,
            collection: byCardId[d['id']],
          ))
      .toList();
});
