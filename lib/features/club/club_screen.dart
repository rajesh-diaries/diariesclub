import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'birthdays_tab.dart';
import 'coffee_menu_tab.dart';
import 'combos_tab.dart';
import 'fit_menu_tab.dart';
import 'providers/cart_provider.dart';
import 'providers/pending_club_tab_provider.dart';
import 'widgets/cart_sheet.dart';
import 'workshops_tab.dart';

/// Tab 2 — Club. Top tabs: Cafe | FIT | Combos | Birthdays | Workshops.
/// Bag icon upper right opens the cart sheet (modal).
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
    _tab = TabController(length: 5, vsync: this);

    // Fire-immediately equivalent for the pending-tab provider.
    // WidgetRef.listen (used in build) doesn't expose fireImmediately the
    // way Ref.listen does, so we read the current value once after the
    // first frame to honour any tab request that landed before this
    // screen mounted (e.g. /club/workshops route redirect setting index 3
    // milliseconds before ClubScreen builds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyPendingTab(ref.read(pendingClubTabProvider));
    });
  }

  /// Animate to the requested tab if it's a valid index, then clear the
  /// pending state so a subsequent plain /club visit lands on the user's
  /// last-viewed tab.
  void _applyPendingTab(int? next) {
    if (next == null) return;
    if (next >= 0 && next < _tab.length) {
      _tab.animateTo(next);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pendingClubTabProvider.notifier).state = null;
    });
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

    // Honour one-shot tab requests (e.g. Home's "Order food" card forces
    // Cafe, /club/workshops redirect sets index 3). The first-mount case
    // — where the value was set BEFORE this screen built — is handled
    // by the post-frame callback in initState() above; this listener
    // covers all subsequent changes.
    ref.listen<int?>(pendingClubTabProvider, (_, next) => _applyPendingTab(next));

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
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.navy,
                        ).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: AppTextStyles.body(
            context,
            color: AppColors.navy,
          ).copyWith(fontWeight: FontWeight.w800),
          unselectedLabelStyle: AppTextStyles.body(
            context,
            color: AppColors.lightTextSecondary,
          ),
          labelColor: AppColors.navy,
          unselectedLabelColor: AppColors.lightTextSecondary,
          indicator: UnderlineTabIndicator(
            borderSide: const BorderSide(
              color: AppColors.gold,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(3),
            insets: const EdgeInsets.symmetric(horizontal: 16),
          ),
          dividerColor: AppColors.lightBorder,
          tabs: const [
            Tab(
              icon: Icon(PhosphorIconsRegular.coffee, size: 18),
              text: 'Cafe',
            ),
            Tab(
              icon: Icon(PhosphorIconsRegular.bowlFood, size: 18),
              text: 'FIT',
            ),
            Tab(
              icon: Icon(PhosphorIconsRegular.gift, size: 18),
              text: 'Combos',
            ),
            Tab(
              icon: Icon(PhosphorIconsRegular.cake, size: 18),
              text: 'Birthdays',
            ),
            Tab(
              icon: Icon(PhosphorIconsRegular.paintBrush, size: 18),
              text: 'Workshops',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.amber,
            height: 30,
            alignment: Alignment.center,
            child: Text(
              'DEBUG tab=${_tab.index}',
              style: const TextStyle(color: Colors.black),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                CoffeeMenuTab(),
                FitMenuTab(),
                CombosTab(),
                BirthdaysTab(),
                WorkshopsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
