import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../utils/admin_image_picker.dart';
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

  // Optional bundled play session. When set, the customer's à la carte
  // sum used for the home-strip "Save ₹X" badge picks up the venue's
  // 1hr / 2hr session price. Stored under inclusions.session_minutes.
  // Allowed: null (no session) | 60 | 120.
  int? _sessionMinutes;

  bool _busy = false;
  bool _loading = true;
  bool _photoLoading = false;
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
          _sessionMinutes = inc['session_minutes'] as int?;
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
    if (_busy || _photoLoading) return;
    setState(() {
      _photoLoading = true;
      _errorText = null;
    });
    try {
      final compressed = await pickAndCompressImage(maxDimension: 1024);
      if (compressed == null || !mounted) return;
      setState(() => _photoBytes = compressed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't load image: $e");
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  Future<String?> _uploadPhotoIfNew() async {
    if (_photoBytes == null) return _existingPhotoUrl;
    return uploadImageBytes(
      bytes: _photoBytes!,
      bucket: 'menu-photos',
      folder: 'combos',
      timeoutSeconds: 30,
    );
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
    // A combo must include SOMETHING — at minimum a session, a FIT
    // template, or a list of menu items. Allow any combination of the
    // three, but at least one must be set.
    if (_selectedItems.isEmpty &&
        _fitTemplateId == null &&
        _sessionMinutes == null) {
      setState(() => _errorText =
          'Pick at least one item, a FIT template, or a bundled session.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final photoUrl = await _uploadPhotoIfNew();
      final inclusions = <String, dynamic>{
        'menu_items': _selectedItems.entries
            .map((e) => {'id': e.key, 'quantity': e.value})
            .toList(),
        if (_sessionMinutes != null) 'session_minutes': _sessionMinutes,
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
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText =
            'Photo upload timed out. Please check your network and try again.';
      });
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
    final fitAsync = ref.watch(fitTemplatesAdminListProvider);
    final configAsync = ref.watch(_venueConfigProvider);

    final items = menuAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final templates = fitAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final config = configAsync.valueOrNull;

    final sumPaise = _sumOfSelectedPaise(items) +
        _fitBasePaise(templates) +
        _sessionPaise(config);
    final breakdown = _breakdownLabel(items, templates, config);

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
                      onChanged: (v) => setState(() {
                        _fitTemplateId = v;
                        // FIT template just took over the meal side —
                        // any FIT items previously picked here become
                        // double-billing. Drop them so the cart doesn't
                        // charge the customer twice for a salad.
                        if (v != null) {
                          _selectedItems.removeWhere((id, _) {
                            final item = menuAsync.valueOrNull?.firstWhere(
                              (m) => m['id'] == id,
                              orElse: () => const <String, dynamic>{},
                            );
                            return (item?['brand'] as String?) == 'fit';
                          });
                        }
                      }),
                    ),
                    const SizedBox(height: 24),
                    Text('Bundled play session (optional)',
                        style: AppTextStyles.h3(context)),
                    const SizedBox(height: 4),
                    Text(
                      'Pick a session length when the combo name starts with '
                      '"Play +". The customer\'s à la carte total adds the '
                      'venue\'s 1hr or 2hr price so the home-strip "Save ₹X" '
                      'badge reflects the real discount.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: _sessionMinutes,
                      decoration: const InputDecoration(
                        labelText: 'Bundled session',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('None')),
                        DropdownMenuItem(value: 60, child: Text('1 hour')),
                        DropdownMenuItem(value: 120, child: Text('2 hours')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _sessionMinutes = v),
                    ),
                    const SizedBox(height: 24),
                    Text('Items in this combo',
                        style: AppTextStyles.h3(context)),
                    const SizedBox(height: 4),
                    Text(
                      _fitTemplateId != null
                          ? 'A FIT template is linked — only Coffee / non-FIT '
                              'items can be added on top to avoid double-billing.'
                          : 'Pick from Coffee + FIT menus. Set quantity per item.',
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
                        items: _fitTemplateId == null
                            ? items
                            : items
                                .where((m) =>
                                    (m['brand'] as String?) != 'fit')
                                .toList(),
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
                      sumPaise: sumPaise,
                      comboPaise: (int.tryParse(_priceCtrl.text.trim()) ?? 0) * 100,
                      breakdown: breakdown,
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
      // When a FIT template is linked, its base price already covers the
      // meal side — don't double-count any FIT items that might still be
      // lingering in the selection.
      if (_fitTemplateId != null &&
          (item['brand'] as String?) == 'fit') {
        continue;
      }
      final price = (item['price_paise'] as int?) ?? 0;
      total += price * entry.value;
    }
    return total;
  }

  int _fitBasePaise(List<Map<String, dynamic>> templates) {
    if (_fitTemplateId == null) return 0;
    final tpl = templates.firstWhere(
      (t) => t['id'] == _fitTemplateId,
      orElse: () => const <String, dynamic>{},
    );
    return (tpl['base_price_paise'] as int?) ?? 0;
  }

  int _sessionPaise(Map<String, dynamic>? config) {
    if (_sessionMinutes == null || config == null) return 0;
    final key = _sessionMinutes == 120
        ? 'session_2hr_price_paise'
        : 'session_1hr_price_paise';
    return (config[key] as int?) ?? 0;
  }

  String _breakdownLabel(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> templates,
    Map<String, dynamic>? config,
  ) {
    final parts = <String>[];
    final itemSum = _sumOfSelectedPaise(items);
    if (itemSum > 0) parts.add('items ${Money.fromPaise(itemSum)}');
    final fitSum = _fitBasePaise(templates);
    if (fitSum > 0) parts.add('FIT base ${Money.fromPaise(fitSum)}');
    final sessionSum = _sessionPaise(config);
    if (sessionSum > 0) parts.add('session ${Money.fromPaise(sessionSum)}');
    if (parts.isEmpty) return 'Nothing selected yet';
    return parts.join('  ·  ');
  }

  Widget _photoPicker() {
    final hasNew = _photoBytes != null;
    final hasExisting = _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;
    return InkWell(
      onTap: (_busy || _photoLoading) ? null : _pickPhoto,
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
        child: _photoLoading
            ? const Center(child: CircularProgressIndicator())
            : hasNew || hasExisting
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
  final String breakdown;
  const _SavingsIndicator({
    required this.sumPaise,
    required this.comboPaise,
    required this.breakdown,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'À la carte total: ${Money.fromPaise(sumPaise)}  ·  ',
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
                const SizedBox(height: 2),
                Text(
                  breakdown,
                  style: AppTextStyles.caption(
                    context, color: AppColors.lightTextSecondary,
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

/// Venue pricing config for the single Kondapur venue. Used to put a real
/// session price into the combo savings math when a bundled play session is
/// selected.
final _venueConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final row = await Supabase.instance.client
      .from('venue_config')
      .select('session_1hr_price_paise, session_2hr_price_paise')
      .eq('venue_id', _kondapurVenueId)
      .maybeSingle();
  return row == null ? null : Map<String, dynamic>.from(row);
});

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
