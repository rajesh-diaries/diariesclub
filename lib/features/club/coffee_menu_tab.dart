import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import 'widgets/brand_menu_tab.dart';

/// Coffee Diaries menu (brand='coffee').
class CoffeeMenuTab extends ConsumerWidget {
  const CoffeeMenuTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final tagline = (cfg['coffee_diaries_tagline'] as String?)?.trim() ?? '';
    return BrandMenuTab(
      brand: 'coffee',
      title: 'Coffee Diaries',
      tagline: tagline,
      brandColor: AppColors.coffeeBrownDeep,
      brandIcon: PhosphorIconsFill.coffee,
    );
  }
}
