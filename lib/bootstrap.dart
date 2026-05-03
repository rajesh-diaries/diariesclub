import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'flavors.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded(_initServices, (error, stack) {
    dev.log('Uncaught zone error', error: error, stackTrace: stack);
    if (F.sentryEnabled) {
      Sentry.captureException(error, stackTrace: stack);
    }
  });

  runApp(const ProviderScope(child: DiariesClubApp()));
}

Future<void> _initServices() async {
  // Sentry first so it captures init errors below.
  if (F.sentryEnabled && F.sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = F.sentryDsn;
      options.environment = F.name;
      options.beforeSend = (event, hint) async => _stripPii(event);
    });
  }

  // Supabase — required.
  await Supabase.initialize(
    url: F.supabaseUrl,
    anonKey: F.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
    debug: F.isDev,
  );

  // Firebase — config files (GoogleService-Info.plist / google-services.json)
  // are added in Session 12. Boot must not crash if missing.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    dev.log('Firebase init skipped — config missing (expected pre-Session 12): $e');
  }

  // Branch.io — same: real key + native config arrives in Session 12.
  try {
    if (F.branchKey.isNotEmpty) {
      await FlutterBranchSdk.init(enableLogging: !F.isProd);
    } else {
      dev.log('Branch init skipped — BRANCH_KEY empty (expected pre-Session 12).');
    }
  } catch (e) {
    dev.log('Branch init failed (non-fatal): $e');
  }
}

/// Strips PII (names/phones/child names) before events leave the device.
/// Keeps anonymised user.id (auth.users.id UUID) for correlation.
/// Sentry 9.x dropped SentryEvent.copyWith — fields are assigned directly.
SentryEvent _stripPii(SentryEvent event) {
  final user = event.user;
  if (user != null) {
    event.user = SentryUser(id: user.id);
  }
  // Scrub digit sequences that look like Indian phones from message text.
  final msg = event.message;
  if (msg != null) {
    final scrubbed = msg.formatted.replaceAll(
      RegExp(r'\+?91?[6-9]\d{9}'),
      '[phone]',
    );
    event.message = SentryMessage(
      scrubbed,
      template: msg.template,
      params: msg.params,
    );
  }
  return event;
}

// Used by tests / hot reload to verify bootstrap ran without exceptions.
@visibleForTesting
const bootstrapMarker = 'diaries_club_bootstrap_v1';
