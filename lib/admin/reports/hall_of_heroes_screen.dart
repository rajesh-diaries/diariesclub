import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// /admin/reports/hall-of-heroes — print-friendly leaderboard for the
/// venue wall. Lists every active kid by total_xp DESC, with overall
/// stage, per-trait stages, and a 'Hero Within' badge column for the
/// kids who've Legend'd all four traits.
///
/// The founder prints / screenshots this monthly to refresh the
/// physical "Hall of Heroes" wall at the venue.
class HallOfHeroesScreen extends ConsumerStatefulWidget {
  const HallOfHeroesScreen({super.key});

  @override
  ConsumerState<HallOfHeroesScreen> createState() =>
      _HallOfHeroesScreenState();
}

class _HallOfHeroesScreenState extends ConsumerState<HallOfHeroesScreen> {
  String _stageFilter = 'all';
  String _sortBy = 'total_xp';

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(_hallOfHeroesProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Hall of Heroes'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Every kid by total XP. Print this for the venue wall — '
                    'Champions in bigger letters, Hero-Within unlocks at the top.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AdminSecondaryButton(
                  label: 'Refresh',
                  onPressed: () => ref.invalidate(_hallOfHeroesProvider),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StageFilterChip(
                  label: 'All',
                  value: 'all',
                  selected: _stageFilter,
                  onSelect: (v) => setState(() => _stageFilter = v),
                ),
                _StageFilterChip(
                  label: 'Legends',
                  value: 'legend',
                  selected: _stageFilter,
                  onSelect: (v) => setState(() => _stageFilter = v),
                ),
                _StageFilterChip(
                  label: 'Champions',
                  value: 'champion',
                  selected: _stageFilter,
                  onSelect: (v) => setState(() => _stageFilter = v),
                ),
                _StageFilterChip(
                  label: 'Adventurers',
                  value: 'adventurer',
                  selected: _stageFilter,
                  onSelect: (v) => setState(() => _stageFilter = v),
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: 'total_xp', child: Text('Sort: Total XP')),
                    DropdownMenuItem(
                        value: 'name', child: Text('Sort: Name')),
                    DropdownMenuItem(
                        value: 'family', child: Text('Sort: Family')),
                  ],
                  onChanged: (v) => setState(() => _sortBy = v ?? 'total_xp'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rowsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    "Couldn't load: $e",
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ),
                data: (rows) {
                  final filtered = _filtered(rows);
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No kids match this filter.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    );
                  }
                  return _HeroesTable(rows: filtered);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    final out = _stageFilter == 'all'
        ? List<Map<String, dynamic>>.from(rows)
        : rows
            .where((r) => r['current_overall_stage'] == _stageFilter)
            .toList();
    switch (_sortBy) {
      case 'name':
        out.sort((a, b) => ((a['name'] as String?) ?? '')
            .toLowerCase()
            .compareTo(((b['name'] as String?) ?? '').toLowerCase()));
        break;
      case 'family':
        out.sort((a, b) => ((a['family_name'] as String?) ?? '')
            .toLowerCase()
            .compareTo(((b['family_name'] as String?) ?? '').toLowerCase()));
        break;
      default:
        out.sort((a, b) =>
            ((b['total_xp'] as int?) ?? 0).compareTo((a['total_xp'] as int?) ?? 0));
    }
    return out;
  }
}

class _StageFilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelect;
  const _StageFilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onSelect(value),
      ),
    );
  }
}

class _HeroesTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _HeroesTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.lightBorder),
        itemBuilder: (context, i) {
          if (i == 0) return const _TableHeader();
          final r = rows[i - 1];
          return _HeroRow(rank: i, row: r);
        },
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final s = AppTextStyles.caption(
      context,
      color: AppColors.lightTextSecondary,
    ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('#', style: s)),
          Expanded(flex: 3, child: Text('HERO', style: s)),
          Expanded(flex: 3, child: Text('FAMILY', style: s)),
          Expanded(flex: 2, child: Text('STAGE', style: s)),
          SizedBox(width: 120, child: Text('TRAITS', style: s)),
          SizedBox(width: 80, child: Text('XP', style: s, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _HeroRow extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> row;
  const _HeroRow({required this.rank, required this.row});

  @override
  Widget build(BuildContext context) {
    final stage = (row['current_overall_stage'] as String?) ?? 'seedling';
    final isLegend = stage == 'legend';
    final isChampion = stage == 'champion';
    final heroWithin = row['hero_within_unlocked'] == true;

    final nameStyle = (isLegend
            ? AppTextStyles.h3(context)
            : isChampion
                ? AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w800)
                : AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w700))
        .copyWith(
      color: heroWithin ? AppColors.gold : null,
    );

    return Container(
      color: heroWithin
          ? AppColors.gold.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$rank',
              style: AppTextStyles.body(context).copyWith(
                color: AppColors.lightTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    (row['name'] as String?) ?? '—',
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (heroWithin) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    PhosphorIconsFill.crown,
                    color: AppColors.gold,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              (row['family_name'] as String?) ?? '—',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: _StageBadge(stage: stage),
          ),
          SizedBox(
            width: 120,
            child: _TraitDots(row: row),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${row['total_xp'] ?? 0}',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final String stage;
  const _StageBadge({required this.stage});

  static const _colors = {
    'welcome':    Color(0xFFB0BEC5),
    'seedling':   Color(0xFF66BB6A),
    'explorer':   Color(0xFF42A5F5),
    'adventurer': Color(0xFF7E57C2),
    'champion':   Color(0xFFFFB300),
    'legend':     Color(0xFFFF6F00),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[stage] ?? AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        stage.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

class _TraitDots extends StatelessWidget {
  final Map<String, dynamic> row;
  const _TraitDots({required this.row});

  static const _heroes = ['rafi', 'ellie', 'gerry', 'zena'];
  static const _heroColors = {
    'rafi': Color(0xFFE8524A),
    'ellie': Color(0xFF4A90E2),
    'gerry': Color(0xFFF39C12),
    'zena': Color(0xFF27AE60),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final h in _heroes) ...[
          _StageDot(
            stage: (row['stage_$h'] as String?) ?? 'seedling',
            color: _heroColors[h]!,
          ),
          if (h != _heroes.last) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _StageDot extends StatelessWidget {
  final String stage;
  final Color color;
  const _StageDot({required this.stage, required this.color});

  static const _stageOrder = [
    'welcome','seedling','explorer','adventurer','champion','legend',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _stageOrder.indexOf(stage);
    // Render 6 mini-dots, fill in based on stage progress.
    return Row(
      children: [
        for (int i = 0; i < 6; i++) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= idx ? color : color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
          ),
          if (i != 5) const SizedBox(width: 2),
        ],
      ],
    );
  }
}

// ─── provider ──────────────────────────────────────────────────────────────

final _hallOfHeroesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Pull all kids with total_xp > 0, plus family name, plus a flag for
  // hero-within unlocks. Two queries because admin_family_search isn't
  // designed for this; instead we go direct against children + families
  // (admin RLS allows admin reads).
  final children = await Supabase.instance.client
      .from('children')
      .select('id, name, family_id, total_xp, current_overall_stage, '
          'stage_rafi, stage_ellie, stage_gerry, stage_zena')
      .gt('total_xp', 0)
      .filter('deleted_at', 'is', null)
      .order('total_xp', ascending: false)
      .limit(500);

  final childList = List<Map<String, dynamic>>.from(children);
  if (childList.isEmpty) return const [];

  final familyIds = childList
      .map((c) => c['family_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();

  final families = await Supabase.instance.client
      .from('families')
      .select('id, name')
      .inFilter('id', familyIds);
  final familyByIdRaw = List<Map<String, dynamic>>.from(families);
  final familyById = {
    for (final f in familyByIdRaw) f['id'] as String: f['name'] as String?
  };

  final unlocks = await Supabase.instance.client
      .from('hero_within_unlocks')
      .select('child_id');
  final unlockedSet = {
    for (final r in List<Map<String, dynamic>>.from(unlocks))
      r['child_id'] as String,
  };

  return [
    for (final c in childList)
      {
        ...c,
        'family_name': familyById[c['family_id'] as String?] ?? '',
        'hero_within_unlocked': unlockedSet.contains(c['id'] as String),
      },
  ];
});
