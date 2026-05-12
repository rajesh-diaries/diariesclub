import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

const _stages = [
  'welcome',
  'seedling',
  'explorer',
  'adventurer',
  'champion',
  'legend',
];

const _stageLabels = {
  'welcome': 'Welcome',
  'seedling': 'Seedling',
  'explorer': 'Explorer',
  'adventurer': 'Adventurer',
  'champion': 'Champion',
  'legend': 'Legend',
};

const _stageBlurbs = {
  'welcome': '0 XP — kid joined Diaries Club',
  'seedling': '1+ XP — first XP earned',
  'explorer': '200+ XP',
  'adventurer': '400+ XP',
  'champion': '800+ XP',
  'legend': '1500+ XP',
};

const _traits = ['rafi', 'ellie', 'gerry', 'zena'];

const _traitLabels = {
  'rafi': 'Rafi · Brave',
  'ellie': 'Ellie · Kind',
  'gerry': 'Gerry · Curious',
  'zena': 'Zena · Creative',
};

/// Admin CRUD for stage_perks. Each row = a perk that auto-generates a
/// redemption code when a kid's trait crosses that stage.
///
/// Non-welcome stages are split per character — a Rafi Seedling perk
/// only fires when a kid's Rafi (Brave) trait reaches Seedling. Keep
/// 2+ active perks per (stage, character) so the customer gets to pick
/// at claim time; with 1 active perk we auto-pick.
class StagePerksScreen extends ConsumerWidget {
  const StagePerksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stagePerksAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Stage perks'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(),
              const SizedBox(height: 16),
              async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text("Couldn't load perks: $e"),
                data: (rows) {
                  final unassigned = rows
                      .where((r) =>
                          r['stage'] != 'welcome' && r['trait'] == null)
                      .toList();
                  return Column(
                    children: [
                      if (unassigned.isNotEmpty) ...[
                        _UnassignedGroup(perks: unassigned),
                        const SizedBox(height: 16),
                      ],
                      for (final stage in _stages)
                        _StageGroup(
                          stage: stage,
                          allPerks: rows.where((r) => r['stage'] == stage).toList(),
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
          const Icon(PhosphorIconsRegular.gift,
              color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Each stage transition (per character, per kid) grants one '
              'perk slot. Keep 2+ active perks per section so customers '
              'can pick. With just 1 active perk, we auto-pick.',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top-of-screen callout for legacy non-welcome perks with trait = NULL.
/// They won't grant until admin assigns a character.
class _UnassignedGroup extends ConsumerWidget {
  final List<Map<String, dynamic>> perks;
  const _UnassignedGroup({required this.perks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.adminRed.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.adminRed.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.warningCircle,
                  color: AppColors.adminRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Needs character assignment',
                  style: AppTextStyles.h3(context)
                      .copyWith(color: AppColors.adminRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'These perks won\'t grant until you assign a character '
            '(Rafi / Ellie / Gerry / Zena). Edit each one or replace.',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in perks) _PerkTile(row: p, allowEdit: true),
        ],
      ),
    );
  }
}

class _StageGroup extends StatelessWidget {
  final String stage;
  final List<Map<String, dynamic>> allPerks;
  const _StageGroup({required this.stage, required this.allPerks});

  bool get _isWelcome => stage == 'welcome';

  @override
  Widget build(BuildContext context) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_stageLabels[stage] ?? stage,
                        style: AppTextStyles.h3(context)),
                    Text(_stageBlurbs[stage] ?? '',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isWelcome)
            _CharacterSection(
              stage: stage,
              trait: null,
              perks:
                  allPerks.where((p) => p['trait'] == null).toList(),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth > 720;
                final cellWidth = isWide
                    ? (c.maxWidth - 12) / 2
                    : c.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final trait in _traits)
                      SizedBox(
                        width: cellWidth,
                        child: _CharacterSection(
                          stage: stage,
                          trait: trait,
                          perks: allPerks
                              .where((p) => p['trait'] == trait)
                              .toList(),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CharacterSection extends ConsumerWidget {
  final String stage;
  final String? trait;
  final List<Map<String, dynamic>> perks;
  const _CharacterSection({
    required this.stage,
    required this.trait,
    required this.perks,
  });

  String get _title {
    if (trait == null) return _stageLabels[stage] ?? stage;
    return '${_stageLabels[stage]} — ${_traitLabels[trait]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount =
        perks.where((p) => (p['is_active'] as bool?) ?? false).length;
    final needsMore = stage != 'welcome' && activeCount < 2;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: AppTextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              AdminSecondaryButton(
                label: 'Add perk',
                icon: PhosphorIconsRegular.plus,
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => _PerkEditor(
                      stage: stage,
                      trait: trait,
                    ),
                  );
                  if (saved == true) {
                    ref.invalidate(stagePerksAdminProvider);
                  }
                },
              ),
            ],
          ),
          if (needsMore) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.info,
                  color: AppColors.gold,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    activeCount == 0
                        ? 'Add 2+ perks so customers can pick.'
                        : 'Add 1 more so customers can pick.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (perks.isEmpty)
            Text(
              'No perks yet.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            )
          else
            ...perks.map((p) => _PerkTile(row: p)),
        ],
      ),
    );
  }
}

class _PerkTile extends ConsumerWidget {
  final Map<String, dynamic> row;
  final bool allowEdit;
  const _PerkTile({required this.row, this.allowEdit = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = (row['is_active'] as bool?) ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: isActive
              ? AppColors.activeGreen.withValues(alpha: 0.40)
              : AppColors.lightBorder,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['perk_label'] as String?) ?? '—',
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w700,
                    decoration:
                        isActive ? null : TextDecoration.lineThrough,
                  ),
                ),
                if ((row['perk_description'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row['perk_description'] as String,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Valid ${row['validity_days']}d · '
                  '${isActive ? 'Active' : 'Inactive'}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (allowEdit)
            AdminIconButton(
              icon: PhosphorIconsRegular.pencilSimple,
              tooltip: 'Edit',
              onPressed: () async {
                final saved = await showDialog<bool>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => _PerkEditor(
                    stage: row['stage'] as String,
                    trait: row['trait'] as String?,
                    row: row,
                  ),
                );
                if (saved == true) {
                  ref.invalidate(stagePerksAdminProvider);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _PerkEditor extends StatefulWidget {
  final String stage;
  final String? trait;
  final Map<String, dynamic>? row;
  const _PerkEditor({
    required this.stage,
    required this.trait,
    this.row,
  });

  @override
  State<_PerkEditor> createState() => _PerkEditorState();
}

class _PerkEditorState extends State<_PerkEditor> {
  late final _label = TextEditingController(
    text: (widget.row?['perk_label'] as String?) ?? '',
  );
  late final _description = TextEditingController(
    text: (widget.row?['perk_description'] as String?) ?? '',
  );
  late final _validity = TextEditingController(
    text: '${widget.row?['validity_days'] ?? 30}',
  );
  late bool _isActive = (widget.row?['is_active'] as bool?) ?? true;
  late String? _trait =
      (widget.row?['trait'] as String?) ?? widget.trait;
  bool _busy = false;
  String? _error;

  bool get _isWelcome => widget.stage == 'welcome';

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    _validity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Label is required.');
      return;
    }
    if (!_isWelcome && _trait == null) {
      setState(() => _error = 'Pick a character.');
      return;
    }
    final days = int.tryParse(_validity.text.trim()) ?? 30;
    if (days < 1 || days > 365) {
      setState(() => _error = 'Validity must be 1–365 days.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_stage_perk_upsert',
        params: {
          'p_id': widget.row?['id'],
          'p_venue_id': null,
          'p_stage': widget.stage,
          'p_trait': _isWelcome ? null : _trait,
          'p_perk_label': _label.text.trim(),
          'p_perk_description': _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          'p_validity_days': days,
          'p_is_active': _isActive,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.row == null;
    final titleSuffix = _isWelcome
        ? _stageLabels[widget.stage]
        : '${_stageLabels[widget.stage]} — '
            '${_traitLabels[_trait] ?? "pick a character"}';
    return AlertDialog(
      title: Text(isNew ? 'New perk · $titleSuffix' : 'Edit perk'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isWelcome) ...[
                DropdownButtonFormField<String>(
                  initialValue: _trait,
                  decoration: const InputDecoration(
                    labelText: 'Character',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in _traits)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_traitLabels[t]!),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _trait = v),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (shown to customer)',
                  hintText: 'e.g. Free hot chocolate',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. Show this code at the counter',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _validity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Validity (days)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  "Inactive perks won't auto-grant on transitions, "
                  'but existing codes stay redeemable.',
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

final stagePerksAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('stage_perks')
      .select()
      .order('stage')
      .order('trait')
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows);
});
