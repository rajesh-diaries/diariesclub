import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/child_avatar.dart';
import 'profile_section.dart';

/// Family children list shown inside Profile. Empty + add-child + chevron
/// to the per-child edit screen. Reactive via `familyChildrenProvider`.
class ChildrenList extends ConsumerWidget {
  const ChildrenList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];

    return ProfileSectionCard(
      children: [
        for (final c in children) _ChildRow(child: c),
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.15),
            ),
            child: const Icon(
              PhosphorIconsRegular.plus,
              color: AppColors.navy,
              size: 18,
            ),
          ),
          title: Text(
            children.isEmpty ? 'Add a child' : 'Add another child',
            style: AppTextStyles.body(context),
          ),
          onTap: () => context.push('/profile/add-child'),
        ),
      ],
    );
  }
}

class _ChildRow extends StatelessWidget {
  final Map<String, dynamic> child;
  const _ChildRow({required this.child});

  int? _ageYears() {
    final dob = child['date_of_birth'] as String?;
    if (dob == null) return null;
    final d = DateTime.parse(dob);
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  @override
  Widget build(BuildContext context) {
    final age = _ageYears();
    return ListTile(
      leading: ChildAvatar(
        name: (child['name'] as String?) ?? '',
        size: 40,
      ),
      title: Text((child['name'] as String?) ?? '—'),
      subtitle: age == null
          ? null
          : Text('$age year${age == 1 ? '' : 's'} old'),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.lightTextSecondary,
        size: 22,
      ),
      onTap: () => context.push('/profile/child/${child['id']}'),
    );
  }
}
