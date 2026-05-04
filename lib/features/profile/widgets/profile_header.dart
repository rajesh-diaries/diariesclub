import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/phone.dart';
import 'edit_profile_sheet.dart';

/// Top-of-Profile header row: avatar (initials), family name + phone,
/// edit pencil. Phone is intentionally read-only — change requires
/// re-OTP, which is gated by support contact.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  void _edit(BuildContext context, Map<String, dynamic> family) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditProfileSheet(family: family),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(currentFamilyProvider);
    final family = familyAsync.valueOrNull ?? const <String, dynamic>{};
    final name = (family['name'] as String?) ?? 'Welcome';
    final phone = (family['phone'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.20),
            ),
            child: Text(
              _initials(name),
              style: AppTextStyles.h2(context, color: AppColors.navy),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.h3(context)),
                const SizedBox(height: 4),
                if (phone.isNotEmpty)
                  Text(
                    PhoneNormalizer.forDisplay(phone),
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(
              PhosphorIconsRegular.pencilSimple,
              color: AppColors.navy,
            ),
            onPressed: family.isEmpty ? null : () => _edit(context, family),
          ),
        ],
      ),
    );
  }
}
