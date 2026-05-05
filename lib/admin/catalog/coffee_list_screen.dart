import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '_menu_items_view.dart';

/// View-only list of Coffee Diaries menu items. Module 2.4 replaces this
/// with full CRUD (photo upload, drag-to-reorder, sold-out toggle).
class CoffeeListScreen extends StatelessWidget {
  const CoffeeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MenuItemsView(
      brand: 'coffee',
      title: 'Coffee Diaries',
      subtitle: 'Read-only — name, photo, category, price, availability',
      placeholderBanner:
          'Create / Edit coming soon — full CRUD ships in Module 2.4.',
      emptyMessage: 'No Coffee Diaries items yet.',
      emptyIcon: PhosphorIconsRegular.coffee,
    );
  }
}
