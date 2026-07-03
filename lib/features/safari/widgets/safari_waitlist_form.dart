import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import 'safari_colors.dart';

class SafariWaitlistForm extends ConsumerStatefulWidget {
  const SafariWaitlistForm({super.key});

  @override
  ConsumerState<SafariWaitlistForm> createState() => _SafariWaitlistFormState();
}

class _SafariWaitlistFormState extends ConsumerState<SafariWaitlistForm> {
  final _parentNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _childNameController = TextEditingController();
  DateTime? _childDob;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _initFromProviders();
  }

  void _initFromProviders() {
    final family = ref.read(currentFamilyProvider).valueOrNull;
    if (family != null) {
      final phone = family['phone'] as String?;
      if (phone != null && phone.isNotEmpty) {
        // Family phone is stored in E.164 (+91XXXXXXXXXX). The waitlist field
        // expects a 10-digit Indian mobile number.
        final digits = phone.replaceAll(RegExp(r'\D'), '');
        _phoneController.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      }
    }

    final children = ref.read(familyChildrenProvider).valueOrNull ?? [];
    if (children.isNotEmpty) {
      final firstChild = children.first;
      final childName = firstChild['name'] as String?;
      if (childName != null && childName.isNotEmpty) {
        _childNameController.text = childName;
      }
      final dob = _parseDob(firstChild['date_of_birth'] as String?);
      if (dob != null) {
        _childDob = dob;
      }
    }
  }

  DateTime? _parseDob(String? dobStr) {
    if (dobStr == null) return null;
    try {
      return DateTime.parse(dobStr);
    } catch (_) {
      return null;
    }
  }

  int? _ageFromDob(DateTime? dob) {
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // Program is for ages 2–5, so constrain the picker to eligible birth dates.
    final firstDate = DateTime(now.year - 6, now.month, now.day);
    final lastDate = DateTime(now.year - 2, now.month, now.day);
    final requested = _childDob ?? DateTime(now.year - 3, now.month, now.day);
    final initial = requested.isBefore(firstDate)
        ? firstDate
        : (requested.isAfter(lastDate) ? lastDate : requested);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select child date of birth',
    );
    if (picked != null) {
      setState(() => _childDob = picked);
    }
  }

  @override
  void dispose() {
    _parentNameController.dispose();
    _phoneController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _parentNameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().length >= 10 &&
        _childNameController.text.trim().isNotEmpty &&
        _childDob != null &&
        !_submitting;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _submitting = true);

    try {
      final familyId =
          ref.read(currentFamilyProvider).valueOrNull?['id'] as String?;

      final dob = _childDob!;
      final age = _ageFromDob(dob);

      await Supabase.instance.client.from('safari_waitlist').insert({
        'family_id': familyId,
        'parent_name': _parentNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'child_name': _childNameController.text.trim(),
        'child_dob': DateFormat('yyyy-MM-dd').format(dob),
        'child_age': age,
        'source': 'app',
      });

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Something went wrong. Please try again.',
              style: AppTextStyles.body(context, color: Colors.white),
            ),
            backgroundColor: AppColors.adminRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: SafariColors.lightSage,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(
              PhosphorIconsRegular.checkCircle,
              size: 48,
              color: SafariColors.jungleGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'Thanks for your interest!',
              style: AppTextStyles.h3(context, color: SafariColors.jungleGreen),
            ),
            const SizedBox(height: 8),
            Text(
              'We’ll reach out when enrollment opens.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(context, color: SafariColors.slate),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Interested?',
            style: AppTextStyles.h3(context, color: SafariColors.jungleGreen),
          ),
          const SizedBox(height: 8),
          Text(
            'Let us know and we’ll reach out when enrollment opens. No commitment required.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _parentNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Parent name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Phone number',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _childNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Child name',
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
                labelText: 'Child date of birth',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: const Icon(PhosphorIconsRegular.calendarBlank),
              ),
              child: Text(
                _childDob == null
                    ? 'Tap to pick a date'
                    : DateFormat('dd MMM yyyy').format(_childDob!),
                style: AppTextStyles.body(
                  context,
                  color: _childDob == null
                      ? AppColors.lightTextSecondary
                      : AppColors.navy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: "I'm interested",
              onPressed: _canSubmit ? _submit : null,
              loading: _submitting,
            ),
          ),
        ],
      ),
    );
  }
}
