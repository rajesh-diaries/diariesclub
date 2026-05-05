import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_list_scaffold.dart';

/// Module 2.8 — hero cards admin CRUD. Card grid grouped by hero.
class HeroCardsScreen extends ConsumerWidget {
  const HeroCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(heroCardsAdminProvider);
    return AdminListScaffold(
      title: 'Hero cards',
      subtitle:
          'Awarded for hero moments. Description shows in the collection sheet.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            label: const Text('New card'),
            onPressed: () => _openEditor(context, ref, null),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.shieldCheck,
        message: 'No hero cards yet.',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => SingleChildScrollView(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final r in rows)
                _HeroCardTile(
                  row: r,
                  onTap: () => _openEditor(context, ref, r),
                ),
            ],
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
      builder: (_) => _HeroCardEditor(row: row),
    );
    if (saved == true) {
      ref.invalidate(heroCardsAdminProvider);
    }
  }
}

class _HeroCardTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _HeroCardTile({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = row['image_url'] as String?;
    final hero = (row['hero'] as String?) ?? '—';
    final isActive = (row['is_active'] as bool?) ?? true;
    final isRare = (row['is_rare'] as bool?) ?? false;
    final isBday = (row['is_birthday_exclusive'] as bool?) ?? false;

    return SizedBox(
      width: 240,
      child: Material(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.lightBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: image == null || image.isEmpty
                      ? Container(
                          color: AppColors.gold.withValues(alpha: 0.18),
                          alignment: Alignment.center,
                          child: const Icon(
                            PhosphorIconsFill.shieldStar,
                            size: 56,
                            color: AppColors.gold,
                          ),
                        )
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.gold.withValues(alpha: 0.18),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (row['name'] as String?) ?? '—',
                        style: AppTextStyles.body(context).copyWith(
                          fontWeight: FontWeight.w800,
                          decoration:
                              isActive ? null : TextDecoration.lineThrough,
                          color: isActive
                              ? null
                              : AppColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hero,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (isRare)
                            const _MiniChip(
                              label: 'Rare',
                              color: Color(0xFFA66BFF),
                            ),
                          if (isBday)
                            const _MiniChip(
                              label: 'Birthday',
                              color: AppColors.gold,
                            ),
                          if (!isActive)
                            const _MiniChip(
                              label: 'Hidden',
                              color: AppColors.lightTextSecondary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _HeroCardEditor extends StatefulWidget {
  final Map<String, dynamic>? row;
  const _HeroCardEditor({required this.row});

  @override
  State<_HeroCardEditor> createState() => _HeroCardEditorState();
}

class _HeroCardEditorState extends State<_HeroCardEditor> {
  late final _name = TextEditingController(
    text: (widget.row?['name'] as String?) ?? '',
  );
  late final _description = TextEditingController(
    text: (widget.row?['description'] as String?) ?? '',
  );
  late final _imageUrl = TextEditingController(
    text: (widget.row?['image_url'] as String?) ?? '',
  );
  late String _hero = (widget.row?['hero'] as String?) ?? 'rafi';
  late bool _isRare = (widget.row?['is_rare'] as bool?) ?? false;
  late bool _isBday = (widget.row?['is_birthday_exclusive'] as bool?) ?? false;
  late bool _isActive = (widget.row?['is_active'] as bool?) ?? true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_hero_card_upsert',
        params: {
          'p_id': widget.row?['id'],
          'p_name': _name.text.trim(),
          'p_hero': _hero,
          'p_description': _description.text.trim(),
          'p_image_url':
              _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
          'p_is_rare': _isRare,
          'p_is_birthday_exclusive': _isBday,
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
      title: Text(isNew ? 'New hero card' : 'Edit hero card'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _hero,
                decoration: const InputDecoration(
                  labelText: 'Hero',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'rafi', child: Text('Rafi')),
                  DropdownMenuItem(value: 'ellie', child: Text('Ellie')),
                  DropdownMenuItem(value: 'gerry', child: Text('Gerry')),
                  DropdownMenuItem(value: 'zena', child: Text('Zena')),
                ],
                onChanged: (v) => setState(() => _hero = v ?? 'rafi'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageUrl,
                decoration: const InputDecoration(
                  labelText: 'Image URL (hero-cards bucket)',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rare'),
                value: _isRare,
                onChanged: (v) => setState(() => _isRare = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Birthday exclusive'),
                value: _isBday,
                onChanged: (v) => setState(() => _isBday = v),
              ),
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

final heroCardsAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('hero_card_definitions')
      .select()
      .order('hero', ascending: true)
      .order('name', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
