import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/adventure/adventure_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/auth/phone_entry_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/birthday/birthday_screens.dart';
import '../../features/club/club_screen.dart';
import '../../features/force_update/force_update_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/add_child_screen.dart';
import '../../features/onboarding/child_details_screen.dart';
import '../../features/onboarding/family_name_screen.dart';
import '../../features/onboarding/hero_pick_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reactivation/reactivation_screen.dart';
import '../../features/recap/reflection_screen.dart';
import '../../features/session/pre_book_screen.dart';
import '../../features/sessions/session_qr_screen.dart';
import '../../features/sessions/session_start_screen.dart';
import '../../features/wall_of_legends/wall_of_legends_screen.dart';
import '../providers/app_version_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/error_screen.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// Routes the user can hit while signed out. Anything else is redirected to
// /auth/phone by the redirect callback.
const _publicPathPrefixes = <String>['/auth/', '/update-required', '/welcome-back'];

bool _isPublic(String location) {
  if (location == '/') return true; // Splash always public.
  for (final p in _publicPathPrefixes) {
    if (location == p || location.startsWith(p)) return true;
  }
  return false;
}

/// GoRouter wired to Riverpod for force-update + auth redirects.
///
/// Splash (`/`) does the smart routing on cold start; this redirect just
/// keeps direct navigation safe (e.g. signed-out user deep-linking to
/// `/home`).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => FriendlyErrorScreen(
      code: 'E-ROUTE',
      userMessage: 'Page not found',
      technicalDetails: state.error?.toString(),
    ),
    redirect: (context, state) {
      // 1) Force-update gate.
      final version = ref.read(appVersionStatusProvider).valueOrNull;
      final isOnUpdate = state.matchedLocation == '/update-required';
      if (version?.status == AppVersionStatus.forceUpdate && !isOnUpdate) {
        return '/update-required';
      }
      if (version?.status != AppVersionStatus.forceUpdate && isOnUpdate) {
        return '/';
      }

      // 2) Auth gate. Signed-out + protected route → /auth/phone.
      final familyId = ref.read(currentFamilyIdProvider);
      final loc = state.matchedLocation;
      if (familyId == null && !_isPublic(loc)) {
        return '/auth/phone';
      }

      return null;
    },
    routes: [
      // ── Splash (initial) ──────────────────────────────────────────────
      GoRoute(
        path: '/',
        name: 'splash',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Auth (Session 4) ──────────────────────────────────────────────
      GoRoute(
        path: '/auth/phone',
        name: 'auth_phone',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PhoneEntryScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        name: 'auth_otp',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OtpVerifyScreen(),
      ),

      // ── Onboarding (Session 4) ────────────────────────────────────────
      GoRoute(
        path: '/onboarding/family-name',
        name: 'onboarding_family_name',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FamilyNameScreen(),
      ),
      GoRoute(
        path: '/onboarding/add-child',
        name: 'onboarding_add_child',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AddChildScreen(),
      ),
      GoRoute(
        path: '/onboarding/child-details',
        name: 'onboarding_child_details',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ChildDetailsScreen(),
      ),
      GoRoute(
        path: '/onboarding/hero-pick',
        name: 'onboarding_hero_pick',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HeroPickScreen(),
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

      // ── Session lifecycle (Session 5) ─────────────────────────────────
      GoRoute(
        path: '/session/start',
        name: 'session_start',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SessionStartScreen(),
      ),
      GoRoute(
        path: '/session/qr/:sessionId',
        name: 'session_qr',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => SessionQrScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
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
