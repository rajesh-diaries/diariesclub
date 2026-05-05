import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_app_bar.dart';

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// Manages global FIT meal categories + their options (Module 2.5
/// commit B). Each category is an ExpansionTile; options live inside.
/// Inline dialogs for create/edit to keep the screen single-pane.
class FitCategoriesScreen extends ConsumerWidget {
  const FitCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(fitCategoriesAdminProvider);
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(
        title: 'FIT categories',
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              icon: const Icon(PhosphorIconsRegular.plus, size: 16),
              label: const Text('New category'),
              onPressed: () => _showCategoryDialog(context, ref),
            ),
          ),
        ],
      ),
      body: cats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No categories yet. Create one (e.g. Protein, Dip, Salad) to start building meal templates.',
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: rows.length,
                itemBuilder: (_, i) => _CategoryCard(
                  category: rows[i],
                ),
              ),
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final Map<String, dynamic> category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = category['id'] as String;
    final options = ref.watch(fitOptionsForCategoryProvider(id));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                (category['name'] as String?) ?? '—',
                style: AppTextStyles.h3(context),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                category['selection_type'] as String? ?? '—',
                style: AppTextStyles.caption(context, color: AppColors.navy),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit category',
              icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 16),
              onPressed: () => _showCategoryDialog(
                context, ref,
                existing: category,
              ),
            ),
            IconButton(
              tooltip: 'Delete category',
              icon: const Icon(PhosphorIconsRegular.trash,
                  size: 16, color: AppColors.adminRed),
              onPressed: () => _confirmDeleteCategory(context, ref, category),
            ),
          ],
        ),
        subtitle: Text(
          'slug: ${category['slug']} · ${category['default_required'] == true ? 'required' : 'optional'} by default',
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
        children: [
          options.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
            data: (rows) => Column(
              children: [
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No options yet.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                for (final o in rows)
                  _OptionRow(option: o, ref: ref),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(PhosphorIconsRegular.plus, size: 14),
                      label: const Text('Add option'),
                      onPressed: () => _showOptionDialog(
                        context, ref,
                        categoryId: id,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final Map<String, dynamic> option;
  final WidgetRef ref;
  const _OptionRow({required this.option, required this.ref});

  Future<void> _toggle(BuildContext context, bool to) async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_option_toggle_available',
        params: {'p_id': option['id'], 'p_available': to},
      );
      ref.invalidate(fitOptionsForCategoryProvider(option['category_id'] as String));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not toggle: $e')),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_option_delete',
        params: {'p_id': option['id']},
      );
      ref.invalidate(fitOptionsForCategoryProvider(option['category_id'] as String));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final published = (option['is_published'] as bool?) ?? true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (option['name'] as String?) ?? '—',
              style: TextStyle(
                decoration: published ? null : TextDecoration.lineThrough,
                color: published ? null : AppColors.lightTextSecondary,
              ),
            ),
          ),
          if ((option['upcharge_paise'] as int?) != null
              && (option['upcharge_paise'] as int) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '+${Money.fromPaise((option['upcharge_paise'] as int?) ?? 0)}',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.gold,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          Switch(
            value: (option['is_available'] as bool?) ?? true,
            onChanged: published ? (v) => _toggle(context, v) : null,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(PhosphorIconsRegular.pencilSimple, size: 16),
            onPressed: () => _showOptionDialog(
              context, ref,
              categoryId: option['category_id'] as String,
              existing: option,
            ),
          ),
          if (published)
            IconButton(
              tooltip: 'Hide',
              icon: const Icon(PhosphorIconsRegular.eyeSlash,
                  size: 16, color: AppColors.adminRed),
              onPressed: () => _delete(context),
            ),
        ],
      ),
    );
  }
}

Future<void> _showCategoryDialog(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) async {
  final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
  final slugCtrl = TextEditingController(text: existing?['slug'] as String? ?? '');
  final orderCtrl = TextEditingController(
    text: (existing?['display_order'] as int?)?.toString() ?? '0',
  );
  String selType = (existing?['selection_type'] as String?) ?? 'single';
  bool defaultRequired = (existing?['default_required'] as bool?) ?? true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(existing == null ? 'New category' : 'Edit category'),
      content: StatefulBuilder(
        builder: (_, setSt) => SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Protein, Dip, Salad…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slugCtrl,
                enabled: existing == null, // immutable after create
                decoration: InputDecoration(
                  labelText: 'Slug (stable id, lowercase)',
                  hintText: 'protein',
                  border: const OutlineInputBorder(),
                  helperText: existing == null
                      ? null
                      : 'Slug is immutable after create.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selType,
                decoration: const InputDecoration(
                  labelText: 'Selection type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'single', child: Text('Single (radio)')),
                  DropdownMenuItem(value: 'multi', child: Text('Multi (checkboxes)')),
                ],
                onChanged: (v) => setSt(() => selType = v ?? 'single'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Required by default'),
                subtitle: const Text(
                  'Templates can override per-link.',
                ),
                value: defaultRequired,
                onChanged: (v) => setSt(() => defaultRequired = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: orderCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Display order',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
      ],
    ),
  );

  if (ok != true || !context.mounted) return;
  try {
    if (existing == null) {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_category_create',
        params: {
          'p_venue_id': _kondapurVenueId,
          'p_name': nameCtrl.text.trim(),
          'p_slug': slugCtrl.text.trim(),
          'p_selection_type': selType,
          'p_default_required': defaultRequired,
          'p_display_order': int.tryParse(orderCtrl.text.trim()) ?? 0,
        },
      );
    } else {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_category_update',
        params: {
          'p_id': existing['id'],
          'p_name': nameCtrl.text.trim(),
          'p_selection_type': selType,
          'p_default_required': defaultRequired,
          'p_display_order': int.tryParse(orderCtrl.text.trim()) ?? 0,
        },
      );
    }
    ref.invalidate(fitCategoriesAdminProvider);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save: $e')),
    );
  }
}

Future<void> _showOptionDialog(
  BuildContext context,
  WidgetRef ref, {
  required String categoryId,
  Map<String, dynamic>? existing,
}) async {
  final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
  final upchargeCtrl = TextEditingController(
    text: ((existing?['upcharge_paise'] as int?) ?? 0) ~/ 100 == 0
        ? ''
        : (((existing?['upcharge_paise'] as int?) ?? 0) ~/ 100).toString(),
  );
  final orderCtrl = TextEditingController(
    text: (existing?['display_order'] as int?)?.toString() ?? '0',
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(existing == null ? 'New option' : 'Edit option'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Chicken, Paneer, Hummus…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: upchargeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Upcharge (₹)',
                hintText: '0 for no upcharge',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: orderCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Display order',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
      ],
    ),
  );

  if (ok != true || !context.mounted) return;
  try {
    if (existing == null) {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_option_create',
        params: {
          'p_venue_id': _kondapurVenueId,
          'p_category_id': categoryId,
          'p_name': nameCtrl.text.trim(),
          'p_upcharge_paise': (int.tryParse(upchargeCtrl.text.trim()) ?? 0) * 100,
          'p_display_order': int.tryParse(orderCtrl.text.trim()) ?? 0,
        },
      );
    } else {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_fit_option_update',
        params: {
          'p_id': existing['id'],
          'p_name': nameCtrl.text.trim(),
          'p_upcharge_paise': (int.tryParse(upchargeCtrl.text.trim()) ?? 0) * 100,
          'p_is_available': null,
          'p_is_published': null,
          'p_display_order': int.tryParse(orderCtrl.text.trim()) ?? 0,
        },
      );
    }
    ref.invalidate(fitOptionsForCategoryProvider(categoryId));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save: $e')),
    );
  }
}

Future<void> _confirmDeleteCategory(
  BuildContext context, WidgetRef ref, Map<String, dynamic> cat) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Delete category?'),
      content: Text(
        'Permanently deletes "${cat['name']}". Refused if any template is using it — '
        'detach from templates first.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await Supabase.instance.client.rpc<dynamic>(
      'admin_fit_category_delete',
      params: {'p_id': cat['id']},
    );
    ref.invalidate(fitCategoriesAdminProvider);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
        e.toString().contains('category_in_use_by_templates')
            ? 'Category in use by templates — detach first.'
            : 'Could not delete: $e',
      )),
    );
  }
}

final fitCategoriesAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('fit_meal_categories')
      .select()
      .eq('venue_id', _kondapurVenueId)
      .order('display_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});

final fitOptionsForCategoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, categoryId) async {
  final rows = await Supabase.instance.client
      .from('fit_meal_options')
      .select()
      .eq('category_id', categoryId)
      .order('display_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
