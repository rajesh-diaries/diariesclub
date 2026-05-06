import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/staff_auth_provider.dart';

/// Shared staff-app top bar. Shows the venue label on the left, a sign-out
/// affordance on the right.
class StaffAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? extraActions;
  const StaffAppBar({super.key, this.title, this.extraActions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(currentTabletDeviceProvider).valueOrNull;
    final label = (device?['device_label'] as String?) ?? 'Diaries Staff';

    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Icon(Icons.phone_iphone, color: AppColors.navy, size: 20),
          const SizedBox(width: 8),
          Text(
            title ?? label,
            style: AppTextStyles.h3(context),
          ),
        ],
      ),
      actions: [
        ...?extraActions,
        IconButton(
          tooltip: 'Sign out tablet',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Sign out tablet?'),
                content: const Text(
                  'Signing out the tablet will require the device to be re-registered before any staff can use it.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.adminRed,
                    ),
                    onPressed: () => Navigator.of(c).pop(true),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await Supabase.instance.client.auth.signOut();
            }
          },
        ),
      ],
    );
  }
}
