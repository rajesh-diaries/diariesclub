import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'coffee_menu_tab.dart';
import 'combos_tab.dart';
import 'fit_menu_tab.dart';
import 'providers/cart_provider.dart';
import 'widgets/cart_sheet.dart';
import 'workshops_tab.dart';

/// Tab 2 — Club. Top tabs: Coffee | FIT | Combos | Workshops. Bag icon
/// upper right opens the cart sheet (modal).
class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(cartItemCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Club'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Bag',
            onPressed: _openCart,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  PhosphorIconsRegular.shoppingBag,
                  color: AppColors.navy,
                  size: 26,
                ),
                if (count > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Cafe'),
            Tab(text: 'FIT'),
            Tab(text: 'Combos'),
            Tab(text: 'Workshops'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          CoffeeMenuTab(),
          FitMenuTab(),
          CombosTab(),
          WorkshopsTab(),
        ],
      ),
    );
  }
}
