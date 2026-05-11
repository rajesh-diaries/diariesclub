import 'dart:convert';

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
import '../widgets/admin_buttons.dart';
import 'packages_list_screen.dart' show packagesAdminListProvider;

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// New / edit birthday package (Module 2.7). Form pre-fills sensible
/// JSONB defaults so admin edits structured data instead of starting
/// blank. JSONB fields are edited as JSON-text textareas — visual
/// editors are a polish-pass refactor; this is the v1 admin form.
class PackageEditScreen extends ConsumerStatefulWidget {
  final String? packageId;
  const PackageEditScreen({super.key, this.packageId});

  @override
  ConsumerState<PackageEditScreen> createState() =>
      _PackageEditScreenState();
}

// JSON array of strings — these render as bullet points on the customer
// discover screen. Keep entries punchy ("1 Welcome Drink", "Min 20 guests").
const _placeholderInclusions = '''
[
  "Hall: Pearl",
  "Min 20 guests",
  "1 Welcome Drink",
  "2 Starters",
  "2 Main Course",
  "1 Dessert"
]''';

const _placeholderMenuOptions = '''
[
  {
    "category": "Cake",
    "options": [
      { "id": "vanilla", "name": "Vanilla", "upcharge_paise": 0 },
      { "id": "chocolate", "name": "Chocolate", "upcharge_paise": 0 },
      { "id": "red_velvet", "name": "Red Velvet", "upcharge_paise": 50000 }
    ]
  },
  {
    "category": "Drinks",
    "options": [
      { "id": "juice", "name": "Mixed juice", "upcharge_paise": 0 },
      { "id": "soda", "name": "Soft drinks", "upcharge_paise": 0 }
    ]
  }
]''';

const _placeholderNonFood = '''
[
  { "label": "Decoration", "detail": "Theme-based balloon arch + table centrepieces" },
  { "label": "Music", "detail": "Curated playlist via venue speakers" },
  { "label": "Photographer", "detail": "1hr coverage; soft-copies in 7 days" },
  { "label": "Return gifts", "detail": "Diaries-branded mini hero card pack per child" }
]''';

const _placeholderAvailableDays = '''
{
  "weekend": true,
  "weekday": true,
  "specific_dates": []
}''';

class _PackageEditScreenState extends ConsumerState<PackageEditScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: '0');
  final _durationCtrl = TextEditingController(text: '3');
  final _maxKidsCtrl = TextEditingController();
  final _maxAdultsCtrl = TextEditingController();
  final _galleryCtrl = TextEditingController();
  final _inclusionsCtrl = TextEditingController(text: _placeholderInclusions);
  final _menuOptsCtrl = TextEditingController(text: _placeholderMenuOptions);
  final _nonFoodCtrl = TextEditingController(text: _placeholderNonFood);
  final _availableCtrl = TextEditingController(text: _placeholderAvailableDays);
  final _sortCtrl = TextEditingController(text: '0');
  // New birthday-package fields (Slice 2 — admin tooling).
  final _hallNameCtrl = TextEditingController();
  final _minGuestsCtrl = TextEditingController();
  final _maxGuestsCtrl = TextEditingController();
  final _priceVegCtrl = TextEditingController();
  final _priceNonVegCtrl = TextEditingController();
  final _pdfUrlCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();

  String _tier = 'little_joy';
  String? _heroTheme;
  Uint8List? _photoBytes;
  String? _existingCoverUrl;
  bool _isActive = true;
  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.packageId != null;

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
    _depositCtrl.dispose();
    _durationCtrl.dispose();
    _maxKidsCtrl.dispose();
    _maxAdultsCtrl.dispose();
    _galleryCtrl.dispose();
    _inclusionsCtrl.dispose();
    _menuOptsCtrl.dispose();
    _nonFoodCtrl.dispose();
    _availableCtrl.dispose();
    _sortCtrl.dispose();
    _hallNameCtrl.dispose();
    _minGuestsCtrl.dispose();
    _maxGuestsCtrl.dispose();
    _priceVegCtrl.dispose();
    _priceNonVegCtrl.dispose();
    _pdfUrlCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('birthday_packages')
          .select()
          .eq('id', widget.packageId!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Package not found.';
        });
        return;
      }
      setState(() {
        _nameCtrl.text = (row['name'] as String?) ?? '';
        _descCtrl.text = (row['description'] as String?) ?? '';
        // Legacy flat price + deposit. Optional going forward — admin
        // can leave blank if using per-pax pricing only.
        final price = row['price_paise'] as int?;
        _priceCtrl.text = price == null ? '' : (price ~/ 100).toString();
        final deposit = row['deposit_paise'] as int?;
        _depositCtrl.text = deposit == null ? '' : (deposit ~/ 100).toString();
        _durationCtrl.text = (row['duration_hours'] as int?)?.toString() ?? '3';
        _maxKidsCtrl.text = (row['max_kids'] as int?)?.toString() ?? '';
        _maxAdultsCtrl.text = (row['max_adults'] as int?)?.toString() ?? '';
        _sortCtrl.text = (row['sort_order'] as int?)?.toString() ?? '0';
        _tier = (row['tier'] as String?) ?? 'little_joy';
        _heroTheme = row['hero_theme'] as String?;
        _existingCoverUrl = row['cover_image_url'] as String?;
        _isActive = (row['is_active'] as bool?) ?? true;
        final gallery = (row['gallery_image_urls'] as List?)?.cast<String>() ?? const [];
        _galleryCtrl.text = gallery.join('\n');
        _inclusionsCtrl.text = _pretty(row['inclusions']);
        _menuOptsCtrl.text = _pretty(row['menu_options']);
        _nonFoodCtrl.text = _pretty(row['non_food_offerings']);
        _availableCtrl.text = _pretty(row['available_days']);
        // Slice 2 fields.
        _hallNameCtrl.text = (row['hall_name'] as String?) ?? '';
        _minGuestsCtrl.text = (row['min_guests'] as int?)?.toString() ?? '';
        _maxGuestsCtrl.text = (row['max_guests'] as int?)?.toString() ?? '';
        final pVeg = row['price_per_pax_veg_paise'] as int?;
        _priceVegCtrl.text = pVeg == null ? '' : (pVeg ~/ 100).toString();
        final pNon = row['price_per_pax_non_veg_paise'] as int?;
        _priceNonVegCtrl.text = pNon == null ? '' : (pNon ~/ 100).toString();
        _pdfUrlCtrl.text = (row['pdf_url'] as String?) ?? '';
        // Experience inclusions are an array of strings; render one per
        // line so admin can add/remove without thinking about JSON.
        final exp = (row['experience_inclusions'] as List?)?.cast<String>()
            ?? const <String>[];
        _experienceCtrl.text = exp.join('\n');
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

  String _pretty(dynamic raw) {
    if (raw == null) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(raw);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000,
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
    if (_photoBytes == null) return _existingCoverUrl;
    final fileName = '${const Uuid().v4()}.jpg';
    final path = 'packages/$fileName';
    await Supabase.instance.client.storage
        .from('package-photos')
        .uploadBinary(path, _photoBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg', upsert: false,
            ));
    return Supabase.instance.client.storage
        .from('package-photos').getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorText = 'Name is required.');
      return;
    }
    // Per-pax pricing is the new model. Legacy flat price is optional.
    final priceVeg = int.tryParse(_priceVegCtrl.text.trim());
    final priceNonVeg = int.tryParse(_priceNonVegCtrl.text.trim());
    if (priceVeg == null || priceVeg <= 0 ||
        priceNonVeg == null || priceNonVeg <= 0) {
      setState(() => _errorText =
          'Per-pax veg + non-veg prices are required.');
      return;
    }
    final minG = int.tryParse(_minGuestsCtrl.text.trim());
    final maxG = int.tryParse(_maxGuestsCtrl.text.trim());
    if (minG == null || maxG == null || minG <= 0 || maxG < minG) {
      setState(() => _errorText =
          'Min/max guests are required, and max must be ≥ min.');
      return;
    }
    if (_hallNameCtrl.text.trim().isEmpty) {
      setState(() => _errorText = 'Hall name is required.');
      return;
    }
    // Legacy flat price stays optional but if present must be a positive int.
    final priceLegacy = _priceCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_priceCtrl.text.trim());
    if (priceLegacy != null && priceLegacy <= 0) {
      setState(() => _errorText = 'Legacy price (₹) must be positive.');
      return;
    }

    dynamic inclusionsJson;
    dynamic menuOptionsJson;
    dynamic nonFoodJson;
    dynamic availableJson;
    try {
      inclusionsJson = _inclusionsCtrl.text.trim().isEmpty
          ? <dynamic>[] : jsonDecode(_inclusionsCtrl.text);
      menuOptionsJson = _menuOptsCtrl.text.trim().isEmpty
          ? <dynamic>[] : jsonDecode(_menuOptsCtrl.text);
      nonFoodJson = _nonFoodCtrl.text.trim().isEmpty
          ? <dynamic>[] : jsonDecode(_nonFoodCtrl.text);
      availableJson = _availableCtrl.text.trim().isEmpty
          ? <String, dynamic>{} : jsonDecode(_availableCtrl.text);
    } catch (e) {
      setState(() => _errorText = 'Invalid JSON in one of the fields: $e');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final coverUrl = await _uploadPhotoIfNew();
      final gallery = _galleryCtrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final params = {
        'p_name': _nameCtrl.text.trim(),
        'p_tier': _tier,
        'p_description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'p_price_paise': priceLegacy == null ? null : priceLegacy * 100,
        'p_deposit_paise':
            _depositCtrl.text.trim().isEmpty
                ? null
                : (int.tryParse(_depositCtrl.text.trim()) ?? 0) * 100,
        'p_duration_hours': int.tryParse(_durationCtrl.text.trim()) ?? 3,
        'p_max_kids': int.tryParse(_maxKidsCtrl.text.trim()),
        'p_max_adults': int.tryParse(_maxAdultsCtrl.text.trim()),
        'p_cover_image_url': coverUrl,
        'p_gallery_image_urls': gallery,
        'p_inclusions': inclusionsJson,
        'p_menu_options': menuOptionsJson,
        'p_non_food_offerings': nonFoodJson,
        'p_available_days': availableJson,
        'p_hero_theme': _heroTheme,
        'p_sort_order': int.tryParse(_sortCtrl.text.trim()) ?? 0,
        // Slice 2 fields.
        'p_hall_name': _hallNameCtrl.text.trim().isEmpty
            ? null
            : _hallNameCtrl.text.trim(),
        'p_min_guests': minG,
        'p_max_guests': maxG,
        'p_price_per_pax_veg_paise': priceVeg * 100,
        'p_price_per_pax_non_veg_paise': priceNonVeg * 100,
        'p_pdf_url': _pdfUrlCtrl.text.trim().isEmpty
            ? null
            : _pdfUrlCtrl.text.trim(),
        'p_experience_inclusions': _experienceCtrl.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      };

      String? id = widget.packageId;
      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_package_update',
          params: {'p_id': id, 'p_is_active': _isActive, ...params},
        );
      } else {
        final res = await Supabase.instance.client
            .rpc<Map<String, dynamic>>(
          'admin_package_create',
          params: {'p_venue_id': _kondapurVenueId, ...params},
        );
        id = res['package_id'] as String?;
      }

      // Auto-trigger PDF regen on save.
      if (id != null) {
        try {
          await Supabase.instance.client.rpc<dynamic>(
            'admin_package_regenerate_pdf',
            params: {'p_id': id},
          );
        } catch (_) {
          // PDF regen failure shouldn't block save success.
        }
      }

      if (!mounted) return;
      ref.invalidate(packagesAdminListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          _isEditing ? 'Saved · PDF regenerating' : 'Created · PDF generating',
        )),
      );
      context.go('/admin/packages');
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
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: _isEditing ? 'Edit package' : 'New package'),
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
                        labelText: 'Name', border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description', border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _tier,
                            decoration: const InputDecoration(
                              labelText: 'Tier', border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'little_joy', child: Text('Little Joy')),
                              DropdownMenuItem(value: 'happy_tales', child: Text('Happy Tales')),
                              DropdownMenuItem(value: 'grand', child: Text('Grand')),
                              DropdownMenuItem(value: 'magical', child: Text('Magical')),
                              DropdownMenuItem(value: 'custom', child: Text('Custom')),
                            ],
                            onChanged: (v) => setState(() => _tier = v ?? 'little_joy'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _hallNameCtrl.text.isEmpty
                                ? null
                                : _hallNameCtrl.text,
                            decoration: const InputDecoration(
                              labelText: 'Hall', border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Pearl', child: Text('Pearl')),
                              DropdownMenuItem(value: 'The Grand', child: Text('The Grand')),
                            ],
                            onChanged: (v) => setState(() => _hallNameCtrl.text = v ?? ''),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numField('Per-pax Veg (₹)', _priceVegCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField('Per-pax Non-Veg (₹)', _priceNonVegCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField('Duration (hr)', _durationCtrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Per-pax · 18% GST extra. Prices customers see on the inquiry form.',
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _numField('Min guests', _minGuestsCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _numField('Max guests', _maxGuestsCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _numField('Sort order', _sortCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pdfUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Menu PDF URL (optional)',
                        hintText: 'https://...packages-poster.pdf',
                        helperText:
                            'Upload the PDF to Supabase Storage (or any '
                            'public URL) and paste it here. Customer sees a '
                            '"View full menu (PDF)" link if filled.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _experienceCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Experience inclusions',
                        hintText: '2.5 hours play time\n'
                            '3 hours hall booking\n'
                            'Food buffet',
                        helperText:
                            'One bullet per line. Shown on the package as '
                            '"EXPERIENCE" — add as many as you like.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Legacy / advanced',
                        style: AppTextStyles.caption(
                          context, color: AppColors.lightTextSecondary,
                        ).copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _numField('Flat price (₹) — optional', _priceCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField('Deposit (₹) — optional', _depositCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _heroTheme,
                            decoration: const InputDecoration(
                              labelText: 'Hero theme (legacy)',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('— None —')),
                              DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                            ],
                            onChanged: (v) => setState(() => _heroTheme = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _numField('Max kids (legacy)', _maxKidsCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _numField('Max adults (legacy)', _maxAdultsCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _galleryCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Gallery image URLs (one per line)',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _jsonField('Inclusions', _inclusionsCtrl,
                        helper:
                            'JSON array of strings — one bullet per line. '
                            'e.g. ["Hall: Pearl", "Min 20 guests", '
                            '"1 Welcome Drink"]'),
                    const SizedBox(height: 12),
                    _jsonField('Menu options', _menuOptsCtrl,
                        helper: 'JSON array of {category, options:[{id,name,upcharge_paise}]}'),
                    const SizedBox(height: 12),
                    _jsonField('Non-food offerings', _nonFoodCtrl,
                        helper: 'JSON array of {label, detail}'),
                    const SizedBox(height: 12),
                    _jsonField('Available days', _availableCtrl,
                        helper: 'JSON: {weekend, weekday, specific_dates:[]}'),
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
                              : () => context.go('/admin/packages'),
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

  Widget _numField(String label, TextEditingController ctrl) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(),
        ),
      );

  Widget _jsonField(String label, TextEditingController ctrl, {String? helper}) =>
      TextField(
        controller: ctrl,
        maxLines: 8,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _photoPicker() {
    final hasNew = _photoBytes != null;
    final hasExisting = _existingCoverUrl != null && _existingCoverUrl!.isNotEmpty;
    return InkWell(
      onTap: _busy ? null : _pickPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
          image: hasNew
              ? DecorationImage(image: MemoryImage(_photoBytes!), fit: BoxFit.cover)
              : hasExisting
                  ? DecorationImage(image: NetworkImage(_existingCoverUrl!), fit: BoxFit.cover)
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
                      'Tap to add cover photo',
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
