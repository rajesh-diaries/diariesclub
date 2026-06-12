import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  ConsumerState<SafariWaitlistForm> createState() =>
      _SafariWaitlistFormState();
}

class _SafariWaitlistFormState extends ConsumerState<SafariWaitlistForm> {
  final _parentNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _childNameController = TextEditingController();
  int? _selectedAge;
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
        _phoneController.text = phone;
      }
    }

    final children = ref.read(familyChildrenProvider).valueOrNull ?? [];
    if (children.isNotEmpty) {
      final firstChild = children.first;
      final childName = firstChild['name'] as String?;
      if (childName != null && childName.isNotEmpty) {
        _childNameController.text = childName;
      }
      final age = _ageFromDob(firstChild['date_of_birth'] as String?);
      if (age != null && age >= 2 && age <= 4) {
        _selectedAge = age;
      }
    }
  }

  int? _ageFromDob(String? dobStr) {
    if (dobStr == null) return null;
    try {
      final dob = DateTime.parse(dobStr);
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age < 0 ? 0 : age;
    } catch (_) {
      return null;
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
        _selectedAge != null &&
        !_submitting;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _submitting = true);

    try {
      final familyId =
          ref.read(currentFamilyProvider).valueOrNull?['id'] as String?;

      await Supabase.instance.client.from('safari_waitlist').insert({
        'family_id': familyId,
        'parent_name': _parentNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'child_name': _childNameController.text.trim(),
        'child_age': _selectedAge,
        'source': 'app',
      });

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
              'You\'re on the list!',
              style: AppTextStyles.h3(
                context,
                color: SafariColors.jungleGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We\'ll reach out as soon as Safari Club is ready. Thank you for your interest!',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(
                context,
                color: SafariColors.slate,
              ),
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
            'Join the waitlist',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to know when Safari Club opens. No commitment required.',
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
          Text(
            'Child age',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [2, 3, 4].map((age) {
              final selected = _selectedAge == age;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text('$age years'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedAge = age),
                  selectedColor: SafariColors.jungleGreen,
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected
                        ? SafariColors.jungleGreen
                        : AppColors.lightBorder,
                  ),
                  labelStyle: AppTextStyles.body(
                    context,
                    color: selected ? Colors.white : SafariColors.slate,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Join waitlist',
              onPressed: _canSubmit ? _submit : null,
              loading: _submitting,
            ),
          ),
        ],
      ),
    );
  }
}
