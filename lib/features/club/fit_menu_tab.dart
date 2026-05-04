import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/brand_menu_tab.dart';

/// FIT Diaries menu (brand='fit').
class FitMenuTab extends StatelessWidget {
  const FitMenuTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrandMenuTab(
      brand: 'fit',
      title: 'FIT Diaries',
      tagline: 'Healthy + tasty, made fresh.',
      heroImage:
          'https://placehold.co/1200x600/0D4A2E/FFFFFF.png?text=FIT+Diaries',
      brandColor: AppColors.fitGreen,
      brandIcon: PhosphorIconsFill.carrot,
    );
  }
}
