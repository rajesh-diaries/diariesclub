import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/adventure/adventure_screen.dart';
import '../../features/adventure/per_trait_detail_screen.dart';
import '../../features/auth/otp_verify_screen.dart';
import '../../features/auth/phone_entry_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/birthday/birthday_packages_screen.dart';
import '../../features/birthday/package_detail_screen.dart';
import '../../features/birthday/reservation_status_screen.dart';
import '../../features/club/club_screen.dart';
import '../../features/club/fit_builder_screen.dart';
import '../../features/club/order_tracking_screen.dart';
import '../../features/club/providers/pending_club_tab_provider.dart';
import '../../features/club/workshop_detail_screen.dart';
import '../../features/force_update/force_update_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/add_child_screen.dart';
import '../../features/onboarding/child_details_screen.dart';
import '../../features/onboarding/family_name_screen.dart';
import '../../features/onboarding/hero_pick_screen.dart';
import '../../features/onboarding/welcome_manifesto_screen.dart';
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
import '../../features/profile/profile_screen.dart';
import '../../features/profile/referral_details_screen.dart';
import '../../features/profile/wallet_history_screen.dart';
import '../../features/gamification/card_unboxing_screen.dart';
import '../../features/gamification/reflection_screen.dart';
import '../../features/reactivation/reactivation_screen.dart';
import '../../features/sessions/session_detail_screen.dart';
import '../../features/sessions/session_qr_screen.dart';
import '../../features/sessions/session_start_screen.dart';
import '../notifications/fcm_lifecycle_provider.dart';
import '../notifications/fcm_setup.dart';
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
    // Listen to BOTH auth state changes AND pending FCM deep links so
    // a notification tap re-runs `redirect` and consumes the link from
    // anywhere in the app (not just home_screen). See _onMessageOpenedApp.
    refreshListenable: Listenable.merge(
      [_AuthListenable(ref), pendingFcmDeepLinkNotifier],
    ),
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
      debugPrint('[ROUTER] redirect loc=$loc familyId=$familyId');
      if (familyId == null && !_isPublic(loc)) {
        debugPrint('[ROUTER] → redirecting to /auth/phone');
        return '/auth/phone';
      }

      // 3) Pending FCM deep link. A notification tap stashes the target
      // path on pendingFcmDeepLinkNotifier (see _onMessageOpenedApp).
      // Consume it here so the user lands on the right screen regardless
      // of which tab they were on when they tapped.
      final pendingLink = pendingFcmDeepLink;
      if (familyId != null &&
          pendingLink != null &&
          pendingLink.isNotEmpty &&
          loc != pendingLink) {
        consumePendingFcmDeepLink(); // null out so we don't re-fire
        debugPrint('[ROUTER] consuming FCM deep link → $pendingLink');
        return pendingLink;
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
        path: '/onboarding/welcome',
        name: 'onboarding_welcome',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final revisit = state.uri.queryParameters['revisit'] == '1';
          return WelcomeManifestoScreen(isRevisit: revisit);
        },
      ),
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
      // Notification deep-link aliases. Server-pushed notifications
      // (referral conversions, top-up confirmations) embed '/wallet' as
      // their deep_link; this redirect lands the customer on the real
      // wallet history screen.
      GoRoute(
        path: '/wallet',
        redirect: (_, __) => '/profile/wallet-history',
      ),
      // Workshop-published notifications + workshop announcement cards
      // embed '/club/workshops'. There's no dedicated workshops route
      // (the workshops list lives inside the Club tab as tab index 4 —
      // bumped from 3 when the Birthdays tab landed between Combos and
      // Workshops), so we set pendingClubTabProvider before redirecting
      // to /club — ClubScreen listens for that and animates to the
      // Workshops tab.
      GoRoute(
        path: '/club/workshops',
        redirect: (context, _) {
          ProviderScope.containerOf(context)
              .read(pendingClubTabProvider.notifier)
              .state = 4;
          return '/club';
        },
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
      // /birthday is now the packages screen directly — the old discovery
      // hop (interest radio + "see packages" CTA) was a redundant screen
      // between the home card and the actual content.
      GoRoute(
        path: '/birthday',
        name: 'birthday_packages',
        builder: (context, state) => const BirthdayPackagesScreen(),
      ),
      GoRoute(
        path: '/birthday/packages',
        redirect: (_, __) => '/birthday',
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
      GoRoute(
        path: '/session/:sessionId',
        name: 'session_detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => SessionDetailScreen(
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
      GoRoute(
        path: '/club/fit/builder/:templateId',
        name: 'club_fit_builder',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          // When opened from a combo with a linked FIT template (Option B),
          // the caller passes a FitBuilderComboContext via state.extra so
          // the builder knows to render combo-mode UI and pop with the
          // selections instead of writing the cart directly.
          final extra = state.extra;
          return FitBuilderScreen(
            templateId: state.pathParameters['templateId']!,
            comboContext:
                extra is FitBuilderComboContext ? extra : null,
          );
        },
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

/// Bridges Riverpod's currentFamilyIdProvider to GoRouter's
/// refreshListenable so sign-in/sign-out re-runs the redirect.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    debugPrint('[AUTH-LISTEN] constructed');
    _sub = _ref.listen(
      currentFamilyIdProvider,
      (prev, next) {
        debugPrint('[AUTH-LISTEN] $prev → $next');
        notifyListeners();
      },
      fireImmediately: false,
    );
  }
  final Ref _ref;
  late final ProviderSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
