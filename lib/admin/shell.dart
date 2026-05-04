import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import 'widgets/admin_sidebar.dart';

/// Two-pane shell: persistent sidebar on the left at >=900px wide, drawer
/// otherwise. Children are the per-route screens. Each screen is
/// responsible for its own AppBar via AdminAppBar.
class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      drawer: isWide ? null : const Drawer(child: AdminSidebar()),
      body: Row(
        children: [
          if (isWide) const AdminSidebar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
