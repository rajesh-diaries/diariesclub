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
    debugPrint('[BUG-023-V2] StaffApp.build()');
    final themeMode = ref.watch(appThemeModeProvider);
    final router = ref.watch(staffRouterProvider);

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
      // Tablets render at higher density; staff don't need the same Dynamic
      // Type headroom parents do. 1.3× cap keeps KDS cards readable without
      // breaking 4-up grids.
      builder: (context, child) {
        debugPrint(
          '[BUG-023-V2] StaffApp.builder(child=${child?.runtimeType})',
        );
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
