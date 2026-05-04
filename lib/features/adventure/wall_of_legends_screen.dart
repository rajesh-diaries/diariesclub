import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Wall of Legends — placeholder for v1.
///
/// The `wall_of_legends_daily` table is in the supabase_realtime
/// publication (added in 0013), so once Session 13's daily aggregation
/// cron starts populating it, this screen can light up by swapping the
/// placeholder for the real list. The route is wired now so QA can
/// reach it from the AppBar action even before the data lands.
class WallOfLegendsScreen extends StatelessWidget {
  const WallOfLegendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wall of Legends'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  PhosphorIconsFill.trophy,
                  color: AppColors.gold,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Coming soon',
                  style: AppTextStyles.h2(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Daily highlights from Diaries Club — anonymised proud '
                  'moments from the community.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
