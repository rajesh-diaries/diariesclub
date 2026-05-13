import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/brand_menu_tab.dart';

/// Coffee Diaries menu (brand='coffee').
class CoffeeMenuTab extends StatelessWidget {
  const CoffeeMenuTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrandMenuTab(
      brand: 'coffee',
      title: 'Coffee Diaries',
      tagline: 'Slow brews, fast smiles.',
      brandColor: AppColors.coffeeBrown,
      brandIcon: PhosphorIconsFill.coffee,
    );
  }
}
