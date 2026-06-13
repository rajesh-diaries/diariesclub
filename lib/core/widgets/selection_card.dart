import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A branded, selectable card that replaces the deprecated
/// `RadioListTile` pattern for payment and kid-selection flows.
class SelectableCard<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool enabled;

  const SelectableCard({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.leading,
    this.enabled = true,
  });

  bool get _selected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final active = _selected && enabled;
    final bgColor = active
        ? AppColors.navy
        : enabled
            ? AppColors.lightSurface
            : AppColors.lightBackground;
    final fgColor = active ? Colors.white : AppColors.navy;
    final mutedColor = active
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.lightTextSecondary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppColors.navy
              : enabled
                  ? AppColors.lightBorder
                  : AppColors.lightBorder.withValues(alpha: 0.5),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled && onChanged != null
              ? () => onChanged!(value)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.body(
                          context,
                          color: fgColor,
                        ).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTextStyles.caption(
                            context,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    active
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIconsRegular.circle,
                    key: ValueKey<bool>(active),
                    color: active
                        ? AppColors.gold
                        : enabled
                            ? AppColors.lightBorder
                            : AppColors.lightBorder.withValues(alpha: 0.5),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
