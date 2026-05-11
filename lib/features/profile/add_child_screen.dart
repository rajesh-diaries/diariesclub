import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_family_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/services/child_photo_service.dart';
import '../../core/services/photo_compress_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import 'widgets/hero_picker.dart';

/// "Add a child" — combined details + hero pick in one form (the
/// onboarding version is split across two screens because of the
/// progress dots; post-onboarding we fold them together).
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _dob;
  Uint8List? _photoBytes;
  String _hero = 'ellie';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && _dob != null && !_busy;

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? today.subtract(const Duration(days: 5 * 365)),
      firstDate: today.subtract(const Duration(days: 14 * 365)),
      lastDate: today,
      helpText: "Pick your child's date of birth",
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
      setState(() => _photoBytes = compressed);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _errorText = "Couldn't load that photo. Please try a different one.");
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });

    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() => _busy = false);
      return;
    }

    try {
      // 1) Create the child row with photo_url=null (we don't have a child_id
      // until insert, and the storage path includes the child_id).
      final created = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('child_create', params: {
        'p_name': _nameController.text.trim(),
        'p_dob': DateFormat('yyyy-MM-dd').format(_dob!),
        'p_photo_url': null,
        'p_favourite_hero': _hero,
        'p_delivery_address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
      });
      final childId = created['child_id'] as String?;
      if (childId == null) {
        throw StateError('child_create did not return child_id');
      }

      // 2) If a photo was picked, upload then patch the row with the path.
      if (_photoBytes != null) {
        final path = await ChildPhotoService.uploadCompressed(
          familyId: familyId,
          childId: childId,
          rawBytes: _photoBytes!,
        );
        await Supabase.instance.client
            .rpc<Map<String, dynamic>>('child_update', params: {
          'p_child_id': childId,
          'p_photo_url': path,
        });
      }

      ref.invalidate(familyChildrenProvider);
      ref.invalidate(currentFamilyProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_nameController.text.trim()} added to your family'),
        ),
      );
      context.pop();
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't add child. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobText = _dob == null
        ? 'Pick a date'
        : DateFormat('dd MMM yyyy').format(_dob!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a child'),
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
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: _busy ? null : _pickPhoto,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withValues(alpha: 0.18),
                      image: _photoBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_photoBytes!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _photoBytes == null
                        ? const Icon(
                            PhosphorIconsFill.camera,
                            color: AppColors.navy,
                            size: 32,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _photoBytes == null ? 'Add photo (optional)' : 'Tap to change',
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
                style: AppTextStyles.body(context),
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
                  helperText: "We'll mail special prizes here",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: AppTextStyles.body(context),
              ),
              const SizedBox(height: 24),
              Text('Pick a favourite character',
                  style: AppTextStyles.bodyLarge(context)),
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
                  label: 'Add to family',
                  onPressed: _canSubmit ? _submit : null,
                  loading: _busy,
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
