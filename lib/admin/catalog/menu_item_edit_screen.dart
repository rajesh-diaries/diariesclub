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

/// Coffee/FIT menu item create/edit. Route patterns:
///   /admin/catalog/coffee/new?menu_id=<uuid>     — create
///   /admin/catalog/coffee/:id/edit               — edit
///
/// Photo upload uses XFile.readAsBytes (web-safe) and writes to
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
  final _categoryCtrl = TextEditingController();

  bool _isAvailable = true;
  bool _isPublished = true;
  Uint8List? _photoBytes;
  String? _existingPhotoUrl;
  String? _menuId;
  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.itemId != null;

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
    _categoryCtrl.dispose();
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
        _priceCtrl.text =
            (((row['price_paise'] as int?) ?? 0) / 100).toStringAsFixed(0);
        _categoryCtrl.text = (row['category'] as String?) ?? '';
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
    final path = 'menu/$fileName';
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
    if (price == null || price <= 0) return 'Price must be a positive number.';
    if (!_isEditing && (_menuId == null || _menuId!.isEmpty)) {
      return 'Menu missing — go back to the list and try again.';
    }
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
    try {
      final photoUrl = await _uploadPhotoIfNew();
      final pricePaise = int.parse(_priceCtrl.text.trim()) * 100;
      final category = _categoryCtrl.text.trim().isEmpty
          ? null
          : _categoryCtrl.text.trim();

      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_menu_item_update',
          params: {
            'p_id': widget.itemId,
            'p_name': _nameCtrl.text.trim(),
            'p_description': _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            'p_price_paise': pricePaise,
            'p_category': category,
            'p_image_url': photoUrl,
            'p_is_available': _isAvailable,
            'p_is_published': _isPublished,
          },
        );
      } else {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_menu_item_create',
          params: {
            'p_menu_id': _menuId,
            'p_name': _nameCtrl.text.trim(),
            'p_description': _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            'p_price_paise': pricePaise,
            'p_category': category,
            'p_image_url': photoUrl,
            'p_sort_order': null, // auto-append
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Item updated' : 'Item created'),
        ),
      );
      context.go('/admin/catalog/coffee');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('not_admin')
            ? 'You are not authorised.'
            : e.message.contains('invalid_price')
                ? 'Price must be greater than 0.'
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
      appBar: AdminAppBar(title: _isEditing ? 'Edit item' : 'New item'),
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
                              labelText: 'Price (₹)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _categoryCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Category (optional)',
                              hintText: 'e.g. Drinks, Snacks',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isEditing) ...[
                      SwitchListTile(
                        title: const Text('Available'),
                        subtitle: const Text(
                          'Off = sold out for the day; customer sees but cannot order.',
                        ),
                        value: _isAvailable,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isAvailable = v),
                      ),
                      SwitchListTile(
                        title: const Text('Published'),
                        subtitle: const Text('Off = hidden from customers entirely.'),
                        value: _isPublished,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _isPublished = v),
                      ),
                    ],
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
                        AdminSecondaryButton(
                          label: 'Cancel',
                          ghost: true,
                          onPressed: _busy
                              ? null
                              : () => context.go('/admin/catalog/coffee'),
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
            ? Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasNew ? 'New photo' : 'Tap to change',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              )
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
