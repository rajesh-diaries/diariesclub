import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_admin.dart';
import 'app_staff.dart';
import 'core/providers/app_theme_mode_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'flavors.dart';

class DiariesClubApp extends ConsumerWidget {
  const DiariesClubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Three apps share bootstrap + Supabase init; the widget tree branches
    // here. Admin checked first because admin flavors imply web build, and
    // we want a hard fast-path before the customer router boots.
    if (F.isAdmin) return const AdminApp();
    if (F.isStaff) return const StaffApp();

    final themeMode = ref.watch(appThemeModeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Diaries Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // Indian locale baseline.
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Clamp Dynamic Type to 1.5× so layouts don't shatter at extreme sizes.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.5),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
