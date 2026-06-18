import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'birthdays_tab.dart';
import 'coffee_menu_tab.dart';
import 'combos_tab.dart';
import 'fit_menu_tab.dart';
import 'providers/club_search_provider.dart';
import 'providers/pending_club_tab_provider.dart';
import 'widgets/club_cart_bar.dart';
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

  @override
  Widget build(BuildContext context) {
    // Honour one-shot tab requests (e.g. Home's "Order food" card forces
    // Cafe, /club/workshops redirect sets index 3). The first-mount case
    // — where the value was set BEFORE this screen built — is handled
    // by the post-frame callback in initState() above; this listener
    // covers all subsequent changes.
    ref.listen<int?>(pendingClubTabProvider, (_, next) => _applyPendingTab(next));

    return Scaffold(
      appBar: AppBar(
        title: const _ClubSearchBar(),
        automaticallyImplyLeading: false,
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
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: const [
              CoffeeMenuTab(),
              FitMenuTab(),
              CombosTab(),
              BirthdaysTab(),
              WorkshopsTab(),
            ],
          ),
          AnimatedBuilder(
            animation: _tab,
            builder: (_, __) {
              final showCart = _tab.index <= 2; // Cafe, FIT, Combos only
              return Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: ClubCartBar(visible: showCart),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ClubSearchBar extends ConsumerStatefulWidget {
  const _ClubSearchBar();

  @override
  ConsumerState<_ClubSearchBar> createState() => _ClubSearchBarState();
}

class _ClubSearchBarState extends ConsumerState<_ClubSearchBar> {
  late final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textAlignVertical: TextAlignVertical.center,
      style: AppTextStyles.body(context),
      decoration: InputDecoration(
        hintText: 'Search Cafe, FIT, Combos...',
        hintStyle: AppTextStyles.body(
          context,
          color: AppColors.lightTextSecondary,
        ),
        prefixIcon: const Icon(
          PhosphorIconsRegular.magnifyingGlass,
          color: AppColors.lightTextSecondary,
          size: 20,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(
                PhosphorIconsRegular.x,
                color: AppColors.lightTextSecondary,
                size: 18,
              ),
              onPressed: () {
                _controller.clear();
                ref.read(clubSearchQueryProvider.notifier).state = '';
              },
            );
          },
        ),
        filled: true,
        fillColor: AppColors.lightSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      onChanged: (value) {
        ref.read(clubSearchQueryProvider.notifier).state = value.trim().toLowerCase();
      },
    );
  }
}
