import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'widgets/brand_menu_tab.dart';

/// Coffee Diaries menu (brand='coffee').
class CoffeeMenuTab extends ConsumerWidget {
  const CoffeeMenuTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const BrandMenuTab(
      brand: 'coffee',
      title: 'Coffee Diaries',
      brandColor: AppColors.coffeeBrownDeep,
      brandIcon: PhosphorIconsFill.coffee,
    );
  }
}
