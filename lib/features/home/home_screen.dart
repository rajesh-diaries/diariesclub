import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/fcm_lifecycle_provider.dart';
import '../../core/providers/home_state_provider.dart';
import '../../core/providers/recent_activity_provider.dart';
import '../../core/widgets/error_screen.dart';
import 'home_app_bar.dart';
import 'views/idle_home_view.dart';
import 'views/post_session_home_view.dart';
import 'views/session_home_view.dart';

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

  @override
  void initState() {
    super.initState();
    // Whenever the home state's underlying sessions stream emits, we may
    // also need to refresh the recent-activity view (a session row that
    // just completed should appear there). Cheap to invalidate; the view
    // is small.
    _sub = ref.listenManual<AsyncValue<HomeState>>(
      homeStateProvider,
      (_, __) => ref.invalidate(recentActivityProvider),
    );

    // Cold-start FCM tap → consume the deep link saved by FcmSetup once
    // we've reached Home (the safe, signed-in landing point).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deepLink = consumePendingFcmDeepLink();
      if (deepLink != null && mounted) {
        context.push(deepLink);
      }
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeStateProvider);

    debugPrint('[BUG-038] HomeScreen.build state=$state');
    return Scaffold(
      appBar: const HomeAppBar(),
      body: state.when(
        data: (s) {
          debugPrint('[BUG-038] HomeScreen state.data = ${s.runtimeType}');
          if (s is HomeStatePostSession) {
            debugPrint('[BUG-039] HomeScreen entering PostSession branch '
                'sessionId=${s.session['id']}');
          }
          return switch (s) {
            HomeStateIdle() => const IdleHomeView(),
            HomeStateInSession(:final session) =>
              SessionHomeView(session: session),
            HomeStatePostSession(:final session) =>
              PostSessionHomeView(session: session),
          };
        },
        loading: () {
          debugPrint('[BUG-038] HomeScreen state.loading');
          return const Center(child: CircularProgressIndicator());
        },
        error: (e, st) {
          // BUG-033 diagnostic: surface the actual error so we can see
          // what's failing instead of just "E-HOME". Console + UI.
          debugPrint('[E-HOME] homeStateProvider error: $e');
          debugPrint('[E-HOME] stack: $st');
          return FriendlyErrorScreen(
            code: 'E-HOME',
            userMessage: "Couldn't load home",
            technicalDetails: e.toString(),
          );
        },
      ),
    );
  }
}
