import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

const _heroes = ['rafi', 'ellie', 'gerry', 'zena'];

const _heroLabels = {
  'rafi': 'Rafi · Brave',
  'ellie': 'Ellie · Kind',
  'gerry': 'Gerry · Curious',
  'zena': 'Zena · Creative',
};

const _eventTypes = [
  ('session_complete', 'Session complete'),
  ('workshop_attend', 'Workshop attended'),
  ('healthy_bite', 'Healthy Bite distributed'),
  ('fit_meal_order', 'FIT meal ordered'),
  ('reflection_save', 'Reflection submitted'),
];

const _eventLabels = {
  'session_complete': 'Session complete',
  'workshop_attend': 'Workshop attended',
  'healthy_bite': 'Healthy Bite distributed',
  'fit_meal_order': 'FIT meal ordered',
  'reflection_save': 'Reflection submitted',
};

/// Admin layer for Weekly Hero Quests:
///   * Top: 'This week' picker — one quest per hero for the current week.
///   * Below: All quest definitions, grouped by hero. Add / edit dialog.
class HeroQuestsScreen extends ConsumerWidget {
  const HeroQuestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defsAsync = ref.watch(heroQuestDefinitionsAdminProvider);
    final weekAsync = ref.watch(heroQuestWeekCurrentProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Weekly Hero Quests'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              const SizedBox(height: 16),
              _ThisWeekPicker(defsAsync: defsAsync, weekAsync: weekAsync),
              const SizedBox(height: 32),
              Text('All quest definitions', style: AppTextStyles.h2(context)),
              const SizedBox(height: 12),
              defsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text("Couldn't load: $e"),
                data: (rows) {
                  return Column(
                    children: [
                      for (final hero in _heroes)
                        _HeroDefGroup(
                          hero: hero,
                          rows:
                              rows.where((r) => r['hero'] == hero).toList(),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.compass,
              color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Each Monday, schedule one quest per hero. Auto-detect fires '
              'on the right event (session, workshop, healthy bite, FIT meal, '
              'or reflection) and grants xp_bonus to the matching hero.',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThisWeekPicker extends ConsumerWidget {
  final AsyncValue<List<Map<String, dynamic>>> defsAsync;
  final AsyncValue<Map<String, dynamic>?> weekAsync;
  const _ThisWeekPicker({required this.defsAsync, required this.weekAsync});

  Future<void> _setSlot(BuildContext context, WidgetRef ref, String hero,
      String? questId) async {
    final week = ref.read(currentWeekDateProvider);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_quest_week_set',
        params: {
          'p_week_start_date': week,
          'p_hero': hero,
          'p_quest_id': questId,
        },
      );
      ref.invalidate(heroQuestWeekCurrentProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated ${_heroLabels[hero] ?? hero}.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(currentWeekDateProvider);
    final defs = defsAsync.valueOrNull ?? const [];
    final weekRow = weekAsync.valueOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('This week', style: AppTextStyles.h2(context)),
              ),
              Text('starts $week',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          for (final hero in _heroes)
            _HeroSlotRow(
              hero: hero,
              activeQuestId: switch (hero) {
                'rafi' => weekRow?['quest_id_rafi'] as String?,
                'ellie' => weekRow?['quest_id_ellie'] as String?,
                'gerry' => weekRow?['quest_id_gerry'] as String?,
                _ => weekRow?['quest_id_zena'] as String?,
              },
              available: defs
                  .where((d) =>
                      d['hero'] == hero && (d['is_active'] as bool? ?? true))
                  .toList(),
              onChanged: (id) => _setSlot(context, ref, hero, id),
            ),
        ],
      ),
    );
  }
}

class _HeroSlotRow extends StatelessWidget {
  final String hero;
  final String? activeQuestId;
  final List<Map<String, dynamic>> available;
  final ValueChanged<String?> onChanged;
  const _HeroSlotRow({
    required this.hero,
    required this.activeQuestId,
    required this.available,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (hero) {
      'rafi' => const Color(0xFFE8524A),
      'ellie' => const Color(0xFF4A90E2),
      'gerry' => const Color(0xFFF39C12),
      _ => const Color(0xFF27AE60),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(_heroIcon(hero), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(_heroLabels[hero] ?? hero,
                style: AppTextStyles.body(context).copyWith(
                  fontWeight: FontWeight.w800,
                )),
          ),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: activeQuestId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('— No quest this week —')),
                for (final d in available)
                  DropdownMenuItem<String?>(
                    value: d['id'] as String,
                    child: Text(
                      '${d['title']} (+${d['xp_bonus']} XP)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  IconData _heroIcon(String h) => switch (h) {
        'rafi' => PhosphorIconsFill.shieldStar,
        'ellie' => PhosphorIconsFill.heart,
        'gerry' => PhosphorIconsFill.magnifyingGlass,
        'zena' => PhosphorIconsFill.palette,
        _ => PhosphorIconsFill.sparkle,
      };
}

class _HeroDefGroup extends ConsumerWidget {
  final String hero;
  final List<Map<String, dynamic>> rows;
  const _HeroDefGroup({required this.hero, required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_heroLabels[hero] ?? hero,
                    style: AppTextStyles.h3(context)),
              ),
              AdminSecondaryButton(
                label: 'Add quest',
                icon: PhosphorIconsRegular.plus,
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => _QuestEditor(hero: hero),
                  );
                  if (saved == true) {
                    ref.invalidate(heroQuestDefinitionsAdminProvider);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No quests for this hero yet.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            )
          else
            ...rows.map((r) => _QuestTile(row: r)),
        ],
      ),
    );
  }
}

class _QuestTile extends ConsumerWidget {
  final Map<String, dynamic> row;
  const _QuestTile({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = (row['is_active'] as bool?) ?? true;
    final eventType = (row['completion_event_type'] as String?) ?? '';
    final predicate = row['completion_predicate'];
    final predicateText = predicate == null
        ? '{}'
        : (predicate is Map ? jsonEncode(predicate) : predicate.toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isActive
              ? AppColors.activeGreen.withValues(alpha: 0.40)
              : AppColors.lightBorder,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['title'] as String?) ?? '—',
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: isActive ? null : TextDecoration.lineThrough,
                  ),
                ),
                if ((row['description'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(row['description'] as String,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        )),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _MiniBadge(
                      label: _eventLabels[eventType] ?? eventType,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    if (predicateText != '{}')
                      _MiniBadge(
                        label: predicateText,
                        color: AppColors.lightTextSecondary,
                      ),
                    const SizedBox(width: 6),
                    _MiniBadge(
                      label: '+${row['xp_bonus']} XP',
                      color: AppColors.gold,
                    ),
                  ],
                ),
              ],
            ),
          ),
          AdminIconButton(
            icon: PhosphorIconsRegular.pencilSimple,
            tooltip: 'Edit',
            onPressed: () async {
              final saved = await showDialog<bool>(
                context: context,
                useRootNavigator: true,
                builder: (_) => _QuestEditor(
                  hero: row['hero'] as String,
                  row: row,
                ),
              );
              if (saved == true) {
                ref.invalidate(heroQuestDefinitionsAdminProvider);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _QuestEditor extends StatefulWidget {
  final String hero;
  final Map<String, dynamic>? row;
  const _QuestEditor({required this.hero, this.row});

  @override
  State<_QuestEditor> createState() => _QuestEditorState();
}

class _QuestEditorState extends State<_QuestEditor> {
  late final _title = TextEditingController(
    text: (widget.row?['title'] as String?) ?? '',
  );
  late final _description = TextEditingController(
    text: (widget.row?['description'] as String?) ?? '',
  );
  late final _xpBonus = TextEditingController(
    text: '${widget.row?['xp_bonus'] ?? 50}',
  );
  late final _predicate = TextEditingController(
    text: widget.row?['completion_predicate'] == null
        ? '{}'
        : jsonEncode(widget.row!['completion_predicate']),
  );
  late String _eventType =
      (widget.row?['completion_event_type'] as String?) ?? 'session_complete';
  late bool _isActive = (widget.row?['is_active'] as bool?) ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _xpBonus.dispose();
    _predicate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title required.');
      return;
    }
    final xp = int.tryParse(_xpBonus.text.trim()) ?? 50;
    if (xp < 0 || xp > 1000) {
      setState(() => _error = 'XP bonus must be 0..1000.');
      return;
    }
    Map<String, dynamic> predicate = const {};
    final raw = _predicate.text.trim();
    if (raw.isNotEmpty && raw != '{}') {
      try {
        predicate = jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        setState(() => _error = 'Predicate must be valid JSON: $e');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_quest_def_upsert',
        params: {
          'p_id': widget.row?['id'],
          'p_hero': widget.hero,
          'p_title': _title.text.trim(),
          'p_description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          'p_completion_event_type': _eventType,
          'p_completion_predicate': predicate,
          'p_xp_bonus': xp,
          'p_is_active': _isActive,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.row == null;
    return AlertDialog(
      title: Text(
        isNew
            ? 'New quest · ${_heroLabels[widget.hero] ?? widget.hero}'
            : 'Edit quest',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title (shown to customer)',
                  hintText: 'e.g. Brave Marathon',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Play a full 2-hour session this week.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _eventType,
                decoration: const InputDecoration(
                  labelText: 'Triggering event',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in _eventTypes)
                    DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                ],
                onChanged: (v) =>
                    setState(() => _eventType = v ?? 'session_complete'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _predicate,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Predicate (JSON, optional)',
                  hintText:
                      '{} = match anything · {"min_duration_minutes":120} · {"is_guest":true}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _xpBonus,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'XP bonus (0..1000)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive quests can\'t be scheduled or matched. '
                  'Existing scheduled-for-this-week assignments stay until '
                  'admin reschedules.',
                ),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.adminRed,
                    )),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Cancel',
          ghost: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: isNew ? 'Create' : 'Save',
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

// ─── providers ─────────────────────────────────────────────────────────────

final currentWeekDateProvider = Provider<String>((ref) {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  // Monday IST. weekday: Mon=1..Sun=7. Subtract weekday-1 days.
  final monday = DateTime.utc(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  return '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
});

final heroQuestDefinitionsAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('hero_quest_definitions')
      .select()
      .order('hero')
      .order('title');
  return List<Map<String, dynamic>>.from(rows);
});

final heroQuestWeekCurrentProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final week = ref.watch(currentWeekDateProvider);
  final row = await Supabase.instance.client
      .from('hero_quest_weeks')
      .select()
      .eq('week_start_date', week)
      .maybeSingle();
  return row;
});
