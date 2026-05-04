import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Internal-route nav row inside a [ProfileSectionCard]. Trailing chevron
/// + optional value text on the right (e.g. "Theme — System >").
class ProfileNavRow extends StatelessWidget {
  final String label;
  final String? trailing;
  final IconData? leading;
  final Color? leadingColor;
  final String route;
  final VoidCallback? onTap;

  const ProfileNavRow({
    super.key,
    required this.label,
    required this.route,
    this.trailing,
    this.leading,
    this.leadingColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading == null
          ? null
          : Icon(leading, color: leadingColor ?? AppColors.navy),
      title: Text(label, style: AppTextStyles.body(context)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[
            Text(
              trailing!,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(
            Icons.chevron_right,
            color: AppColors.lightTextSecondary,
            size: 22,
          ),
        ],
      ),
      onTap: onTap ?? () => context.push(route),
    );
  }
}

/// External-link nav row — opens the URL in the platform browser. Shows
/// an "external" arrow instead of a chevron.
class ProfileExternalRow extends StatelessWidget {
  final String label;
  final String url;
  final IconData? leading;

  const ProfileExternalRow({
    super.key,
    required this.label,
    required this.url,
    this.leading,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open $label.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading == null
          ? null
          : Icon(leading, color: AppColors.navy),
      title: Text(label, style: AppTextStyles.body(context)),
      trailing: const Icon(
        Icons.north_east,
        color: AppColors.lightTextSecondary,
        size: 18,
      ),
      onTap: () => _open(context),
    );
  }
}

/// Settings-style row that fires a callback rather than navigating. Used
/// by Theme (opens a sheet), Sign out (opens a dialog), etc.
class ProfileActionRow extends StatelessWidget {
  final String label;
  final String? trailing;
  final IconData? leading;
  final Color? leadingColor;
  final Color? labelColor;
  final VoidCallback onTap;

  const ProfileActionRow({
    super.key,
    required this.label,
    required this.onTap,
    this.trailing,
    this.leading,
    this.leadingColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading == null
          ? null
          : Icon(leading, color: leadingColor ?? AppColors.navy),
      title: Text(
        label,
        style: AppTextStyles.body(context, color: labelColor),
      ),
      trailing: trailing == null
          ? const Icon(
              Icons.chevron_right,
              color: AppColors.lightTextSecondary,
              size: 22,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing!,
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.lightTextSecondary,
                  size: 22,
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}
