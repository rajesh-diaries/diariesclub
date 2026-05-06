import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Staff-app top bar. Plain `StatelessWidget` (NOT a `ConsumerWidget`) — the
/// device label is passed in by the screen, which reads the provider once.
///
/// Why: per the BUG-031 bisect, the original `ConsumerWidget extends +
/// ref.watch(currentTabletDeviceProvider)` here was rebuilding the AppBar in
/// a way that absorbed body taps on Flutter web (every rebuild
/// re-registered MouseRegions and the resulting hit-test paths covered the
/// body area). Decoupling the AppBar from Riverpod fixed it.
///
/// Also dropped the leading phone-icon-in-title Row — redundant; the AppBar
/// itself signals "this is the staff app". If we ever want a leading glyph,
/// use AppBar.leading rather than baking it into title.
class StaffAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final String? deviceLabel;
  final List<Widget>? extraActions;
  const StaffAppBar({
    super.key,
    this.title,
    this.deviceLabel,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(
        title ?? deviceLabel ?? 'Diaries Staff',
        style: AppTextStyles.h3(context),
      ),
      actions: [
        ...?extraActions,
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                  'Signing out will require this phone to be re-registered '
                  'before any staff can use it.',
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
