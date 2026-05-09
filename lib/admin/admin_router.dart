import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'announcements/announcement_edit_screen.dart';
import 'announcements/announcements_list_screen.dart';
import 'coupons/coupon_edit_screen.dart';
import 'coupons/coupons_list_screen.dart';
import 'audit/audit_log_screen.dart';
import 'birthday_crm/birthday_crm_screen.dart';
import 'catalog/catalog_index_screen.dart';
import 'catalog/coffee_list_screen.dart';
import 'catalog/combo_edit_screen.dart';
import 'catalog/combos_list_screen.dart';
import 'catalog/fit_categories_screen.dart';
import 'catalog/fit_list_screen.dart';
import 'catalog/fit_template_edit_screen.dart';
import 'catalog/fit_waitlist_screen.dart';
import 'catalog/menu_item_edit_screen.dart';
import 'config/config_screen.dart';
import 'content/content_index_screen.dart';
import 'content/hero_cards_screen.dart';
import 'content/hero_quests_screen.dart';
import 'content/stage_perks_screen.dart';
import 'content/reflection_moments_screen.dart';
import 'customers/customer_detail_screen.dart';
import 'customers/customers_screen.dart';
import 'live_ops/live_ops_screen.dart';
import 'login_screen.dart';
import 'packages/package_edit_screen.dart';
import 'packages/packages_list_screen.dart';
import 'providers/admin_auth_provider.dart';
import 'refunds/refunds_queue_screen.dart';
import 'shell.dart';
import 'stubs/coming_soon_screen.dart';
import 'users/users_screen.dart';
import 'workshops/workshop_edit_screen.dart';
import 'workshops/workshops_list_screen.dart';

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
          // Module 2.1 — view-only list screens (CRUD lands in 2.2 / 2.4 / 2.5).
          GoRoute(
            path: '/admin/workshops',
            builder: (_, __) => const WorkshopsListScreen(),
          ),
          GoRoute(
            path: '/admin/workshops/new',
            builder: (_, __) => const WorkshopEditScreen(),
          ),
          GoRoute(
            path: '/admin/workshops/:id/edit',
            builder: (_, state) =>
                WorkshopEditScreen(workshopId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/catalog',
            builder: (_, __) => const CatalogIndexScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/coffee',
            builder: (_, __) => const CoffeeListScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/coffee/new',
            builder: (_, state) => MenuItemEditScreen(
              menuId: state.uri.queryParameters['menu_id'],
            ),
          ),
          GoRoute(
            path: '/admin/catalog/coffee/:id/edit',
            builder: (_, state) =>
                MenuItemEditScreen(itemId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/catalog/fit',
            builder: (_, __) => const FitListScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/fit/categories',
            builder: (_, __) => const FitCategoriesScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/fit/waitlist',
            builder: (_, __) => const FitWaitlistScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/fit/template/new',
            builder: (_, __) => const FitTemplateEditScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/fit/template/:id/edit',
            builder: (_, state) =>
                FitTemplateEditScreen(templateId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/catalog/combos',
            builder: (_, __) => const CombosListScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/combos/new',
            builder: (_, __) => const ComboEditScreen(),
          ),
          GoRoute(
            path: '/admin/catalog/combos/:id/edit',
            builder: (_, state) =>
                ComboEditScreen(comboId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/packages',
            builder: (_, __) => const PackagesListScreen(),
          ),
          GoRoute(
            path: '/admin/packages/new',
            builder: (_, __) => const PackageEditScreen(),
          ),
          GoRoute(
            path: '/admin/packages/:id/edit',
            builder: (_, state) =>
                PackageEditScreen(packageId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/announcements',
            builder: (_, __) => const AnnouncementsListScreen(),
          ),
          GoRoute(
            path: '/admin/announcements/new',
            builder: (_, __) => const AnnouncementEditScreen(),
          ),
          GoRoute(
            path: '/admin/announcements/:id/edit',
            builder: (_, state) =>
                AnnouncementEditScreen(id: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/coupons',
            builder: (_, __) => const CouponsListScreen(),
          ),
          GoRoute(
            path: '/admin/coupons/new',
            builder: (_, __) => const CouponEditScreen(),
          ),
          GoRoute(
            path: '/admin/coupons/:id/edit',
            builder: (_, state) =>
                CouponEditScreen(id: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/content',
            builder: (_, __) => const ContentIndexScreen(),
          ),
          GoRoute(
            path: '/admin/content/reflection-moments',
            builder: (_, __) => const ReflectionMomentsScreen(),
          ),
          GoRoute(
            path: '/admin/content/hero-cards',
            builder: (_, __) => const HeroCardsScreen(),
          ),
          GoRoute(
            path: '/admin/content/stage-perks',
            builder: (_, __) => const StagePerksScreen(),
          ),
          GoRoute(
            path: '/admin/content/hero-quests',
            builder: (_, __) => const HeroQuestsScreen(),
          ),
          // Stubs.
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
