import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/server_clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_card.dart';
import '../../../features/club/providers/pending_club_tab_provider.dart';

/// Provider for active home banners ordered by display_order.
/// Pulls the new scheduling/deep-link fields; visibility filtering happens
/// client-side against the server clock.
final homeBannersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final res = await Supabase.instance.client
        .from('home_banners')
        .select('id, image_url, target_route, type, visible_from, visible_until, alt_text, display_order')
        .eq('is_active', true)
        .order('display_order');
    return List<Map<String, dynamic>>.from(res);
  },
);

/// Auto-sliding promotional banner carousel for the home screen.
///
/// Each banner is a full-bleed image. The creative (copy + CTA) is baked
/// into the image by the designer. If [target_route] is set, tapping the
/// image navigates there and records analytics. If it is null/empty the
/// banner is static (e.g., greetings, alerts).
class HomeBannerCarousel extends ConsumerStatefulWidget {
  const HomeBannerCarousel({super.key});

  @override
  ConsumerState<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends ConsumerState<HomeBannerCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  Timer? _autoAdvance;
  int _currentPage = 0;
  bool _userInteracting = false;

  static const _advanceInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _autoAdvance?.cancel();
    _autoAdvance = Timer.periodic(_advanceInterval, (_) {
      if (!mounted || _userInteracting) return;
      final banners = ref.read(_visibleBannersProvider).valueOrNull ?? [];
      if (banners.length <= 1) return;
      final next = (_currentPage + 1) % banners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  /// Server-clock-aware filter of currently visible banners.
  static bool _isVisible(Map<String, dynamic> b, DateTime now) {
    final from = b['visible_from'] as String?;
    final until = b['visible_until'] as String?;
    if (from != null) {
      final fromDt = DateTime.tryParse(from);
      if (fromDt != null && now.isBefore(fromDt)) return false;
    }
    if (until != null) {
      final untilDt = DateTime.tryParse(until);
      if (untilDt != null && now.isAfter(untilDt)) return false;
    }
    return true;
  }

  void _onBannerTap(Map<String, dynamic> banner) {
    final route = (banner['target_route'] as String?)?.trim();
    final bannerId = banner['id'] as String?;
    if (route == null || route.isEmpty) return;

    _recordTap(bannerId);

    final clubIndex = _clubTabIndexForRoute(route);
    if (clubIndex != null) {
      ref.read(pendingClubTabProvider.notifier).state = clubIndex;
      context.go('/club');
      return;
    }
    context.go(route);
  }

  Future<void> _recordTap(String? bannerId) async {
    if (bannerId == null) return;
    final family = ref.read(currentFamilyProvider).valueOrNull;
    final familyId = family?['id'] as String?;
    try {
      await Supabase.instance.client.from('home_banner_taps').insert({
        'banner_id': bannerId,
        if (familyId != null) 'family_id': familyId,
      });
    } catch (e) {
      debugPrint('[BANNER-TAP] analytics insert failed: $e');
    }
  }

  /// Maps /club sub-routes to the Club tab controller index.
  /// Returns null for non-club routes.
  int? _clubTabIndexForRoute(String route) {
    final normalized = route.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    return switch (normalized) {
      '/club' || '/club/cafe' => 0,
      '/club/fit' => 1,
      '/club/combos' => 2,
      '/club/birthdays' => 3,
      '/club/workshops' => 4,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final offset = ref.watch(serverClockProvider);
    final now = DateTime.now().toUtc().add(offset);

    final bannersAsync = ref.watch(homeBannersProvider);

    return bannersAsync.when(
      loading: () => const SkeletonCard(height: 140, margin: EdgeInsets.symmetric(horizontal: 24)),
      error: (e, _) => BrandedErrorState(
        message: "Couldn't load banners",
        onRetry: () => ref.invalidate(homeBannersProvider),
      ),
      data: (allBanners) {
        final banners = allBanners.where((b) => _isVisible(b, now)).toList();
        if (banners.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _userInteracting = true;
                    _autoAdvance?.cancel();
                  }
                  if (n is ScrollEndNotification) {
                    _userInteracting = false;
                    _startAutoAdvance();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: banners.length,
                  padEnds: true,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) {
                    final banner = banners[i];
                    return _BannerPage(
                      banner: banner,
                      isCurrent: i == _currentPage,
                      onTap: () => _onBannerTap(banner),
                    );
                  },
                ),
              ),
              if (banners.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(banners.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A computed provider that exposes the same visible banners the UI uses.
/// Useful for the auto-advance timer and for tests.
final _visibleBannersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final offset = ref.watch(serverClockProvider);
    final now = DateTime.now().toUtc().add(offset);
    final all = await ref.watch(homeBannersProvider.future);
    return all.where((b) {
      final from = b['visible_from'] as String?;
      final until = b['visible_until'] as String?;
      if (from != null && now.isBefore(DateTime.parse(from))) return false;
      if (until != null && now.isAfter(DateTime.parse(until))) return false;
      return true;
    }).toList();
  },
);

class _BannerPage extends StatelessWidget {
  final Map<String, dynamic> banner;
  final bool isCurrent;
  final VoidCallback onTap;

  const _BannerPage({
    required this.banner,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = banner['image_url'] as String? ?? '';
    final altText = banner['alt_text'] as String? ?? '';
    final route = (banner['target_route'] as String?)?.trim();
    final type = banner['type'] as String? ?? 'promo';
    final clickable = route != null && route.isNotEmpty;

    final borderColor = switch (type) {
      'urgent' => AppColors.adminRed,
      _ => Colors.transparent,
    };

    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: AppColors.lightBorder,
              ),
              errorWidget: (context, url, error) => Container(
                color: AppColors.lightBorder,
                child: const Icon(
                  PhosphorIconsRegular.image,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            )
          : Container(color: AppColors.navy),
    );

    if (clickable) {
      image = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: image,
        ),
      );
    }

    if (borderColor != Colors.transparent) {
      image = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: image,
      );
    }

    if (altText.isNotEmpty) {
      image = Semantics(
        label: altText,
        child: image,
      );
    }

    if (isCurrent) {
      image = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          boxShadow: [kHomeCardShadow(context)],
        ),
        child: image,
      );
    }

    return AnimatedScale(
      scale: isCurrent ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 250),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: image,
      ),
    );
  }
}

