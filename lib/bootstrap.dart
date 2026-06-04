import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/notifications/fcm_setup.dart';
import 'flavors.dart';

/// App bootstrap — initialises Supabase, Firebase, and FCM, then runs the
/// app. Errors caught in the zone are logged locally only; per Privacy
/// Policy §2.1 no third-party crash-reporting SDK is in the build.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded(_initServices, (error, stack) {
    dev.log('Uncaught zone error', error: error, stackTrace: stack);
  });

  runApp(const ProviderScope(child: DiariesClubApp()));
}

Future<void> _initServices() async {
  // Supabase — required.
  await Supabase.initialize(
    url: F.supabaseUrl,
    anonKey: F.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
    debug: F.isDev,
  );

  // Firebase — google-services.json + firebase_options.dart added in
  // Session 12. Boot must not crash if missing (e.g., new dev clone before
  // running flutterfire configure).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    dev.log('Firebase init skipped — config missing: $e');
  }

  // FCM — customer app only. Staff (tablet, awake) and admin web have
  // Realtime; push would be redundant noise and adds setup cost we don't
  // need right now. Initialise after Firebase so the messaging plugin
  // doesn't trip over a missing default app.
  if (!F.isStaff && !F.isAdmin) {
    // FCM is best-effort. On iOS, the native plugin can hang on APNs
    // registration when entitlements are incomplete (no Runner.entitlements
    // shipped yet — Session 12 task). A hang here would block runApp and
    // keep the iOS launch screen visible forever. Cap at 4s.
    try {
      await FcmSetup.initialize().timeout(const Duration(seconds: 4));
    } catch (e) {
      dev.log('FCM init timed out or failed (non-fatal): $e');
    }
  }
}

// Used by tests / hot reload to verify bootstrap ran without exceptions.
@visibleForTesting
const bootstrapMarker = 'diaries_club_bootstrap_v1';
