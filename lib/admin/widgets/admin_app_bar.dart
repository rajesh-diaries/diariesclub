import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Top bar inside the admin shell. Section title on the left, optional
/// action slot on the right.
class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AdminAppBar({super.key, required this.title, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(color: AppColors.lightBorder),
        ),
      ),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.h2(context)),
          const Spacer(),
          ...?actions,
        ],
      ),
    );
  }
}
