import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/onboarding_state_provider.dart';
import '../../core/services/photo_compress_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/progress_dots.dart';

/// Onboarding step 3 — collect child details and create the row.
///
/// We call `child_create` here with `favourite_hero='ellie'` (the schema
/// default) and let the next screen update it. Inserting on this screen
/// rather than buffering means the child row exists for resume purposes
/// (kill-and-reopen at hero-pick still works).
///
/// Photo upload to Storage is deferred — we wire it once a public bucket
/// + policies land. For now the picker shows but `photo_url` is sent as
/// null. A user can re-select the photo from Profile later.
class ChildDetailsScreen extends ConsumerStatefulWidget {
  const ChildDetailsScreen({super.key});

  @override
  ConsumerState<ChildDetailsScreen> createState() =>
      _ChildDetailsScreenState();
}

class _ChildDetailsScreenState extends ConsumerState<ChildDetailsScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _dob;
  Uint8List? _photoBytes;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && _dob != null && !_isLoading;

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final minDob = today.subtract(const Duration(days: 14 * 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? today.subtract(const Duration(days: 5 * 365)),
      firstDate: minDob,
      lastDate: today,
      helpText: "Pick your child's date of birth",
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
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
      _isLoading = true;
      _errorText = null;
    });

    try {
      final result = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'child_create',
        params: {
          'p_name': _nameController.text.trim(),
          'p_dob': DateFormat('yyyy-MM-dd').format(_dob!),
          // p_photo_url left null for now — Storage wiring is a later session.
          'p_photo_url': null,
          'p_favourite_hero': 'ellie',
          'p_delivery_address':
              _addressController.text.trim().isEmpty
                  ? null
                  : _addressController.text.trim(),
        },
      );

      final childId = result['child_id'] as String?;
      if (childId == null) {
        throw StateError('child_create did not return child_id');
      }

      await ref.read(currentOnboardingChildIdProvider.notifier).set(childId);
      await ref
          .read(onboardingStepProvider.notifier)
          .setStep(OnboardingStep.heroPick);

      if (!mounted) return;
      context.go('/onboarding/hero-pick');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't save. Please try again.";
        _isLoading = false;
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
        title: const ProgressDots(currentStep: 3),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await ref
                .read(onboardingStepProvider.notifier)
                .setStep(OnboardingStep.addChild);
            if (!context.mounted) return;
            context.go('/onboarding/add-child');
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('About your kid', style: AppTextStyles.h1(context)),
              const SizedBox(height: 24),

              // Photo picker
              Center(
                child: GestureDetector(
                  onTap: _isLoading ? null : _pickPhoto,
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
                  style: AppTextStyles.caption(context,
                      color: AppColors.lightTextSecondary),
                ),
              ),

              const SizedBox(height: 24),

              // Name
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

              // DOB
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

              // Address (optional)
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

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorText!,
                    style: AppTextStyles.caption(context,
                        color: AppColors.adminRed),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Continue',
                  onPressed: _canSubmit ? _submit : null,
                  loading: _isLoading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
