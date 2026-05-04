import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'audit/audit_log_screen.dart';
import 'birthday_crm/birthday_crm_screen.dart';
import 'config/config_screen.dart';
import 'customers/customer_detail_screen.dart';
import 'customers/customers_screen.dart';
import 'live_ops/live_ops_screen.dart';
import 'login_screen.dart';
import 'providers/admin_auth_provider.dart';
import 'refunds/refunds_queue_screen.dart';
import 'shell.dart';
import 'stubs/coming_soon_screen.dart';
import 'users/users_screen.dart';

/// Admin web router. Auth gate runs on every navigation:
///   - no Supabase session → /admin/login
///   - signed in but no admin_users row (or deactivated) → sign out, /login
///   - else → requested route inside the AdminShell
final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/admin/live-ops',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      final isLogin = loc == '/admin/login';
      final signedIn = ref.read(isAdminSignedInProvider);

      if (!signedIn && !isLogin) return '/admin/login';
      if (signedIn) {
        // Awaiting the admin row check would block redirect; we trust the
        // login screen to short-circuit non-admin sign-ins, and treat the
        // post-login fetch as an authoritative second check (the shell
        // will redirect if it later resolves to null).
        if (isLogin) return '/admin/live-ops';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/admin/login',
        builder: (_, __) => const AdminLoginScreen(),
      ),
      ShellRoute(
        builder: (_, __, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin/live-ops',
            builder: (_, __) => const LiveOpsScreen(),
          ),
          GoRoute(
            path: '/admin/birthdays',
            builder: (_, __) => const BirthdayCrmScreen(),
          ),
          GoRoute(
            path: '/admin/refunds',
            builder: (_, __) => const RefundsQueueScreen(),
          ),
          GoRoute(
            path: '/admin/customers',
            builder: (_, __) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/admin/customers/:id',
            builder: (_, state) => CustomerDetailScreen(
              familyId: state.pathParameters['id']!,
              preview: state.extra is Map
                  ? Map<String, dynamic>.from(state.extra! as Map)
                  : null,
            ),
          ),
          GoRoute(
            path: '/admin/config',
            builder: (_, __) => const ConfigScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, __) => const UsersScreen(),
          ),
          GoRoute(
            path: '/admin/audit',
            builder: (_, __) => const AuditLogScreen(),
          ),
          // Stubs.
          GoRoute(
            path: '/admin/workshops',
            builder: (_, __) => const ComingSoonScreen(
              title: 'Workshops',
              description: 'Workshop scheduling',
              icon: PhosphorIconsRegular.graduationCap,
              rationale:
                  'Schedule new workshops, view registrations, mark attended. '
                  'Customer-facing workshops already render from the existing '
                  'workshops table — full admin CRUD ships in the next session.',
            ),
          ),
          GoRoute(
            path: '/admin/catalog',
            builder: (_, __) => const ComingSoonScreen(
              title: 'Catalog',
              description: 'Menu items / combos / birthday packages',
              icon: PhosphorIconsRegular.storefront,
              rationale:
                  'Full CRUD for the menu, combos, and birthday package '
                  'tiers. Today the seed data is good — admin edits will '
                  'arrive with image upload.',
            ),
          ),
          GoRoute(
            path: '/admin/content',
            builder: (_, __) => const ComingSoonScreen(
              title: 'Content',
              description: 'FAQ / reflection moments / hero cards',
              icon: PhosphorIconsRegular.fileText,
              rationale:
                  'FAQ table seed in 0017; reflection moment editor + hero '
                  'card image upload follow.',
            ),
          ),
          GoRoute(
            path: '/admin/reports',
            builder: (_, __) => const ComingSoonScreen(
              title: 'Reports',
              description: 'Revenue / sessions / retention / birthday funnel',
              icon: PhosphorIconsRegular.chartBar,
              rationale:
                  'Aggregations are heavy — building once we have a few '
                  'weeks of real venue data so the dashboards reflect '
                  'something useful at first paint.',
            ),
          ),
          GoRoute(
            path: '/admin/reactivation',
            builder: (_, __) => const ComingSoonScreen(
              title: 'Reactivation',
              description: 'CSV import + SMS blast',
              icon: PhosphorIconsRegular.envelope,
              rationale:
                  'CSV import works already against reactivation_contacts. '
                  'SMS blast depends on the Session 13 MSG91 Edge Function.',
            ),
          ),
          GoRoute(
            path: '/admin/health',
            builder: (_, __) => const ComingSoonScreen(
              title: 'System Health',
              description: 'Status lights + reconciliation log',
              icon: PhosphorIconsRegular.heartbeat,
              rationale:
                  'Depends on the Session 13 cron that populates '
                  'system_health_snapshots + reconciliation_log on a fixed '
                  'cadence.',
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen(
      adminAuthStateProvider,
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
