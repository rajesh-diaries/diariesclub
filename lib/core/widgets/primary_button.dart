import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Single primary CTA used across the app. Filled, rounded, navy by default.
///
/// BUG-039a fix: rewritten from `FilledButton` to the canonical
/// Material+InkWell pattern. The previous FilledButton+Row(MainAxisSize.min)
/// +Flexible combination was crashing the entire reflection widget tree on
/// Flutter web — Flexible inside a min-axis Row has contradictory layout
/// constraints that assert silently and abort the build subtree, blanking
/// the whole screen. Same widget family blocked BUG-024 and parts of BUG-031.
/// The Material+InkWell shape avoids both pitfalls: Material owns paint +
/// shape, InkWell owns hit-test + ripple, the inner Row uses default
/// MainAxisSize.max with center alignment so no Flexible needed.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = loading || onPressed == null;
    final bg = disabled ? AppColors.navy.withValues(alpha: 0.50) : AppColors.navy;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
