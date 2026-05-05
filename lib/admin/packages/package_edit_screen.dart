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

const _placeholderInclusions = '''
{
  "session_minutes": 120,
  "venue_setup": "Themed decor + party host",
  "food_for_kids": "Pizza, fries, juice",
  "food_for_adults": "Tea/coffee + snacks",
  "cake": "1kg, theme-based"
}''';

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
  final _durationCtrl = TextEditingController(text: '2');
  final _maxKidsCtrl = TextEditingController(text: '15');
  final _maxAdultsCtrl = TextEditingController(text: '10');
  final _galleryCtrl = TextEditingController();
  final _inclusionsCtrl = TextEditingController(text: _placeholderInclusions);
  final _menuOptsCtrl = TextEditingController(text: _placeholderMenuOptions);
  final _nonFoodCtrl = TextEditingController(text: _placeholderNonFood);
  final _availableCtrl = TextEditingController(text: _placeholderAvailableDays);
  final _sortCtrl = TextEditingController(text: '0');

  String _tier = 'basic';
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
        _priceCtrl.text =
            (((row['price_paise'] as int?) ?? 0) ~/ 100).toString();
        _depositCtrl.text =
            (((row['deposit_paise'] as int?) ?? 0) ~/ 100).toString();
        _durationCtrl.text = (row['duration_hours'] as int?)?.toString() ?? '2';
        _maxKidsCtrl.text = (row['max_kids'] as int?)?.toString() ?? '15';
        _maxAdultsCtrl.text = (row['max_adults'] as int?)?.toString() ?? '10';
        _sortCtrl.text = (row['sort_order'] as int?)?.toString() ?? '0';
        _tier = (row['tier'] as String?) ?? 'basic';
        _heroTheme = row['hero_theme'] as String?;
        _existingCoverUrl = row['cover_image_url'] as String?;
        _isActive = (row['is_active'] as bool?) ?? true;
        final gallery = (row['gallery_image_urls'] as List?)?.cast<String>() ?? const [];
        _galleryCtrl.text = gallery.join('\n');
        _inclusionsCtrl.text = _pretty(row['inclusions']);
        _menuOptsCtrl.text = _pretty(row['menu_options']);
        _nonFoodCtrl.text = _pretty(row['non_food_offerings']);
        _availableCtrl.text = _pretty(row['available_days']);
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
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      setState(() => _errorText = 'Price must be a positive number.');
      return;
    }

    dynamic inclusionsJson;
    dynamic menuOptionsJson;
    dynamic nonFoodJson;
    dynamic availableJson;
    try {
      inclusionsJson = _inclusionsCtrl.text.trim().isEmpty
          ? <String, dynamic>{} : jsonDecode(_inclusionsCtrl.text);
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
        'p_price_paise': price * 100,
        'p_deposit_paise': (int.tryParse(_depositCtrl.text.trim()) ?? 0) * 100,
        'p_duration_hours': int.tryParse(_durationCtrl.text.trim()) ?? 2,
        'p_max_kids': int.tryParse(_maxKidsCtrl.text.trim()) ?? 15,
        'p_max_adults': int.tryParse(_maxAdultsCtrl.text.trim()) ?? 10,
        'p_cover_image_url': coverUrl,
        'p_gallery_image_urls': gallery,
        'p_inclusions': inclusionsJson,
        'p_menu_options': menuOptionsJson,
        'p_non_food_offerings': nonFoodJson,
        'p_available_days': availableJson,
        'p_hero_theme': _heroTheme,
        'p_sort_order': int.tryParse(_sortCtrl.text.trim()) ?? 0,
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
                              DropdownMenuItem(value: 'basic', child: Text('Basic')),
                              DropdownMenuItem(value: 'hero_adventure', child: Text('Hero Adventure')),
                              DropdownMenuItem(value: 'legendary', child: Text('Legendary')),
                              DropdownMenuItem(value: 'custom', child: Text('Custom')),
                            ],
                            onChanged: (v) => setState(() => _tier = v ?? 'basic'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _heroTheme,
                            decoration: const InputDecoration(
                              labelText: 'Hero theme (optional)',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('— None —')),
                              DropdownMenuItem(value: 'rafi', child: Text('Rafi')),
                              DropdownMenuItem(value: 'ellie', child: Text('Ellie')),
                              DropdownMenuItem(value: 'gerry', child: Text('Gerry')),
                              DropdownMenuItem(value: 'zena', child: Text('Zena')),
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
                        Expanded(
                          child: _numField('Price (₹)', _priceCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField('Deposit (₹)', _depositCtrl),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _numField('Duration (hr)', _durationCtrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _numField('Max kids', _maxKidsCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _numField('Max adults', _maxAdultsCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _numField('Sort order', _sortCtrl)),
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
                        helper: 'JSON object: e.g. {"session_minutes":120,"cake":"1kg theme-based"}'),
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
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.go('/admin/packages'),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
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
