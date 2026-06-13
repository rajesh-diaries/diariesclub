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
import '../../core/widgets/skeleton_card.dart';
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

class _WelcomeEntry {
  final String sessionId;
  final String childName;
  final String? favouriteHero;

  const _WelcomeEntry({
    required this.sessionId,
    required this.childName,
    this.favouriteHero,
  });
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ProviderSubscription<AsyncValue<HomeState>>? _sub;

  // Track which sessions have already shown the welcome overlay so we
  // don't greet the same session twice on rebuilds.
  final _greetedSessionIds = <String>{};

  // Queue of fresh sessions waiting for the welcome overlay.
  final _welcomeQueue = <_WelcomeEntry>[];

  // Currently showing welcome overlay (null = none).
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

  /// Detects all sessions that started within the last 15s and haven't
  /// been greeted yet. Returns a list of welcome entries.
  List<_WelcomeEntry> _freshSessionsToGreet(
    List<Map<String, dynamic>> sessions,
  ) {
    final now = DateTime.now();
    final children =
        ref.read(familyChildrenProvider).valueOrNull ?? const [];
    final result = <_WelcomeEntry>[];

    for (final s in sessions) {
      final id = s['id'] as String?;
      if (id == null || _greetedSessionIds.contains(id)) continue;

      final startedAtStr = s['started_at'] as String?;
      if (startedAtStr == null) continue;
      final startedAt = DateTime.tryParse(startedAtStr);
      if (startedAt == null) continue;

      // Only greet sessions that started in the last 15 seconds.
      // 5 minutes was too long — old sessions re-triggered on rebuilds.
      if (now.difference(startedAt).inSeconds > 15) continue;

      final childId = s['child_id'] as String?;
      if (childId == null) continue;

      final child = children.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id'] == childId,
            orElse: () => null,
          );
      if (child == null) continue;

      result.add(_WelcomeEntry(
        sessionId: id,
        childName: child['name'] as String? ?? '',
        favouriteHero: child['favourite_hero'] as String?,
      ));
    }
    return result;
  }

  void _onWelcomeDismissed() {
    final id = _welcomingSessionId;
    if (id != null) _greetedSessionIds.add(id);

    // If there are more queued welcomes, pop the next one immediately.
    if (_welcomeQueue.isNotEmpty) {
      final next = _welcomeQueue.removeAt(0);
      setState(() {
        _welcomingSessionId = next.sessionId;
        _welcomeChildName = next.childName;
        _welcomeFavouriteHero = next.favouriteHero;
      });
      return;
    }

    setState(() {
      _welcomingSessionId = null;
      _welcomeChildName = '';
      _welcomeFavouriteHero = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeStateProvider);
    final activeSessions =
        ref.watch(activeSessionsProvider).valueOrNull ?? const [];

    // Trigger welcome overlay for freshly-started sessions.
    if (_welcomingSessionId == null) {
      final freshList = _freshSessionsToGreet(activeSessions);
      if (freshList.isNotEmpty) {
        // Start with the first, queue the rest.
        final first = freshList.first;
        final rest = freshList.skip(1).toList();
        _welcomeQueue.addAll(rest);
        setState(() {
          _welcomingSessionId = first.sessionId;
          _welcomeChildName = first.childName;
          _welcomeFavouriteHero = first.favouriteHero;
        });
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
        return const SkeletonList(itemCount: 4);
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
              key: ValueKey(_welcomingSessionId),
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
      body: SafeArea(child: body),
    );
  }
}
