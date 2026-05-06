import 'package:flutter/material.dart';

/// BUG-031 minimal-StaffAppBar bisect. Reduced to a plain StatelessWidget
/// returning AppBar(title: Text('Diaries Staff')) — no ConsumerWidget,
/// no ref.watch, no Row, no Icon, no AppTextStyles, no actions array,
/// no IconButton, no tooltip, no showDialog. If body taps fire with
/// THIS, we build back layers and find the absorber.
class StaffAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? extraActions;
  const StaffAppBar({super.key, this.title, this.extraActions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(title ?? 'Diaries Staff'),
      // BUG-031 bisect step 5: add tooltip back on the IconButton.
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () {},
        ),
      ],
    );
  }
}
