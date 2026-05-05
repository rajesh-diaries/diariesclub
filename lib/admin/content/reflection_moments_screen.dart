import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_list_scaffold.dart';

/// Module 2.8 — reflection moments admin CRUD. Inline edit dialog
/// rather than a separate screen since each moment is just a handful
/// of fields.
class ReflectionMomentsScreen extends ConsumerWidget {
  const ReflectionMomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reflectionMomentsAdminProvider);
    return AdminListScaffold(
      title: 'Reflection moments',
      subtitle:
          'Tags shown in the post-session reflection sheet. Trait drives which hero awards XP.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New moment'),
            onPressed: () => _openEditor(context, ref, null),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.heartHalf,
        message: 'No moments yet.',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.lightSurface,
              border: Border.all(color: AppColors.lightBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final r in rows) ...[
                  _MomentRow(
                    row: r,
                    onTap: () => _openEditor(context, ref, r),
                  ),
                  if (r != rows.last)
                    const Divider(height: 1, color: AppColors.lightBorder),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? row,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MomentEditor(row: row),
    );
    if (saved == true) {
      ref.invalidate(reflectionMomentsAdminProvider);
    }
  }
}

class _MomentRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _MomentRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = (row['is_active'] as bool?) ?? true;
    final trait = (row['primary_trait'] as String?) ?? '—';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                '#${row['sort_order'] ?? 0}',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (row['display_text'] as String?) ?? '—',
                    style: AppTextStyles.body(context).copyWith(
                      decoration: isActive ? null : TextDecoration.lineThrough,
                      color:
                          isActive ? null : AppColors.lightTextSecondary,
                    ),
                  ),
                  Text(
                    (row['tag'] as String?) ?? '',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _TraitChip(trait: trait),
            const SizedBox(width: 16),
            SizedBox(
              width: 60,
              child: Text(
                '${row['xp_weight'] ?? 0}× XP',
                textAlign: TextAlign.right,
                style: AppTextStyles.caption(context),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(PhosphorIconsRegular.caretRight,
                size: 16, color: AppColors.lightTextSecondary),
          ],
        ),
      ),
    );
  }
}

class _TraitChip extends StatelessWidget {
  final String trait;
  const _TraitChip({required this.trait});

  static const _colors = <String, Color>{
    'rafi': Color(0xFFFF6B6B),
    'ellie': Color(0xFFFFB84D),
    'gerry': Color(0xFF4ECDC4),
    'zena': Color(0xFFA66BFF),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[trait] ?? AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        trait,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MomentEditor extends StatefulWidget {
  final Map<String, dynamic>? row;
  const _MomentEditor({required this.row});

  @override
  State<_MomentEditor> createState() => _MomentEditorState();
}

class _MomentEditorState extends State<_MomentEditor> {
  late final _tag = TextEditingController(
    text: (widget.row?['tag'] as String?) ?? '',
  );
  late final _displayText = TextEditingController(
    text: (widget.row?['display_text'] as String?) ?? '',
  );
  late final _icon = TextEditingController(
    text: (widget.row?['icon'] as String?) ?? '',
  );
  late final _xpWeight = TextEditingController(
    text: '${widget.row?['xp_weight'] ?? 1}',
  );
  late final _sortOrder = TextEditingController(
    text: '${widget.row?['sort_order'] ?? 0}',
  );
  late String _trait = (widget.row?['primary_trait'] as String?) ?? 'rafi';
  late bool _isActive = (widget.row?['is_active'] as bool?) ?? true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tag.dispose();
    _displayText.dispose();
    _icon.dispose();
    _xpWeight.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_reflection_moment_upsert',
        params: {
          'p_id': widget.row?['id'],
          'p_tag': _tag.text.trim(),
          'p_display_text': _displayText.text.trim(),
          'p_icon': _icon.text.trim().isEmpty ? null : _icon.text.trim(),
          'p_primary_trait': _trait,
          'p_xp_weight': double.tryParse(_xpWeight.text) ?? 1,
          'p_sort_order': int.tryParse(_sortOrder.text) ?? 0,
          'p_is_active': _isActive,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.row == null;
    return AlertDialog(
      title: Text(isNew ? 'New reflection moment' : 'Edit reflection moment'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _displayText,
                decoration: const InputDecoration(
                  labelText: 'Display text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tag,
                decoration: const InputDecoration(
                  labelText: 'Tag (snake_case)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _icon,
                decoration: const InputDecoration(
                  labelText: 'Icon name (optional)',
                  hintText: 'e.g. star, heart',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _trait,
                decoration: const InputDecoration(
                  labelText: 'Primary trait',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'rafi', child: Text('Rafi (courage)')),
                  DropdownMenuItem(value: 'ellie', child: Text('Ellie (kindness)')),
                  DropdownMenuItem(value: 'gerry', child: Text('Gerry (curiosity)')),
                  DropdownMenuItem(value: 'zena', child: Text('Zena (creativity)')),
                ],
                onChanged: (v) => setState(() => _trait = v ?? 'rafi'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _xpWeight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'XP weight',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sortOrder,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sort order',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTextStyles.caption(context,
                      color: AppColors.adminRed),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

final reflectionMomentsAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('reflection_moments')
      .select()
      .order('primary_trait', ascending: true)
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
