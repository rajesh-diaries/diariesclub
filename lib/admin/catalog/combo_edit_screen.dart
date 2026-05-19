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
import '../../core/utils/currency.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';
import 'combos_list_screen.dart' show combosAdminListProvider;
import 'fit_list_screen.dart' show fitTemplatesAdminListProvider;

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// Combo create / edit (Module 2.6). Multi-item picker pulls from
/// menu_items across both Coffee + FIT brands. Live "savings" indicator
/// computes (sum of items × quantities) − combo price.
class ComboEditScreen extends ConsumerStatefulWidget {
  final String? comboId;
  const ComboEditScreen({super.key, this.comboId});

  @override
  ConsumerState<ComboEditScreen> createState() => _ComboEditScreenState();
}

class _ComboEditScreenState extends ConsumerState<ComboEditScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _sortCtrl = TextEditingController(text: '0');

  Uint8List? _photoBytes;
  String? _existingPhotoUrl;
  bool _isActive = true;

  // selectedItems[menu_item_id] = quantity
  final Map<String, int> _selectedItems = {};

  // When set, this combo opens the FIT builder (pre-targeted to this
  // template) instead of using the fixed-items flow. The combo's price
  // covers the template's base_price_paise; selection upcharges are
  // billed on top at checkout. NULL = legacy fixed-items combo.
  String? _fitTemplateId;

  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.comboId != null;

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
      final row = await Supabase.instance.client
          .from('combos')
          .select()
          .eq('id', widget.comboId!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Combo not found.';
        });
        return;
      }
      setState(() {
        _nameCtrl.text = (row['name'] as String?) ?? '';
        _descCtrl.text = (row['description'] as String?) ?? '';
        _priceCtrl.text =
            (((row['price_paise'] as int?) ?? 0) ~/ 100).toString();
        _sortCtrl.text = (row['sort_order'] as int?)?.toString() ?? '0';
        _isActive = (row['is_active'] as bool?) ?? true;
        _existingPhotoUrl = row['cover_image_url'] as String?;
        _fitTemplateId = row['fit_template_id'] as String?;

        // Read items from inclusions JSONB. Accept both new shape
        // (menu_items: [{id, quantity}]) and legacy (menu_item_ids: [...]).
        final inc = row['inclusions'];
        if (inc is Map) {
          final items = inc['menu_items'];
          if (items is List) {
            for (final it in items) {
              if (it is Map) {
                final id = it['id'];
                final qty = (it['quantity'] as int?) ?? 1;
                if (id is String) _selectedItems[id] = qty;
              }
            }
          } else {
            final legacy = inc['menu_item_ids'];
            if (legacy is List) {
              for (final id in legacy) {
                if (id is String) _selectedItems[id] = 1;
              }
            }
          }
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
        maxWidth: 1200, maxHeight: 1200,
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
    final path = 'combos/$fileName';
    await Supabase.instance.client.storage
        .from('menu-photos')
        .uploadBinary(
          path, _photoBytes!,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg', upsert: false,
          ),
        );
    return Supabase.instance.client.storage
        .from('menu-photos').getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorText = 'Name is required.');
      return;
    }
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _errorText = 'Price must be a positive number.');
      return;
    }
    if (_selectedItems.isEmpty) {
      setState(() => _errorText = 'Pick at least one item.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final photoUrl = await _uploadPhotoIfNew();
      final inclusions = {
        'menu_items': _selectedItems.entries
            .map((e) => {'id': e.key, 'quantity': e.value})
            .toList(),
      };
      final params = {
        'p_name': _nameCtrl.text.trim(),
        'p_description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'p_price_paise': price * 100,
        'p_photo_url': photoUrl,
        'p_inclusions': inclusions,
        'p_sort_order': int.tryParse(_sortCtrl.text.trim()) ?? 0,
        'p_fit_template_id': _fitTemplateId,
      };
      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_combo_update',
          params: {
            'p_id': widget.comboId,
            'p_is_active': _isActive,
            ...params,
          },
        );
      } else {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_combo_create',
          params: {'p_venue_id': _kondapurVenueId, ...params},
        );
      }
      if (!mounted) return;
      ref.invalidate(combosAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Saved' : 'Created')),
      );
      context.go('/admin/catalog/combos');
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
    final menuAsync = ref.watch(_allMenuItemsProvider);
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: _isEditing ? 'Edit combo' : 'New combo'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
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
                              labelText: 'Combo price (₹)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
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
                    if (_isEditing) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Active'),
                        subtitle: const Text('Off = hidden from customers.'),
                        value: _isActive,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isActive = v),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Link to a FIT meal builder (optional)',
                        style: AppTextStyles.h3(context)),
                    const SizedBox(height: 4),
                    Text(
                      'Set this to turn the combo into a Play + FIT bundle. '
                      'The customer opens the FIT builder for the chosen '
                      'template, the combo price covers its base, and any '
                      'selection upcharges are added at checkout. Leave as '
                      '"None" for plain fixed-item combos.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FitTemplatePicker(
                      value: _fitTemplateId,
                      onChanged: (v) => setState(() => _fitTemplateId = v),
                    ),
                    const SizedBox(height: 24),
                    Text('Items in this combo',
                        style: AppTextStyles.h3(context)),
                    const SizedBox(height: 4),
                    Text(
                      'Pick from Coffee + FIT menus. Set quantity per item.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    menuAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (items) => _ItemPicker(
                        items: items,
                        selected: _selectedItems,
                        onChanged: (next) =>
                            setState(() {
                              _selectedItems
                                ..clear()
                                ..addAll(next);
                            }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SavingsIndicator(
                      sumPaise: _sumOfSelectedPaise(menuAsync.valueOrNull ?? const []),
                      comboPaise: (int.tryParse(_priceCtrl.text.trim()) ?? 0) * 100,
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: AppTextStyles.caption(
                          context, color: AppColors.adminRed,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AdminSecondaryButton(
                          label: 'Cancel',
                          ghost: true,
                          onPressed: _busy
                              ? null
                              : () => context.go('/admin/catalog/combos'),
                        ),
                        const SizedBox(width: 12),
                        AdminPrimaryButton(
                          label: _isEditing ? 'Save' : 'Create',
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  int _sumOfSelectedPaise(List<Map<String, dynamic>> items) {
    var total = 0;
    for (final entry in _selectedItems.entries) {
      final item = items.firstWhere(
        (i) => i['id'] == entry.key,
        orElse: () => const <String, dynamic>{},
      );
      final price = (item['price_paise'] as int?) ?? 0;
      total += price * entry.value;
    }
    return total;
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
                  image: MemoryImage(_photoBytes!), fit: BoxFit.cover,
                )
              : hasExisting
                  ? DecorationImage(
                      image: NetworkImage(_existingPhotoUrl!), fit: BoxFit.cover,
                    )
                  : null,
        ),
        child: hasNew || hasExisting
            ? null
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsRegular.image,
                        size: 36, color: AppColors.lightTextSecondary),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to add photo',
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ItemPicker extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, int> selected;
  final ValueChanged<Map<String, int>> onChanged;
  const _ItemPicker({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Group by brand.
    final byBrand = <String, List<Map<String, dynamic>>>{};
    for (final i in items) {
      final brand = (i['brand'] as String?) ?? 'other';
      byBrand.putIfAbsent(brand, () => []).add(i);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final entry in byBrand.entries) ...[
            _BrandHeader(brand: entry.key),
            for (final i in entry.value)
              _ItemRow(
                item: i,
                quantity: selected[i['id']] ?? 0,
                onChange: (q) {
                  final next = {...selected};
                  if (q <= 0) {
                    next.remove(i['id']);
                  } else {
                    next[i['id'] as String] = q;
                  }
                  onChanged(next);
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final String brand;
  const _BrandHeader({required this.brand});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.lightBackground,
      child: Row(
        children: [
          Text(
            brand.toUpperCase(),
            style: AppTextStyles.caption(
              context, color: AppColors.lightTextSecondary,
            ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final int quantity;
  final ValueChanged<int> onChange;
  const _ItemRow({
    required this.item,
    required this.quantity,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => onChange(v == true ? 1 : 0),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (item['name'] as String?) ?? '—',
                  style: AppTextStyles.body(context),
                ),
                if ((item['category'] as String?)?.isNotEmpty ?? false)
                  Text(
                    item['category'] as String,
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            Money.fromPaise((item['price_paise'] as int?) ?? 0),
            style: AppTextStyles.body(context),
          ),
          const SizedBox(width: 12),
          if (selected)
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  AdminIconButton(
                    icon: PhosphorIconsRegular.minus,
                    size: 14,
                    onPressed: quantity > 1 ? () => onChange(quantity - 1) : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Text('$quantity',
                          style: AppTextStyles.body(context)),
                    ),
                  ),
                  AdminIconButton(
                    icon: PhosphorIconsRegular.plus,
                    size: 14,
                    onPressed: () => onChange(quantity + 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SavingsIndicator extends StatelessWidget {
  final int sumPaise;
  final int comboPaise;
  const _SavingsIndicator({required this.sumPaise, required this.comboPaise});

  @override
  Widget build(BuildContext context) {
    final saves = sumPaise - comboPaise;
    final color = saves > 0
        ? AppColors.activeGreen
        : (saves < 0 ? AppColors.adminRed : AppColors.lightTextSecondary);
    final label = saves > 0
        ? 'Saves ${Money.fromPaise(saves)}'
        : (saves < 0 ? 'Combo costs MORE than items' : 'Same as à-la-carte');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            saves > 0 ? PhosphorIconsRegular.checkCircle
                      : (saves < 0 ? PhosphorIconsRegular.warning
                                   : PhosphorIconsRegular.info),
            color: color,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Sum of items: ${Money.fromPaise(sumPaise)}  ·  ',
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
                  TextSpan(
                    text: 'Combo: ${Money.fromPaise(comboPaise)}  ·  ',
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: AppTextStyles.body(context, color: color)
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// All menu_items joined to menus (for brand). Includes only active items.
final _allMenuItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('menu_items')
      .select(
        'id, name, price_paise, category, '
        'menu:menus!inner(brand)',
      )
      .order('name', ascending: true);
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final m = Map<String, dynamic>.from(r);
    final menu = m['menu'];
    if (menu is Map) m['brand'] = menu['brand'];
    out.add(m);
  }
  return out;
});

/// Dropdown of FIT meal templates with a "None" sentinel for legacy
/// fixed-item combos. Used in the combo editor to opt this combo into
/// the FIT builder flow.
class _FitTemplatePicker extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _FitTemplatePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fitTemplatesAdminListProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(
        "Couldn't load FIT templates: $e",
        style: AppTextStyles.caption(context, color: AppColors.adminRed),
      ),
      data: (templates) {
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('None — plain fixed-item combo'),
          ),
          for (final t in templates)
            DropdownMenuItem<String?>(
              value: t['id'] as String?,
              child: Text(
                '${t['name']}  ·  base ${Money.fromPaise((t['base_price_paise'] as int?) ?? 0)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ];
        return DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Linked FIT template',
            border: OutlineInputBorder(),
          ),
          items: items,
          onChanged: onChanged,
        );
      },
    );
  }
}
