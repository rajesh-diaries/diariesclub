import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/adventure/adventure_screen.dart';
import '../../features/adventure/per_trait_detail_screen.dart';
import '../../features/adventure/wall_of_legends_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/auth/phone_entry_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/birthday/birthday_album_screen.dart';
import '../../features/birthday/birthday_discovery_screen.dart';
import '../../features/birthday/birthday_packages_screen.dart';
import '../../features/birthday/package_detail_screen.dart';
import '../../features/birthday/reservation_status_screen.dart';
import '../../features/club/club_screen.dart';
import '../../features/club/order_tracking_screen.dart';
import '../../features/club/workshop_detail_screen.dart';
import '../../features/force_update/force_update_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/add_child_screen.dart';
import '../../features/onboarding/child_details_screen.dart';
import '../../features/onboarding/family_name_screen.dart';
import '../../features/onboarding/hero_pick_screen.dart';
import '../../features/profile/add_child_screen.dart' as profile_add_child;
import '../../features/profile/delete_account_screen.dart';
import '../../features/profile/edit_child_screen.dart';
import '../../features/profile/farewell_screen.dart';
import '../../features/profile/fcm_debug_screen.dart';
import '../../features/profile/help_screen.dart';
import '../../features/profile/language_screen.dart';
import '../../features/profile/notifications_settings_screen.dart';
import '../../features/profile/past_birthdays_screen.dart';
import '../../features/profile/past_orders_screen.dart';
import '../../features/profile/past_session_detail_screen.dart';
import '../../features/profile/past_sessions_screen.dart';
import '../../features/profile/past_workshops_screen.dart';
import '../../features/profile/pre_booking_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/referral_details_screen.dart';
import '../../features/profile/wallet_history_screen.dart';
import '../../features/gamification/card_unboxing_screen.dart';
import '../../features/gamification/reflection_screen.dart';
import '../../features/reactivation/reactivation_screen.dart';
import '../../features/session/pre_book_screen.dart';
import '../../features/sessions/session_qr_screen.dart';
import '../../features/sessions/session_start_screen.dart';
import '../providers/app_version_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/error_screen.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// Routes the user can hit while signed out. Anything else is redirected to
// /auth/phone by the redirect callback. /farewell is the post-deletion
// landing — by definition the user is signed out by the time they see it.
const _publicPathPrefixes = <String>[
  '/auth/',
  '/update-required',
  '/welcome-back',
  '/farewell',
];

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

      // ── Profile sub-screens (Session 5b) ──────────────────────────────
      GoRoute(
        path: '/profile/add-child',
        name: 'profile_add_child',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const profile_add_child.AddChildScreen(),
      ),
      GoRoute(
        path: '/profile/child/:childId',
        name: 'profile_edit_child',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => EditChildScreen(
          childId: state.pathParameters['childId']!,
        ),
      ),
      GoRoute(
        path: '/profile/referral-details',
        name: 'profile_referral_details',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReferralDetailsScreen(),
      ),
      GoRoute(
        path: '/profile/wallet-history',
        name: 'profile_wallet_history',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WalletHistoryScreen(),
      ),
      GoRoute(
        path: '/profile/pre-book',
        name: 'profile_pre_book',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PreBookingScreen(),
      ),
      GoRoute(
        path: '/profile/sessions',
        name: 'profile_sessions',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PastSessionsScreen(),
      ),
      GoRoute(
        path: '/profile/sessions/:sessionId',
        name: 'profile_session_detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PastSessionDetailScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/profile/orders',
        name: 'profile_orders',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PastOrdersScreen(),
      ),
      GoRoute(
        path: '/profile/workshops',
        name: 'profile_workshops',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PastWorkshopsScreen(),
      ),
      GoRoute(
        path: '/profile/birthdays',
        name: 'profile_birthdays',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PastBirthdaysScreen(),
      ),
      GoRoute(
        path: '/profile/notifications-settings',
        name: 'profile_notifications_settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/language',
        name: 'profile_language',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/profile/help',
        name: 'profile_help',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HelpScreen(),
      ),
      // Dev-only FCM debug. The screen self-gates on F.isDev so this
      // route is harmless if hit on prod (renders a "dev only" stub).
      GoRoute(
        path: '/profile/fcm-debug',
        name: 'profile_fcm_debug',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FcmDebugScreen(),
      ),
      GoRoute(
        path: '/profile/delete-account',
        name: 'profile_delete_account',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/farewell',
        name: 'farewell',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FarewellScreen(),
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
        builder: (context, state) => PackageDetailScreen(
          packageId: state.pathParameters['packageId']!,
          triggeredBy: state.uri.queryParameters['trigger'],
        ),
      ),
      GoRoute(
        path: '/birthday/status/:reservationId',
        name: 'birthday_status',
        builder: (context, state) => ReservationStatusScreen(
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

      // ── Reflection (entered from Hero Recap card tap) ─────────────────
      GoRoute(
        path: '/reflection/:sessionId',
        name: 'reflection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ReflectionScreen(sessionId: state.pathParameters['sessionId']!),
      ),

      // ── Hero card unboxing (entered from healthy_bite_distribute) ─────
      GoRoute(
        path: '/cards/unbox/:collectionId',
        name: 'card_unbox',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CardUnboxingScreen(
          collectionId: state.pathParameters['collectionId']!,
        ),
      ),

      // ── Adventure: per-trait detail + Wall of Legends (Session 8) ─────
      GoRoute(
        path: '/adventure/trait/:childId/:hero',
        name: 'adventure_trait_detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PerTraitDetailScreen(
          childId: state.pathParameters['childId']!,
          hero: state.pathParameters['hero']!,
        ),
      ),
      GoRoute(
        path: '/adventure/wall-of-legends',
        name: 'adventure_wall_of_legends',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WallOfLegendsScreen(),
      ),

      // ── Club: order tracking + workshop detail (Session 7) ────────────
      GoRoute(
        path: '/club/order/:orderId',
        name: 'club_order_tracking',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => OrderTrackingScreen(
          orderId: state.pathParameters['orderId']!,
        ),
      ),
      GoRoute(
        path: '/club/workshop/:workshopId',
        name: 'club_workshop_detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => WorkshopDetailScreen(
          workshopId: state.pathParameters['workshopId']!,
        ),
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
