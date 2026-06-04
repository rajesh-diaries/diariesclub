import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/fcm_lifecycle_provider.dart';
import '../../core/notifications/fcm_setup.dart';
import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/providers/home_state_provider.dart';
import '../../core/providers/recent_activity_provider.dart';
import '../../core/widgets/error_screen.dart';
import 'home_app_bar.dart';
import 'views/idle_home_view.dart';
import 'views/multi_session_home_view.dart';
import 'views/post_session_home_view.dart';
import 'widgets/session_welcome_overlay.dart';

/// Tab 1 — Home. The single source of truth for which sub-view to render
/// is `homeStateProvider` (DB-driven). Active vs grace within an open
/// session is computed visually inside the session view.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ProviderSubscription<AsyncValue<HomeState>>? _sub;

  // Track which sessions have already shown the welcome overlay so we
  // don't greet the same session twice on rebuilds.
  final _greetedSessionIds = <String>{};

  // Session ID currently showing the welcome overlay (null = none).
  String? _welcomingSessionId;
  String _welcomeChildName = '';
  String? _welcomeFavouriteHero;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<AsyncValue<HomeState>>(
      homeStateProvider,
      (_, __) => ref.invalidate(recentActivityProvider),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeIfPending();
    });

    pendingFcmDeepLinkNotifier.addListener(_onPendingDeepLinkChanged);
  }

  void _onPendingDeepLinkChanged() => _consumeIfPending();

  void _consumeIfPending() {
    final link = consumePendingFcmDeepLink();
    if (link != null && mounted) {
      context.push(link);
    }
  }

  @override
  void dispose() {
    pendingFcmDeepLinkNotifier.removeListener(_onPendingDeepLinkChanged);
    _sub?.close();
    super.dispose();
  }

  /// Detects any session that started within the last 30s and hasn't
  /// been greeted yet. Returns the child name + hero for the overlay.
  ({String childName, String? favouriteHero})? _freshSessionToGreet(
    List<Map<String, dynamic>> sessions,
  ) {
    final now = DateTime.now();
    for (final s in sessions) {
      final id = s['id'] as String?;
      if (id == null || _greetedSessionIds.contains(id)) continue;

      final startedAtStr = s['started_at'] as String?;
      if (startedAtStr == null) continue;
      final startedAt = DateTime.tryParse(startedAtStr);
      if (startedAt == null) continue;

      // Only greet sessions that started in the last 5 minutes.
      if (now.difference(startedAt).inSeconds > 300) continue;

      final childId = s['child_id'] as String?;
      if (childId == null) continue;

      final children =
          ref.read(familyChildrenProvider).valueOrNull ?? const [];
      final child = children.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id'] == childId,
            orElse: () => null,
          );
      if (child == null) continue;

      return (
        childName: child['name'] as String? ?? '',
        favouriteHero: child['favourite_hero'] as String?,
      );
    }
    return null;
  }

  void _onWelcomeDismissed() {
    final id = _welcomingSessionId;
    setState(() {
      _welcomingSessionId = null;
      _welcomeChildName = '';
      _welcomeFavouriteHero = null;
    });
    if (id != null) _greetedSessionIds.add(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeStateProvider);
    final activeSessions =
        ref.watch(activeSessionsProvider).valueOrNull ?? const [];

    // Trigger welcome overlay for freshly-started sessions.
    if (_welcomingSessionId == null) {
      final greet = _freshSessionToGreet(activeSessions);
      if (greet != null) {
        final freshId = activeSessions
            .firstWhere((s) {
              final startedAt = DateTime.tryParse(
                (s['started_at'] as String?) ?? '',
              );
              return startedAt != null &&
                  DateTime.now().difference(startedAt).inSeconds <= 300;
            }, orElse: () => const <String, dynamic>{})['id']
            ?.toString();
        if (freshId != null) {
          setState(() {
            _welcomingSessionId = freshId;
            _welcomeChildName = greet.childName;
            _welcomeFavouriteHero = greet.favouriteHero;
          });
        }
      }
    }

    Widget body = state.when(
      data: (s) {
        if (activeSessions.isNotEmpty) {
          return const MultiSessionHomeView();
        }
        return switch (s) {
          HomeStateIdle() => const IdleHomeView(),
          HomeStateInSession() => const MultiSessionHomeView(),
          HomeStatePostSession(:final session) =>
            PostSessionHomeView(session: session),
        };
      },
      loading: () {
        return const Center(child: CircularProgressIndicator());
      },
      error: (e, st) {
        debugPrint('[E-HOME] homeStateProvider error: $e');
        debugPrint('[E-HOME] stack: $st');
        return FriendlyErrorScreen(
          code: 'E-HOME',
          userMessage: "Couldn't load home",
          technicalDetails: e.toString(),
        );
      },
    );

    // Layer welcome overlay on top when a fresh session is detected.
    if (_welcomingSessionId != null) {
      body = Stack(
        children: [
          body,
          Positioned.fill(
            child: SessionWelcomeOverlay(
              childName: _welcomeChildName,
              favouriteHero: _welcomeFavouriteHero,
              onDismissed: _onWelcomeDismissed,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: const HomeAppBar(),
      body: body,
    );
  }
}
