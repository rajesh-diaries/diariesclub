import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '_menu_items_view.dart';

/// View-only list of FIT menu items (menus.brand='fit'). Module 2.5
/// introduces the meal-builder layer (fit_meal_templates + categories +
/// options) on top of this; until then we surface what's already in
/// menu_items.
class FitListScreen extends StatelessWidget {
  const FitListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MenuItemsView(
      brand: 'fit',
      title: 'FIT',
      subtitle: 'Read-only — name, photo, category, price, availability',
      placeholderBanner:
          'Meal builder (templates / categories / options) ships in Module 2.5. '
          'Today this lists the existing menu_items where brand=fit.',
      emptyMessage: 'No FIT items yet.',
      emptySubtitle:
          'Seed will land alongside the Module 2.5 meal-builder schema.',
      emptyIcon: PhosphorIconsRegular.barbell,
    );
  }
}
