import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/admin_auth_provider.dart';
import 'admin_buttons.dart';

/// Persistent sidebar for the admin shell. 220px wide on desktop. The 13
/// nav items match the Session 11 spec; stub sections show a small "soon"
/// dot until they're built out.
class AdminSidebar extends ConsumerWidget {
  const AdminSidebar({super.key});

  static const _items = <_NavItemSpec>[
    _NavItemSpec('/admin/live-ops', 'Live Ops', PhosphorIconsRegular.pulse),
    _NavItemSpec('/admin/birthdays', 'Birthday CRM', PhosphorIconsRegular.cake),
    _NavItemSpec('/admin/refunds', 'Refunds', PhosphorIconsRegular.arrowUUpLeft),
    _NavItemSpec('/admin/customers', 'Customers', PhosphorIconsRegular.users),
    _NavItemSpec('/admin/workshops', 'Workshops', PhosphorIconsRegular.graduationCap),
    _NavItemSpec('/admin/catalog', 'Catalog', PhosphorIconsRegular.storefront),
    _NavItemSpec('/admin/packages', 'Packages', PhosphorIconsRegular.cake),
    _NavItemSpec('/admin/announcements', 'Announcements', PhosphorIconsRegular.megaphone),
    _NavItemSpec('/admin/coupons', 'Coupons', PhosphorIconsRegular.ticket),
    _NavItemSpec('/admin/config', 'Config', PhosphorIconsRegular.gear),
    _NavItemSpec('/admin/content', 'Content', PhosphorIconsRegular.fileText),
    _NavItemSpec('/admin/users', 'Users', PhosphorIconsRegular.key),
    _NavItemSpec('/admin/reports', 'Reports', PhosphorIconsRegular.chartBar, isStub: true),
    _NavItemSpec('/admin/reactivation', 'Reactivation', PhosphorIconsRegular.envelope, isStub: true),
    _NavItemSpec('/admin/health', 'System Health', PhosphorIconsRegular.heartbeat, isStub: true),
    _NavItemSpec('/admin/audit', 'Audit Log', PhosphorIconsRegular.scroll),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final admin = ref.watch(currentAdminUserProvider).valueOrNull;

    return Container(
      width: 220,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.shield_moon, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Admin',
                  style: AppTextStyles.h3(context, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),

          // Nav
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                final isActive = currentRoute.startsWith(item.route);
                return _NavRow(
                  item: item,
                  isActive: isActive,
                  onTap: () => context.go(item.route),
                );
              },
            ),
          ),

          const Divider(color: Colors.white24, height: 1),
          // User pill
          if (admin != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.gold,
                    child: Text(
                      ((admin['name'] as String?) ?? '?')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (admin['name'] as String?) ?? '—',
                          style: AppTextStyles.body(
                            context,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          (admin['role'] as String?) ?? '—',
                          style: AppTextStyles.caption(
                            context,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AdminIconButton(
                    icon: Icons.logout,
                    color: Colors.white,
                    size: 20,
                    tooltip: 'Sign out',
                    onPressed: () =>
                        Supabase.instance.client.auth.signOut(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItemSpec {
  final String route;
  final String label;
  final IconData icon;
  final bool isStub;
  const _NavItemSpec(this.route, this.label, this.icon, {this.isStub = false});
}

class _NavRow extends StatelessWidget {
  final _NavItemSpec item;
  final bool isActive;
  final VoidCallback onTap;
  const _NavRow({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.12) : null,
            border: Border(
              left: BorderSide(
                color: isActive ? AppColors.gold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: AppTextStyles.body(context, color: Colors.white),
                ),
              ),
              if (item.isStub)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
