import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_router.dart';
import 'core/providers/app_theme_mode_provider.dart';
import 'core/theme/app_theme.dart';

/// Admin web shell. Branches off from DiariesClubApp when F.isAdmin.
/// Desktop-first layout (sidebar at >=900px, drawer below). Text scale
/// stays at 1.0× — admin density beats accessibility headroom on a
/// laptop screen.
class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final router = ref.watch(adminRouterProvider);

    return MaterialApp.router(
      title: 'Diaries Club Admin',
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
