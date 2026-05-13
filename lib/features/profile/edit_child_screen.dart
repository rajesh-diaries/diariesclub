import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/services/child_photo_service.dart';
import '../../core/services/photo_compress_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/child_avatar.dart';
import '../../core/widgets/primary_button.dart';
import 'widgets/hero_picker.dart';

/// Edit a single child's profile. Pre-populated, with a "Remove child"
/// CTA at the bottom that calls `child_deactivate` (soft-delete). The RPC
/// blocks last-child removal unless the family is_cafe_only=true.
class EditChildScreen extends ConsumerStatefulWidget {
  final String childId;
  const EditChildScreen({super.key, required this.childId});

  @override
  ConsumerState<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends ConsumerState<EditChildScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _dob;
  String _hero = 'ellie';
  String? _existingPhotoPath;
  Uint8List? _newPhotoBytes;
  bool _busy = false;
  bool _hydrated = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> child) {
    if (_hydrated) return;
    _hydrated = true;
    _nameController.text = (child['name'] as String?) ?? '';
    _addressController.text = (child['delivery_address'] as String?) ?? '';
    _hero = (child['favourite_hero'] as String?) ?? 'ellie';
    _existingPhotoPath = child['photo_url'] as String?;
    final dob = child['date_of_birth'] as String?;
    if (dob != null) _dob = DateTime.tryParse(dob);
  }

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? today.subtract(const Duration(days: 5 * 365)),
      firstDate: today.subtract(const Duration(days: 14 * 365)),
      lastDate: today,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      final compressed = await PhotoCompressService.compress(raw);
      if (!mounted) return;
      setState(() => _newPhotoBytes = compressed);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _errorText = "Couldn't load that photo. Try a different one.");
    }
  }

  Future<void> _save() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    if (_nameController.text.trim().isEmpty || _dob == null) {
      setState(() => _errorText = 'Name and date of birth are required.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    String? newPath;
    try {
      if (_newPhotoBytes != null) {
        newPath = await ChildPhotoService.uploadCompressed(
          familyId: familyId,
          childId: widget.childId,
          rawBytes: _newPhotoBytes!,
        );
      }

      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('child_update', params: {
        'p_child_id': widget.childId,
        'p_name': _nameController.text.trim(),
        'p_dob': DateFormat('yyyy-MM-dd').format(_dob!),
        if (newPath != null) 'p_photo_url': newPath,
        'p_favourite_hero': _hero,
        'p_delivery_address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
      });

      // Best-effort cleanup of the orphan photo (the path uploaded on a
      // *previous* edit, not the just-created one).
      if (newPath != null && _existingPhotoPath != null) {
        await ChildPhotoService.deleteIfExists(_existingPhotoPath);
      }

      ref.invalidate(familyChildrenProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't save. Please try again.";
      });
    }
  }

  Future<void> _confirmRemove(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'Their adventure progress, character cards, and history will be archived '
          'but kept for your records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('child_deactivate', params: {
        'p_child_id': widget.childId,
      });
      ref.invalidate(familyChildrenProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name removed')),
      );
      context.pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('cannot_remove_only_child')
            ? 'Add another child first, or set this account to cafe-only '
                'in settings.'
            : "Couldn't remove. Please try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't remove. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final child = children.firstWhere(
      (c) => c['id'] == widget.childId,
      orElse: () => const <String, dynamic>{},
    );
    if (child.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _hydrate(child);

    final dobText = _dob == null
        ? 'Pick a date'
        : DateFormat('dd MMM yyyy').format(_dob!);
    final name = (child['name'] as String?) ?? 'Child';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit child'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _busy ? null : _pickPhoto,
                  child: _newPhotoBytes != null
                      ? Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: MemoryImage(_newPhotoBytes!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : ChildAvatar(
                          name: name,
                          size: 96,
                          photoPath: _existingPhotoPath,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _newPhotoBytes != null || _existingPhotoPath != null
                      ? 'Tap to change'
                      : 'Add photo (optional)',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: "Child's first name",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: const Icon(Icons.calendar_today, size: 20),
                  ),
                  child: Text(dobText, style: AppTextStyles.body(context)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Delivery address (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Favourite character', style: AppTextStyles.bodyLarge(context)),
              const SizedBox(height: 12),
              HeroPicker(
                selected: _hero,
                onChanged: (id) => setState(() => _hero = id),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Save changes',
                  onPressed: _busy ? null : _save,
                  loading: _busy,
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _busy ? null : () => _confirmRemove(name),
                icon: const Icon(
                  PhosphorIconsRegular.trash,
                  color: AppColors.adminRed,
                ),
                label: Text(
                  'Remove $name from family',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.adminRed,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
