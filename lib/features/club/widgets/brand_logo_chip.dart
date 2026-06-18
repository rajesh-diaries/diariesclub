import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Compact brand identity row for Club brand tabs (Coffee / FIT).
/// Shows the brand logo plus an optional tagline. No tall colored hero.
class BrandLogoChip extends StatelessWidget {
  final String logoAsset;
  final String? tagline;
  final double logoHeight;

  const BrandLogoChip({
    super.key,
    required this.logoAsset,
    this.tagline,
    this.logoHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Image.asset(
            logoAsset,
            height: logoHeight,
            fit: BoxFit.contain,
          ),
          if (tagline != null && tagline!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tagline!,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
