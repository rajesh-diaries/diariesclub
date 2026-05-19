import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_admin.dart';
import 'app_staff.dart';
import 'core/notifications/fcm_lifecycle_provider.dart';
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

    final router = ref.watch(appRouterProvider);
    // Watch the FCM lifecycle so its auth listener stays alive for the
    // life of the customer app. The provider returns void; the side
    // effect (token persist + sign-out clear) is what we care about.
    ref.watch(fcmLifecycleProvider);

    return MaterialApp.router(
      title: 'Play Diaries',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Customer-app dark theme is shipped LOCKED OFF for v1. The card
      // surfaces, borders, and a few text styles are still hard-coded
      // to light values across dozens of widgets — switching the app to
      // dark mode produced white cards with white text (unreadable).
      // Proper dark theme audit is tracked as a separate task.
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
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
