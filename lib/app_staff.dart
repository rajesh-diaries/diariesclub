import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_theme_mode_provider.dart';
import 'core/theme/app_theme.dart';
import 'staff/staff_router.dart';

/// Staff app shell. Lives at the root of the staff flavor; identical
/// theme/localisation wiring as DiariesClubApp but routes through the
/// staff-only router and clamps text scale tighter (tablet KDS cards).
class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final router = ref.watch(staffRouterProvider);

    // BUG-031 v1.1 investigation move #1: dropped the MaterialApp.router
    // builder MediaQuery wrapper. The wrapper rebuilds on every router
    // child swap and re-wraps Navigator in a fresh MediaQuery, which
    // can re-register MouseRegions whose hit-test paths invalidate
    // continuously on web. If staff home action taps now fire, the
    // textScaler clamp belongs in a different layer (per-screen, or
    // applied via Theme); for now we live with system textScaler.
    return MaterialApp.router(
      title: 'Diaries Club Staff',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
