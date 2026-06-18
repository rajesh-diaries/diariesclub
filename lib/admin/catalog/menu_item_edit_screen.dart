import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/admin_catalog_providers.dart';
import '../utils/admin_image_picker.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';
import '_menu_items_view.dart' show menuItemsByBrandProvider;

/// Coffee/FIT menu item create/edit. Route patterns:
///   /admin/catalog/coffee/new?menu_id=<uuid>     — create
///   /admin/catalog/coffee/:id/edit               — edit
///
/// Photo upload uses FilePicker (web-safe) and writes to the
/// menu-photos bucket via the admin's authenticated session.
class MenuItemEditScreen extends ConsumerStatefulWidget {
  final String? itemId;
  final String? menuId; // required when itemId is null
  const MenuItemEditScreen({super.key, this.itemId, this.menuId});

  @override
  ConsumerState<MenuItemEditScreen> createState() => _MenuItemEditScreenState();
}

class _MenuItemEditScreenState extends ConsumerState<MenuItemEditScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();
  final _offerPriceCtrl = TextEditingController();
  final _offerLabelCtrl = TextEditingController();
  final _prepTimeCtrl = TextEditingController();
  final _newTagCtrl = TextEditingController();
  final _newSymbolCtrl = TextEditingController();

  bool _isAvailable = true;
  bool _isPublished = true;
  Uint8List? _photoBytes;
  String? _existingPhotoUrl;
  String? _menuId;
  String? _selectedCategory;
  String? _dietaryType;
  final _selectedTags = <String>{};
  final _selectedSymbols = <String>{};
  bool _busy = false;
  bool _loading = true;
  bool _photoLoading = false;
  String? _errorText;

  bool get _isEditing => widget.itemId != null;

  static const _tagOptions = [
    'Vegetarian',
    'Vegan',
    'Gluten-free',
    'Spicy',
    'Healthy',
    'Bestseller',
    'New',
  ];

  static const _symbolOptions = [
    'chilli',
    'leaf',
    'star',
    'flame',
    'heart',
    'timer',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      _menuId = widget.menuId;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _newCategoryCtrl.dispose();
    _offerPriceCtrl.dispose();
    _offerLabelCtrl.dispose();
    _prepTimeCtrl.dispose();
    _newTagCtrl.dispose();
    _newSymbolCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('menu_items')
          .select()
          .eq('id', widget.itemId!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Item not found.';
        });
        return;
      }
      setState(() {
        _nameCtrl.text = (row['name'] as String?) ?? '';
        _descCtrl.text = (row['description'] as String?) ?? '';
        _priceCtrl.text = _rupeesFromPaise(row['price_paise'] as int?);
        _selectedCategory = (row['category'] as String?) ?? '';
        if (_selectedCategory?.isEmpty ?? true) _selectedCategory = null;
        _dietaryType = row['dietary_type'] as String?;
        _selectedTags.clear();
        _selectedTags.addAll(_listOfStrings(row['tags']));
        _selectedSymbols.clear();
        _selectedSymbols.addAll(_listOfStrings(row['symbols']));
        _offerPriceCtrl.text = _rupeesFromPaise(
          row['offer_price_paise'] as int?,
        );
        _offerLabelCtrl.text = (row['offer_label'] as String?) ?? '';
        _prepTimeCtrl.text = (row['prep_time_minutes']?.toString()) ?? '';
        _isAvailable = (row['is_available'] as bool?) ?? true;
        _isPublished = (row['is_published'] as bool?) ?? true;
        _existingPhotoUrl = row['image_url'] as String?;
        _menuId = row['menu_id'] as String?;
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

  String _rupeesFromPaise(int? paise) {
    if (paise == null || paise == 0) return '';
    return (paise / 100).toStringAsFixed(2);
  }

  List<String> _listOfStrings(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.whereType<String>().toList();
    return const [];
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
    } catch (e, st) {
      debugPrint('Photo pick failed: $e\n$st');
      if (!mounted) return;
      setState(() => _errorText = 'Could not load image: $e');
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  void _removePhoto() {
    if (_busy) return;
    setState(() {
      _photoBytes = null;
      _existingPhotoUrl = null;
    });
  }

  Future<String?> _uploadPhotoIfNew() async {
    if (_photoBytes == null) return _existingPhotoUrl;
    return uploadImageBytes(
      bytes: _photoBytes!,
      bucket: 'menu-photos',
      folder: 'menu',
      timeoutSeconds: 30,
    );
  }

  int? _parseRupeesToPaise(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Name is required.';
    final price = _parseRupeesToPaise(_priceCtrl.text);
    if (price == null || price <= 0) return 'Price must be a positive number.';
    if (!_isEditing && (_menuId == null || _menuId!.isEmpty)) {
      return 'Menu missing — go back to the list and try again.';
    }
    final offerPrice = _parseRupeesToPaise(_offerPriceCtrl.text);
    if (offerPrice != null) {
      if (offerPrice <= 0) return 'Offer price must be greater than 0.';
      if (offerPrice >= price) {
        return 'Offer price must be less than the regular price.';
      }
    }
    final prepTime = int.tryParse(_prepTimeCtrl.text.trim());
    if (_prepTimeCtrl.text.trim().isNotEmpty &&
        (prepTime == null || prepTime < 0)) {
      return 'Prep time must be a non-negative integer.';
    }
    return null;
  }

  String _userFacingError(PostgrestException e) {
    return switch (e.code) {
      'not_admin' => 'You are not authorised.',
      'invalid_price' => 'Price must be greater than 0.',
      _ => e.message,
    };
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
    try {
      const rpcTimeout = Duration(seconds: 20);
      const uploadTimeout = Duration(seconds: 60);

      final photoUrl = await _uploadPhotoIfNew().timeout(uploadTimeout);
      final pricePaise = _parseRupeesToPaise(_priceCtrl.text)!;
      final offerPricePaise = _parseRupeesToPaise(_offerPriceCtrl.text);
      final prepTime = int.tryParse(_prepTimeCtrl.text.trim());
      final category = _selectedCategory?.trim().isEmpty ?? true
          ? null
          : _selectedCategory!.trim();
      final newCategory = _newCategoryCtrl.text.trim();
      // If a new category is typed, it takes precedence over the dropdown.
      final effectiveCategory = newCategory.isNotEmpty ? newCategory : category;
      final tags = _selectedTags.toList();
      final symbols = _selectedSymbols.toList();
      final offerLabel = _offerLabelCtrl.text.trim().isEmpty
          ? null
          : _offerLabelCtrl.text.trim();

      if (_isEditing) {
        await Supabase.instance.client
            .rpc<dynamic>(
              'admin_menu_item_update',
              params: {
                'p_id': widget.itemId,
                'p_name': _nameCtrl.text.trim(),
                'p_description': _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                'p_price_paise': pricePaise,
                'p_category': effectiveCategory,
                'p_image_url': photoUrl,
                'p_is_available': _isAvailable,
                'p_is_published': _isPublished,
                'p_tags': tags,
                'p_symbols': symbols,
                'p_offer_price_paise': offerPricePaise,
                'p_offer_label': offerLabel,
                'p_prep_time_minutes': prepTime,
                'p_dietary_type': _dietaryType,
              },
            )
            .timeout(rpcTimeout);
      } else {
        await Supabase.instance.client
            .rpc<dynamic>(
              'admin_menu_item_create',
              params: {
                'p_menu_id': _menuId,
                'p_name': _nameCtrl.text.trim(),
                'p_description': _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                'p_price_paise': pricePaise,
                'p_category': effectiveCategory,
                'p_image_url': photoUrl,
                'p_sort_order': null, // auto-append
                'p_tags': tags,
                'p_symbols': symbols,
                'p_offer_price_paise': offerPricePaise,
                'p_offer_label': offerLabel,
                'p_prep_time_minutes': prepTime,
                'p_dietary_type': _dietaryType,
              },
            )
            .timeout(rpcTimeout);
      }
      if (!mounted) return;
      ref.invalidate(menuItemsByBrandProvider('coffee'));
      ref.invalidate(menuItemsByBrandProvider('fit'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Item updated' : 'Item created'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy,
        ),
      );
      context.go('/admin/catalog/coffee');
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText =
            'Save timed out. Please check your network and try again.';
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _userFacingError(e);
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
      appBar: AdminAppBar(title: _isEditing ? 'Edit item' : 'New item'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Photo'),
                            const SizedBox(height: 12),
                            _photoPicker(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Basic details'),
                            const SizedBox(height: 16),
                            _TextField(
                              controller: _nameCtrl,
                              label: 'Name',
                              hint: 'e.g. Chilli Paneer',
                              enabled: !_busy,
                            ),
                            const SizedBox(height: 16),
                            _TextField(
                              controller: _descCtrl,
                              label: 'Description',
                              hint: 'Optional — shown on the customer menu',
                              maxLines: 3,
                              enabled: !_busy,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Pricing & category'),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _TextField(
                                    controller: _priceCtrl,
                                    label: 'Price (₹)',
                                    hint: 'e.g. 120.00',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}'),
                                      ),
                                    ],
                                    enabled: !_busy,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _OfferPriceField(
                                    controller: _offerPriceCtrl,
                                    enabled: !_busy,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _TextField(
                              controller: _offerLabelCtrl,
                              label: 'Offer label',
                              hint: 'Optional — e.g. Summer Special',
                              enabled: !_busy,
                            ),
                            const SizedBox(height: 16),
                            _CategoryField(
                              menuId: _menuId,
                              selectedCategory: _selectedCategory,
                              newCategoryController: _newCategoryCtrl,
                              enabled: !_busy,
                              onCategorySelected: (category) =>
                                  setState(() => _selectedCategory = category),
                            ),
                            const SizedBox(height: 16),
                            _DietaryTypeField(
                              value: _dietaryType,
                              enabled: !_busy,
                              onChanged: (value) =>
                                  setState(() => _dietaryType = value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Tags & symbols'),
                            const SizedBox(height: 12),
                            _EditableChipGroup(
                              label: 'Tags',
                              suggestions: _tagOptions,
                              selected: _selectedTags,
                              enabled: !_busy,
                              controller: _newTagCtrl,
                              onAdd: (tag) => setState(() {
                                _selectedTags.add(tag);
                                _newTagCtrl.clear();
                              }),
                              onRemove: (tag) =>
                                  setState(() => _selectedTags.remove(tag)),
                            ),
                            const SizedBox(height: 16),
                            _EditableChipGroup(
                              label: 'Symbols',
                              suggestions: _symbolOptions,
                              selected: _selectedSymbols,
                              enabled: !_busy,
                              controller: _newSymbolCtrl,
                              iconFor: _symbolToIcon,
                              onAdd: (symbol) => setState(() {
                                _selectedSymbols.add(symbol);
                                _newSymbolCtrl.clear();
                              }),
                              onRemove: (symbol) =>
                                  setState(() => _selectedSymbols.remove(symbol)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Kitchen'),
                            const SizedBox(height: 16),
                            _TextField(
                              controller: _prepTimeCtrl,
                              label: 'Prep time (minutes)',
                              hint: 'Optional — e.g. 10',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              enabled: !_busy,
                            ),
                          ],
                        ),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 16),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle('Visibility'),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: const Row(
                                  children: [
                                    Icon(
                                      PhosphorIconsRegular.checkCircle,
                                      color: AppColors.navy,
                                      size: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Available',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: const Text(
                                  'Off = sold out for the day; customers see it but cannot order.',
                                ),
                                value: _isAvailable,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _isAvailable = v),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: const Row(
                                  children: [
                                    Icon(
                                      PhosphorIconsRegular.eye,
                                      color: AppColors.navy,
                                      size: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Published',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: const Text(
                                  'Off = hidden from the menu entirely.',
                                ),
                                value: _isPublished,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _isPublished = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_errorText != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.adminRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.adminRed.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                PhosphorIconsRegular.warningCircle,
                                color: AppColors.adminRed,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorText!,
                                  style: AppTextStyles.body(
                                    context,
                                    color: AppColors.adminRed,
                                  ),
                                ),
                              ),
                            ],
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
                                : () => context.go('/admin/catalog/coffee'),
                          ),
                          const SizedBox(width: 12),
                          AdminPrimaryButton(
                            label: _isEditing ? 'Save changes' : 'Create item',
                            busy: _busy,
                            onPressed: _busy ? null : _submit,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: AppTextStyles.bodyLarge(
        context,
      ).copyWith(fontWeight: FontWeight.w700, color: AppColors.navy),
    );
  }

  Widget _photoPicker() {
    final hasNew = _photoBytes != null;
    final hasExisting =
        _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;

    Widget imageContent;
    if (hasNew) {
      imageContent = Image.memory(
        _photoBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (hasExisting) {
      imageContent = Image.network(
        _existingPhotoUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _photoPlaceholder(),
      );
    } else {
      imageContent = _photoPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            height: 220,
            width: double.infinity,
            color: AppColors.lightSurface,
            child: imageContent,
          ),
          if (_photoLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.10),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_busy || _photoLoading) ? null : _pickPhoto,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PhotoActionChip(
                          icon: PhosphorIconsRegular.camera,
                          label: hasNew || hasExisting ? 'Change' : 'Add photo',
                          onTap: (_busy || _photoLoading) ? null : _pickPhoto,
                        ),
                        if (hasNew || hasExisting) ...[
                          const SizedBox(width: 8),
                          _PhotoActionChip(
                            icon: PhosphorIconsRegular.trash,
                            label: 'Remove',
                            onTap: (_busy || _photoLoading) ? null : _removePhoto,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.image,
            size: 44,
            color: AppColors.lightTextSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to add a photo',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended: 1200 × 1200 px',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int? maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines ?? 1,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _OfferPriceField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const _OfferPriceField({required this.controller, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: 'Offer price (₹)',
        hintText: 'Optional',
        filled: true,
        fillColor: AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _CategoryField extends ConsumerWidget {
  final String? menuId;
  final String? selectedCategory;
  final TextEditingController newCategoryController;
  final ValueChanged<String?> onCategorySelected;
  final bool enabled;

  const _CategoryField({
    required this.menuId,
    required this.selectedCategory,
    required this.newCategoryController,
    required this.onCategorySelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (menuId == null || menuId!.isEmpty) {
      return _TextField(
        controller: newCategoryController,
        label: 'Category',
        hint: 'e.g. Quick Bites',
        enabled: enabled,
      );
    }

    final async = ref.watch(menuCategoriesProvider(menuId!));

    return async.when(
      loading: () => const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Could not load categories: $e',
            style: AppTextStyles.caption(context, color: AppColors.adminRed),
          ),
          const SizedBox(height: 8),
          _TextField(
            controller: newCategoryController,
            label: 'Category',
            hint: 'e.g. Quick Bites',
            enabled: enabled,
          ),
        ],
      ),
      data: (categories) {
        final categoryNames = categories
            .map((c) => (c['name'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final selected = selectedCategory;
        final items = [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('— No category —'),
          ),
          ...categoryNames.map(
            (name) => DropdownMenuItem<String?>(value: name, child: Text(name)),
          ),
          if (selected != null &&
              selected.isNotEmpty &&
              !categoryNames.contains(selected))
            DropdownMenuItem<String?>(
              value: selected,
              child: Text(
                selected,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Category',
                filled: true,
                fillColor: AppColors.lightSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.lightBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.lightBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.navy,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              child: IgnorePointer(
                ignoring: !enabled,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedCategory,
                    isExpanded: true,
                    items: items,
                    onChanged: onCategorySelected,
                    hint: const Text('— No category —'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _TextField(
              controller: newCategoryController,
              label: 'Or add new category',
              hint: 'Type here to create a new one',
              enabled: enabled,
            ),
          ],
        );
      },
    );
  }
}

IconData? _symbolToIcon(String symbol) {
  return switch (symbol.toLowerCase()) {
    'chilli' || 'spicy' => PhosphorIconsRegular.pepper,
    'leaf' || 'healthy' || 'vegetarian' => PhosphorIconsRegular.leaf,
    'star' || 'bestseller' => PhosphorIconsRegular.star,
    'flame' || 'new' => PhosphorIconsRegular.fire,
    'heart' || 'popular' => PhosphorIconsRegular.heart,
    'timer' => PhosphorIconsRegular.timer,
    _ => null,
  };
}

class _DietaryTypeField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const _DietaryTypeField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  static const _options = [
    (value: 'veg', label: 'Veg', color: Colors.green),
    (value: 'non_veg', label: 'Non-veg', color: Colors.red),
    (value: 'egg', label: 'Egg', color: Colors.amber),
    (value: 'customizable', label: 'Customizable', color: Colors.blue),
  ];

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Dietary type',
        filled: true,
        fillColor: AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      child: IgnorePointer(
        ignoring: !enabled,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: value,
            isExpanded: true,
            hint: const Text('— None —'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— None —'),
              ),
              for (final option in _options)
                DropdownMenuItem<String?>(
                  value: option.value,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: option.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(option.label),
                    ],
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _EditableChipGroup extends StatelessWidget {
  final String label;
  final List<String> suggestions;
  final Set<String> selected;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final IconData? Function(String)? iconFor;
  final bool enabled;

  const _EditableChipGroup({
    required this.label,
    required this.suggestions,
    required this.selected,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    this.iconFor,
    this.enabled = true,
  });

  void _addFromController(BuildContext context) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return;
    onAdd(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final unselectedSuggestions =
        suggestions.where((s) => !selected.contains(s)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body(
            context,
          ).copyWith(fontWeight: FontWeight.w600, color: AppColors.navy),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in selected)
              InputChip(
                avatar: iconFor != null
                    ? Icon(
                        iconFor!(item) ?? PhosphorIconsRegular.circle,
                        size: 16,
                        color: AppColors.navy,
                      )
                    : null,
                label: Text(item),
                onDeleted: enabled ? () => onRemove(item) : null,
                deleteIconColor: AppColors.adminRed,
                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                side: const BorderSide(color: AppColors.navy),
              ),
          ],
        ),
        if (unselectedSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in unselectedSuggestions)
                FilterChip(
                  avatar: iconFor != null
                      ? Icon(
                          iconFor!(suggestion) ?? PhosphorIconsRegular.circle,
                          size: 16,
                        )
                      : null,
                  label: Text(suggestion),
                  selected: false,
                  onSelected: enabled ? (_) => onAdd(suggestion) : null,
                  side: const BorderSide(color: AppColors.lightBorder),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TextField(
                controller: controller,
                label: 'Add new $label',
                hint: 'Type and press +',
                enabled: enabled,
                onSubmitted: enabled ? (_) => _addFromController(context) : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: enabled ? () => _addFromController(context) : null,
              icon: const Icon(PhosphorIconsRegular.plus),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PhotoActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
