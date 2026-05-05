import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import 'fit_categories_screen.dart' show fitCategoriesAdminProvider;
import 'fit_list_screen.dart' show fitTemplatesAdminListProvider;

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// Create / edit FIT meal template. Two-section form:
///   1. Template details (name, photo, base price, etc.)
///   2. Linked categories (which option groups this template offers)
///      with per-link required-toggle + selection-type override.
class FitTemplateEditScreen extends ConsumerStatefulWidget {
  final String? templateId;
  const FitTemplateEditScreen({super.key, this.templateId});

  @override
  ConsumerState<FitTemplateEditScreen> createState() =>
      _FitTemplateEditScreenState();
}

class _FitTemplateEditScreenState extends ConsumerState<FitTemplateEditScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _sortCtrl = TextEditingController(text: '0');

  Uint8List? _photoBytes;
  String? _existingPhotoUrl;
  bool _isPublished = true;
  bool _isAvailable = true;
  bool _isSubscribable = false;

  // Linked categories: map category_id → {is_required, selection_type_override, display_order}.
  Map<String, _LinkSpec> _links = {};

  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final tpl = await Supabase.instance.client
          .from('fit_meal_templates')
          .select()
          .eq('id', widget.templateId!)
          .maybeSingle();
      if (!mounted || tpl == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorText = 'Template not found.';
          });
        }
        return;
      }
      final links = await Supabase.instance.client
          .from('fit_meal_template_categories')
          .select()
          .eq('template_id', widget.templateId!)
          .order('display_order', ascending: true);

      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (tpl['name'] as String?) ?? '';
        _descCtrl.text = (tpl['description'] as String?) ?? '';
        _priceCtrl.text =
            (((tpl['base_price_paise'] as int?) ?? 0) ~/ 100).toString();
        _sortCtrl.text = (tpl['sort_order'] as int?)?.toString() ?? '0';
        _isPublished = (tpl['is_published'] as bool?) ?? true;
        _isAvailable = (tpl['is_available'] as bool?) ?? true;
        _isSubscribable = (tpl['is_subscribable'] as bool?) ?? false;
        _existingPhotoUrl = tpl['photo_url'] as String?;
        for (final l in links) {
          final cid = l['category_id'] as String;
          _links[cid] = _LinkSpec(
            isRequired: (l['is_required'] as bool?) ?? true,
            selectionTypeOverride: l['selection_type_override'] as String?,
            displayOrder: (l['display_order'] as int?) ?? 0,
          );
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = "Couldn't load: $e";
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = raw);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't load that image.");
    }
  }

  Future<String?> _uploadPhotoIfNew() async {
    if (_photoBytes == null) return _existingPhotoUrl;
    final fileName = '${const Uuid().v4()}.jpg';
    final path = 'fit/$fileName';
    await Supabase.instance.client.storage
        .from('menu-photos')
        .uploadBinary(
          path,
          _photoBytes!,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return Supabase.instance.client.storage
        .from('menu-photos')
        .getPublicUrl(path);
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Name is required.';
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) return 'Base price must be a non-negative number.';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });

    String? templateId = widget.templateId;
    try {
      final photoUrl = await _uploadPhotoIfNew();
      final basePricePaise = (int.parse(_priceCtrl.text.trim())) * 100;
      final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;

      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_fit_template_update',
          params: {
            'p_id': widget.templateId,
            'p_name': _nameCtrl.text.trim(),
            'p_description':
                _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            'p_base_price_paise': basePricePaise,
            'p_photo_url': photoUrl,
            'p_is_subscribable': _isSubscribable,
            'p_subscription_meta': null,
            'p_is_published': _isPublished,
            'p_is_available': _isAvailable,
            'p_sort_order': sortOrder,
          },
        );
      } else {
        final res = await Supabase.instance.client.rpc<Map<String, dynamic>>(
          'admin_fit_template_create',
          params: {
            'p_venue_id': _kondapurVenueId,
            'p_name': _nameCtrl.text.trim(),
            'p_description':
                _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            'p_base_price_paise': basePricePaise,
            'p_photo_url': photoUrl,
            'p_is_subscribable': _isSubscribable,
            'p_subscription_meta': null,
            'p_sort_order': sortOrder,
          },
        );
        templateId = res['template_id'] as String?;
      }

      // Sync links: re-link every entry in _links; unlink any that were
      // present at load and got removed.
      if (templateId != null) {
        for (final entry in _links.entries) {
          await Supabase.instance.client.rpc<dynamic>(
            'admin_fit_template_link_category',
            params: {
              'p_template_id': templateId,
              'p_category_id': entry.key,
              'p_is_required': entry.value.isRequired,
              'p_selection_type_override': entry.value.selectionTypeOverride,
              'p_display_order': entry.value.displayOrder,
            },
          );
        }
        // For edits: prune links that the user removed.
        if (_isEditing) {
          final current = await Supabase.instance.client
              .from('fit_meal_template_categories')
              .select('category_id')
              .eq('template_id', templateId);
          for (final row in current) {
            final cid = row['category_id'] as String;
            if (!_links.containsKey(cid)) {
              await Supabase.instance.client.rpc<dynamic>(
                'admin_fit_template_unlink_category',
                params: {
                  'p_template_id': templateId,
                  'p_category_id': cid,
                },
              );
            }
          }
        }
      }

      if (!mounted) return;
      ref.invalidate(fitTemplatesAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Saved' : 'Created')),
      );
      context.go('/admin/catalog/fit');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('not_admin')
            ? 'You are not authorised.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(fitCategoriesAdminProvider);
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: _isEditing ? 'Edit template' : 'New template'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _photoPicker(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Base price (₹)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _sortCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Sort order',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Subscribable (future)'),
                      subtitle: const Text(
                        'Reserved for the upcoming weekly-delivery flow.',
                      ),
                      value: _isSubscribable,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _isSubscribable = v),
                    ),
                    if (_isEditing) ...[
                      SwitchListTile(
                        title: const Text('Available'),
                        subtitle: const Text('Off = sold out for the day.'),
                        value: _isAvailable,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isAvailable = v),
                      ),
                      SwitchListTile(
                        title: const Text('Published'),
                        subtitle: const Text('Off = hidden entirely.'),
                        value: _isPublished,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isPublished = v),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Linked categories', style: AppTextStyles.h3(context)),
                    const SizedBox(height: 8),
                    Text(
                      'Pick which option groups customers see when building this meal. Override required and selection type per template if you need to.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    cats.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (rows) => _LinksEditor(
                        categories: rows,
                        links: _links,
                        onChanged: (next) => setState(() => _links = next),
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.adminRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.go('/admin/catalog/fit'),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Text(_isEditing ? 'Save' : 'Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _photoPicker() {
    final hasNew = _photoBytes != null;
    final hasExisting = _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;
    return InkWell(
      onTap: _busy ? null : _pickPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
          image: hasNew
              ? DecorationImage(
                  image: MemoryImage(_photoBytes!),
                  fit: BoxFit.cover,
                )
              : hasExisting
                  ? DecorationImage(
                      image: NetworkImage(_existingPhotoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
        ),
        child: hasNew || hasExisting
            ? null
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      PhosphorIconsRegular.image,
                      size: 36,
                      color: AppColors.lightTextSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to add photo',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LinkSpec {
  final bool isRequired;
  final String? selectionTypeOverride;
  final int displayOrder;
  const _LinkSpec({
    required this.isRequired,
    required this.selectionTypeOverride,
    required this.displayOrder,
  });
  _LinkSpec copyWith({
    bool? isRequired,
    String? selectionTypeOverride,
    bool clearOverride = false,
    int? displayOrder,
  }) =>
      _LinkSpec(
        isRequired: isRequired ?? this.isRequired,
        selectionTypeOverride: clearOverride
            ? null
            : (selectionTypeOverride ?? this.selectionTypeOverride),
        displayOrder: displayOrder ?? this.displayOrder,
      );
}

class _LinksEditor extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final Map<String, _LinkSpec> links;
  final ValueChanged<Map<String, _LinkSpec>> onChanged;
  const _LinksEditor({
    required this.categories,
    required this.links,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final linked = categories.where((c) => links.containsKey(c['id'])).toList();
    linked.sort((a, b) {
      final la = links[a['id']]!.displayOrder;
      final lb = links[b['id']]!.displayOrder;
      return la.compareTo(lb);
    });
    final unlinked =
        categories.where((c) => !links.containsKey(c['id'])).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (linked.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No categories linked yet. Add at least one for customers to build a meal.',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
          for (final c in linked)
            _LinkRow(
              category: c,
              spec: links[c['id']]!,
              onUpdate: (s) {
                final next = {...links, c['id'] as String: s};
                onChanged(next);
              },
              onRemove: () {
                final next = {...links}..remove(c['id']);
                onChanged(next);
              },
            ),
          if (unlinked.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in unlinked)
                    ActionChip(
                      avatar: const Icon(PhosphorIconsRegular.plus, size: 14),
                      label: Text((c['name'] as String?) ?? ''),
                      onPressed: () {
                        final next = {
                          ...links,
                          c['id'] as String: _LinkSpec(
                            isRequired: (c['default_required'] as bool?) ?? true,
                            selectionTypeOverride: null,
                            displayOrder: links.length * 10,
                          ),
                        };
                        onChanged(next);
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final Map<String, dynamic> category;
  final _LinkSpec spec;
  final ValueChanged<_LinkSpec> onUpdate;
  final VoidCallback onRemove;
  const _LinkRow({
    required this.category,
    required this.spec,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (category['name'] as String?) ?? '—',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Required toggle
          Row(
            children: [
              Text('Required',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  )),
              const SizedBox(width: 4),
              Checkbox(
                value: spec.isRequired,
                onChanged: (v) => onUpdate(spec.copyWith(isRequired: v ?? true)),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Selection type override
          DropdownButton<String?>(
            value: spec.selectionTypeOverride,
            hint: Text(
              category['selection_type'] as String? ?? '—',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('default')),
              DropdownMenuItem(value: 'single', child: Text('single')),
              DropdownMenuItem(value: 'multi', child: Text('multi')),
            ],
            onChanged: (v) => onUpdate(
              v == null
                  ? spec.copyWith(clearOverride: true)
                  : spec.copyWith(selectionTypeOverride: v),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(PhosphorIconsRegular.x,
                size: 16, color: AppColors.adminRed),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
