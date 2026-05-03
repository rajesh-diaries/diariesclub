import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/adventure/adventure_screen.dart';
import '../../features/auth/auth_screens.dart';
import '../../features/birthday/birthday_screens.dart';
import '../../features/club/club_screen.dart';
import '../../features/force_update/force_update_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screens.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reactivation/reactivation_screen.dart';
import '../../features/recap/reflection_screen.dart';
import '../../features/session/pre_book_screen.dart';
import '../../features/wall_of_legends/wall_of_legends_screen.dart';
import '../providers/app_version_provider.dart';
import '../widgets/error_screen.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// GoRouter wired to Riverpod for auth + version-gate redirects.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => FriendlyErrorScreen(
      code: 'E-ROUTE',
      userMessage: 'Page not found',
      technicalDetails: state.error?.toString(),
    ),
    redirect: (context, state) {
      // Force-update gate. Read the cached value; if the future is still
      // loading we don't redirect (avoids flashing the gate before data lands).
      final version = ref.read(appVersionStatusProvider).valueOrNull;
      final isOnUpdate = state.matchedLocation == '/update-required';
      if (version?.status == AppVersionStatus.forceUpdate && !isOnUpdate) {
        return '/update-required';
      }
      if (version?.status != AppVersionStatus.forceUpdate && isOnUpdate) {
        return '/home';
      }
      // Auth + onboarding gates wired in Session 4.
      return null;
    },
    routes: [
      // ── Auth (Session 4) ──────────────────────────────────────────────
      GoRoute(
        path: '/auth/phone',
        name: 'auth_phone',
        builder: (context, state) => const PhoneAuthScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        name: 'auth_otp',
        builder: (context, state) => const OtpScreen(),
      ),

      // ── Onboarding (Session 4) ────────────────────────────────────────
      GoRoute(
        path: '/onboarding/name',
        name: 'onboarding_name',
        builder: (context, state) => const OnboardingNameScreen(),
      ),
      GoRoute(
        path: '/onboarding/child',
        name: 'onboarding_child',
        builder: (context, state) => const OnboardingChildScreen(),
      ),

      // ── Force-update gate ─────────────────────────────────────────────
      GoRoute(
        path: '/update-required',
        name: 'force_update',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ForceUpdateScreen(),
      ),

      // ── Reactivation deep link from SMS install ───────────────────────
      GoRoute(
        path: '/welcome-back',
        name: 'reactivation_welcome',
        builder: (context, state) => const ReactivationWelcomeScreen(),
      ),

      // ── Birthday funnel ───────────────────────────────────────────────
      GoRoute(
        path: '/birthday',
        name: 'birthday_discovery',
        builder: (context, state) => const BirthdayDiscoveryScreen(),
      ),
      GoRoute(
        path: '/birthday/packages',
        name: 'birthday_packages',
        builder: (context, state) => const BirthdayPackagesScreen(),
      ),
      GoRoute(
        path: '/birthday/reserve/:packageId',
        name: 'birthday_reserve',
        builder: (context, state) => BirthdayReserveScreen(
          packageId: state.pathParameters['packageId']!,
        ),
      ),
      GoRoute(
        path: '/birthday/status/:reservationId',
        name: 'birthday_status',
        builder: (context, state) => BirthdayStatusScreen(
          reservationId: state.pathParameters['reservationId']!,
        ),
      ),
      GoRoute(
        path: '/birthday/album/:reservationId',
        name: 'birthday_album',
        builder: (context, state) => BirthdayAlbumScreen(
          reservationId: state.pathParameters['reservationId']!,
        ),
      ),

      // ── Session pre-booking ───────────────────────────────────────────
      GoRoute(
        path: '/session/pre-book',
        name: 'session_pre_book',
        builder: (context, state) => const SessionPreBookScreen(),
      ),

      // ── Wall of Legends ───────────────────────────────────────────────
      GoRoute(
        path: '/wall-of-legends',
        name: 'wall_of_legends',
        builder: (context, state) => const WallOfLegendsScreen(),
      ),

      // ── Reflection (entered from Hero Recap card tap) ─────────────────
      GoRoute(
        path: '/reflection/:sessionId',
        name: 'reflection',
        builder: (context, state) =>
            ReflectionScreen(sessionId: state.pathParameters['sessionId']!),
      ),

      // ── Bottom-nav shell with 4 main tabs ─────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/club',
                name: 'club',
                builder: (context, state) => const ClubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/adventure',
                name: 'adventure',
                builder: (context, state) => const AdventureScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
