import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/onboarding_state_provider.dart';
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
class ChildDetailsScreen extends ConsumerStatefulWidget {
  const ChildDetailsScreen({super.key});

  @override
  ConsumerState<ChildDetailsScreen> createState() =>
      _ChildDetailsScreenState();
}

class _ChildDetailsScreenState extends ConsumerState<ChildDetailsScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  DateTime? _dob;
  bool _isLoading = false;
  String? _errorText;
  String? _dobError;

  @override
  void initState() {
    super.initState();
    // If the user previously submitted on this screen and then navigated
    // back, currentOnboardingChildIdProvider still has the child UUID.
    // Refetch the row and prefill so back-nav doesn't lose state — and
    // _submit can route to child_update instead of creating a duplicate.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromDraft());
  }

  Future<void> _prefillFromDraft() async {
    final childId = await ref.read(currentOnboardingChildIdProvider.future);
    if (childId == null || !mounted) return;
    try {
      final row = await Supabase.instance.client
          .from('children')
          .select('name, dob, delivery_address')
          .eq('id', childId)
          .maybeSingle();
      if (row == null || !mounted) return;
      final prefilledDob = DateTime.tryParse((row['dob'] as String?) ?? '');
      setState(() {
        _nameController.text = (row['name'] as String?) ?? '';
        _addressController.text = (row['delivery_address'] as String?) ?? '';
        _dob = prefilledDob;
        if (prefilledDob != null) {
          _dobController.text = DateFormat('dd/MM/yyyy').format(prefilledDob);
        }
      });
    } catch (_) {
      // Non-fatal — user will just see blank fields, same as today.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && _dob != null && _dobError == null && !_isLoading;

  void _onDobChanged(String value) {
    if (value.length != 10) {
      setState(() {
        _dob = null;
        _dobError = null;
      });
      return;
    }
    final parts = value.split('/');
    if (parts.length != 3) {
      setState(() {
        _dob = null;
        _dobError = 'Use DD/MM/YYYY format';
      });
      return;
    }
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) {
      setState(() {
        _dob = null;
        _dobError = 'Invalid date';
      });
      return;
    }
    final parsed = DateTime.tryParse('$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
    if (parsed == null || parsed.day != day || parsed.month != month) {
      setState(() {
        _dob = null;
        _dobError = 'That date does not exist';
      });
      return;
    }
    final today = DateTime.now();
    final minDob = today.subtract(const Duration(days: 14 * 365));
    if (parsed.isAfter(today)) {
      setState(() {
        _dob = null;
        _dobError = 'Date cannot be in the future';
      });
      return;
    }
    if (parsed.isBefore(minDob)) {
      setState(() {
        _dob = null;
        _dobError = 'Child must be under 14 years';
      });
      return;
    }
    setState(() {
      _dob = parsed;
      _dobError = null;
    });
  }

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
      setState(() {
        _dob = picked;
        _dobController.text = DateFormat('dd/MM/yyyy').format(picked);
        _dobError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final existingId =
          await ref.read(currentOnboardingChildIdProvider.future);
      final client = Supabase.instance.client;
      final name = _nameController.text.trim();
      final dobStr = DateFormat('yyyy-MM-dd').format(_dob!);
      final address = _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim();

      final String childId;
      if (existingId != null) {
        // Returning user after back-nav — update the same row instead of
        // creating a duplicate. Preserves whatever favourite_hero they
        // already picked on the hero-pick screen if they got that far.
        await client.rpc<Map<String, dynamic>>(
          'child_update',
          params: {
            'p_child_id': existingId,
            'p_name': name,
            'p_dob': dobStr,
            'p_favourite_hero': null,
            'p_delivery_address': address,
          },
        );
        childId = existingId;
      } else {
        final result = await client.rpc<Map<String, dynamic>>(
          'child_create',
          params: {
            'p_name': name,
            'p_dob': dobStr,
            'p_favourite_hero': 'ellie',
            'p_delivery_address': address,
          },
        );
        final newId = result['child_id'] as String?;
        if (newId == null) {
          throw StateError('child_create did not return child_id');
        }
        childId = newId;
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
              TextField(
                controller: _dobController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                onChanged: _onDobChanged,
                inputFormatters: [_DobInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Date of birth (DD/MM/YYYY)',
                  hintText: '12/05/2020',
                  counterText: '',
                  errorText: _dobError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today, size: 20),
                    onPressed: _pickDob,
                  ),
                ),
                style: AppTextStyles.body(context),
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

/// Formats typed digits into DD/MM/YYYY. Only allows numbers; auto-inserts
/// slashes after the day and month segments. Backspace works naturally.
class _DobInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(raw[i]);
    }
    final formatted = buffer.toString();
    // Keep cursor at the end unless user is deleting.
    final selection = newValue.selection.baseOffset > oldValue.selection.baseOffset
        ? TextSelection.collapsed(offset: formatted.length)
        : newValue.selection;
    return TextEditingValue(text: formatted, selection: selection);
  }
}
