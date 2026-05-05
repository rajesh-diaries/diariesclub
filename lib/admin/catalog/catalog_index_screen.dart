import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

/// Hub for the three catalog domains (Coffee / FIT / Combos). Sidebar
/// "Catalog" entry points here; each tile deep-links to its dedicated
/// list screen. Birthday packages live under their own top-level route.
class CatalogIndexScreen extends StatelessWidget {
  const CatalogIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Catalog'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pick a domain to manage. Each surface is currently read-only '
              'in Module 2.1; CRUD ships per-domain in Modules 2.4 (Coffee) '
              'and 2.5 (FIT).',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            const Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _CatalogTile(
                  route: '/admin/catalog/coffee',
                  icon: PhosphorIconsFill.coffee,
                  title: 'Coffee Diaries',
                  subtitle: 'Drinks, snacks, baked goods',
                ),
                _CatalogTile(
                  route: '/admin/catalog/fit',
                  icon: PhosphorIconsFill.barbell,
                  title: 'FIT',
                  subtitle: 'Healthy meals & meal builder (Module 2.5)',
                ),
                _CatalogTile(
                  route: '/admin/catalog/combos',
                  icon: PhosphorIconsFill.gift,
                  title: 'Combos',
                  subtitle: 'Session + menu bundles',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final String route;
  final IconData icon;
  final String title;
  final String subtitle;
  const _CatalogTile({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Material(
        color: AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.gold, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.h3(context)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
