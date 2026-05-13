import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'active_sessions_screen.dart';
import 'grant_card_screen.dart';
import 'healthy_bite_screen.dart';
import 'redeem_perk_screen.dart';
import 'kds_screen.dart';
import 'manual_session_screen.dart';
import 'menu_availability_screen.dart';
import 'providers/staff_auth_provider.dart';
import 'qr_scanner_screen.dart';
import 'refund_screen.dart';
import 'scan_success_screen.dart';
import 'shift_close_screen.dart';
import 'staff_home_screen.dart';
import 'staff_pin_change_screen.dart';
import 'tablet_login_screen.dart';
import 'walkin_pos_screen.dart';
import 'workshop_attendance_screen.dart';

/// Router for the staff flavor. Listens to tabletAuthStateProvider so the
/// login redirect runs whenever the tablet signs out (or its device row
/// is revoked from admin web).
final staffRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/staff/home',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final signedIn = ref.read(isTabletSignedInProvider);
      final loc = state.matchedLocation;
      final atLogin = loc == '/staff/login';
      if (!signedIn && !atLogin) return '/staff/login';
      if (signedIn && atLogin) return '/staff/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/staff/login',
        builder: (_, __) => const TabletLoginScreen(),
      ),
      GoRoute(
        path: '/staff/home',
        builder: (_, __) => const StaffHomeScreen(),
      ),
      GoRoute(
        path: '/staff/pin-change',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return StaffPinChangeScreen(
            staffId: extra?['staffId'] as String? ?? '',
            currentPin: extra?['currentPin'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/staff/qr',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return QrScannerScreen(staffId: extra?['staffId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: '/staff/scan-success',
        builder: (_, state) {
          final extra = state.extra is Map
              ? Map<String, dynamic>.from(state.extra! as Map)
              : <String, dynamic>{};
          return ScanSuccessScreen(result: extra);
        },
      ),
      GoRoute(
        path: '/staff/manual',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ManualSessionScreen(
            staffId: extra?['staffId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/staff/sessions',
        builder: (_, __) => const ActiveSessionsScreen(),
      ),
      GoRoute(
        path: '/staff/kds',
        builder: (_, __) => const KdsScreen(),
      ),
      GoRoute(
        path: '/staff/healthy-bite',
        builder: (_, __) => const HealthyBiteScreen(),
      ),
      GoRoute(
        path: '/staff/grant-card',
        builder: (_, __) => const GrantCardScreen(),
      ),
      GoRoute(
        path: '/staff/redeem-perk',
        builder: (_, __) => const RedeemPerkScreen(),
      ),
      GoRoute(
        path: '/staff/menu',
        builder: (_, __) => const MenuAvailabilityScreen(),
      ),
      GoRoute(
        path: '/staff/refund',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return RefundScreen(staffId: extra?['staffId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: '/staff/walkin',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return WalkinPosScreen(
            staffId: extra?['staffId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/staff/shift-close',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ShiftCloseScreen(
            staffId: extra?['staffId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: '/staff/workshops',
        builder: (_, __) => const WorkshopAttendanceScreen(),
      ),
      GoRoute(
        path: '/staff/workshops/:workshopId/attendance',
        builder: (_, state) {
          final extra = state.extra is Map
              ? Map<String, dynamic>.from(state.extra! as Map)
              : <String, dynamic>{};
          return WorkshopRegistrationsScreen(
            workshopId: state.pathParameters['workshopId']!,
            title: extra['title'] as String?,
          );
        },
      ),
      // Stub: full audit-log viewer is admin-web (Session 11). Staff app
      // gets a placeholder so the home tile doesn't 404.
      GoRoute(
        path: '/staff/audit',
        builder: (_, __) => const _AuditPlaceholder(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});

/// Bridges Riverpod's tabletAuthStateProvider to GoRouter's refreshListenable.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen(
      tabletAuthStateProvider,
      (_, __) => notifyListeners(),
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

class _AuditPlaceholder extends StatelessWidget {
  const _AuditPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Per-PIN audit log lives in admin web (Session 11). Coming next.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
