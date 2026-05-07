import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Material+InkWell button replacements for FilledButton / IconButton /
/// ExpansionTile in the admin web app. Same pattern that fixed BUG-039a
/// (PrimaryButton) and BUG-024 (Profile Top up):
///
///     Material(color, shape, clipBehavior: antiAlias)
///       └─ InkWell(onTap)
///            └─ Padding
///                 └─ Row(min)
///
/// Why this is more reliable on Flutter web than the stock widgets:
///   * Material owns paint + shape — no FilledButton internal Row+Flexible
///     anti-pattern that crashed build subtrees on web.
///   * InkWell registers exactly one MouseRegion per instance — fewer
///     re-registration churn during ConsumerWidget rebuilds (BUG-031
///     family).
///   * Explicit `color` and `borderRadius` so we never depend on theme
///     defaults that drift between Flutter versions.
///
/// Use these everywhere in `lib/admin/`. Customer/staff apps continue
/// to use the canonical PrimaryButton (customer) or stock widgets where
/// they work.

// =============================================================================
//  AdminPrimaryButton — replaces FilledButton + FilledButton.icon (navy)
//  + danger variant for FilledButton(style: red).
// =============================================================================
class AdminPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool dense;

  /// Override background colour. Defaults to navy. Use `.danger` for red.
  final Color? color;

  const AdminPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.dense = false,
    this.color,
  });

  /// Destructive variant — red background.
  const AdminPrimaryButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.dense = false,
  }) : color = AppColors.adminRed;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || onPressed == null;
    final bg = color ?? AppColors.navy;
    final shaded = disabled ? bg.withValues(alpha: 0.50) : bg;
    final vPad = dense ? 8.0 : 12.0;
    final hPad = dense ? 12.0 : 16.0;

    return Material(
      color: shaded,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  AdminSecondaryButton — outlined / ghost-style. Replaces TextButton +
//  TextButton.icon + the secondary-action role of FilledButton inside
//  AlertDialog.actions.
// =============================================================================
class AdminSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? foreground;

  /// If true, no border — just a tappable text label (TextButton role).
  /// If false (default), shows a 1.2px outline matching foreground.
  final bool ghost;

  const AdminSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.foreground,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final fg = foreground ?? AppColors.navy;
    final shaded = disabled ? fg.withValues(alpha: 0.50) : fg;

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: ghost
            ? BorderSide.none
            : BorderSide(color: shaded, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: shaded),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: shaded,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  AdminIconButton — replaces stock IconButton (transparent bg, circle
//  ripple, optional tooltip).
// =============================================================================
class AdminIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  const AdminIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final iconColor = disabled
        ? (color ?? AppColors.navy).withValues(alpha: 0.40)
        : (color ?? AppColors.navy);

    Widget button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: size, color: iconColor),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
