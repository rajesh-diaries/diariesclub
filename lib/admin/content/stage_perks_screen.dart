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
  'explorer': '50+ XP',
  'adventurer': '150+ XP',
  'champion': '350+ XP',
  'legend': '700+ XP',
};

/// Admin CRUD for stage_perks. Each row = a perk that auto-generates a
/// redemption code for any kid whose trait crosses that stage.
/// Multiple perks per stage allowed (e.g. sticker + free brownie).
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
                  return Column(
                    children: [
                      for (final stage in _stages)
                        _StageGroup(
                          stage: stage,
                          perks:
                              rows.where((r) => r['stage'] == stage).toList(),
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
              'Each stage transition (per trait, per kid) auto-generates '
              'one perk code per active perk below. Codes expire after '
              'validity_days. Staff redeems at counter via /staff/redeem-perk.',
              style: AppTextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageGroup extends ConsumerWidget {
  final String stage;
  final List<Map<String, dynamic>> perks;
  const _StageGroup({required this.stage, required this.perks});

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
              AdminSecondaryButton(
                label: 'Add perk',
                icon: PhosphorIconsRegular.plus,
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => _PerkEditor(stage: stage),
                  );
                  if (saved == true) {
                    ref.invalidate(stagePerksAdminProvider);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (perks.isEmpty)
            Text(
              'No perks for this stage yet.',
              style: AppTextStyles.body(
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
  const _PerkTile({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = (row['is_active'] as bool?) ?? true;
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
                  (row['perk_label'] as String?) ?? '—',
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w800,
                    decoration: isActive
                        ? null
                        : TextDecoration.lineThrough,
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
                  'Valid for ${row['validity_days']} days · '
                  '${isActive ? 'Active' : 'Inactive'}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
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
                builder: (_) => _PerkEditor(
                  stage: row['stage'] as String,
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
  final Map<String, dynamic>? row;
  const _PerkEditor({required this.stage, this.row});

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
  bool _busy = false;
  String? _error;

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
          'p_perk_label': _label.text.trim(),
          'p_perk_description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
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
    return AlertDialog(
      title: Text(
        isNew
            ? 'New perk · ${_stageLabels[widget.stage] ?? widget.stage}'
            : 'Edit perk',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  'Inactive perks won\'t auto-grant on transitions, '
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
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows);
});
