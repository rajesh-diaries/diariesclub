import 'dart:async';
import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/notifications/fcm_setup.dart';
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
      // Tag every event with the flavor so a single Sentry project can
      // host all three apps if you ever consolidate. Today we keep three
      // projects + three DSNs but tagging is free defence-in-depth.
      options.beforeSend = (event, hint) async => _stripPii(event);
      options.beforeBreadcrumb = (crumb, hint) => _scrubBreadcrumb(crumb);
    });
  }

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

// ── PII scrub regex set ───────────────────────────────────────────────
// Order matters: emails first (they contain @ which the phone regex
// would not catch), then phones, then catch-all 10+ digit blocks, then
// any child names the current family has registered with us at runtime
// (see [registerChildNamesForScrub] below), then the possessive-pattern
// fallback for any child name we didn't get to register in time.
final RegExp _emailRe =
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
final RegExp _phoneRe = RegExp(r'\+?91[\s\-]?[6-9]\d{4}[\s\-]?\d{5}');
final RegExp _bareIndianMobileRe = RegExp(r'(?<!\d)[6-9]\d{9}(?!\d)');
final RegExp _possessiveChildRe =
    RegExp(r"\b[A-Z][a-zA-Z]{1,30}'s\s+(reflection|session|birthday|hero|recap)");

/// Runtime set of the current family's child first names. Populated by
/// the children provider once auth + first read complete; cleared on
/// sign-out. Read inside [_scrubText] to replace any bare occurrence of
/// a child name with the literal `[child]` before the event leaves the
/// device.
///
/// This is best-effort: if a crash happens before the children stream
/// has yielded its first row, the bare-name strip won't catch anything
/// — the possessive-pattern fallback still applies. Anything matching
/// `<Name>'s reflection|session|birthday|hero|recap` is scrubbed even
/// without registration.
final Set<String> _runtimeChildNames = <String>{};

/// Register the current family's child first names so the Sentry PII
/// scrubber can strip them out of any event / breadcrumb that would
/// otherwise leave the device. Call this whenever the children list
/// changes (e.g. inside `familyChildrenProvider`'s yield path). Pass an
/// empty list on sign-out to clear.
void registerChildNamesForScrub(Iterable<String> names) {
  _runtimeChildNames
    ..clear()
    ..addAll(names
        .map((n) => n.trim())
        .where((n) => n.length >= 2 && n.length <= 40));
}

String _scrubText(String input) {
  if (input.isEmpty) return input;
  var out = input
      .replaceAll(_emailRe, '[email]')
      .replaceAll(_phoneRe, '[phone]')
      .replaceAll(_bareIndianMobileRe, '[phone]');

  // Strip every registered child name (case-insensitive, word-bounded).
  // Iterating a small set (typically 1-3 names) is cheap.
  for (final n in _runtimeChildNames) {
    final escaped = RegExp.escape(n);
    out = out.replaceAll(
      RegExp(r'\b' + escaped + r'\b', caseSensitive: false),
      '[child]',
    );
  }

  // Possessive-pattern fallback for any child name we didn't register
  // (e.g. crash fired before the children stream yielded).
  out = out.replaceAllMapped(_possessiveChildRe, (m) {
    final tail = m.group(1) ?? '';
    return "[child]'s $tail";
  });

  return out;
}

dynamic _scrubAny(dynamic value) {
  if (value is String) return _scrubText(value);
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, _scrubAny(v)));
  }
  if (value is List) {
    return value.map(_scrubAny).toList();
  }
  return value;
}

/// Strips PII (phones, emails, child-name patterns) from an event before
/// it leaves the device. Keeps anonymised user.id (auth.users.id UUID)
/// for correlation. Sentry 9.x dropped SentryEvent.copyWith — fields are
/// assigned directly.
///
/// Surfaces scrubbed:
///   * event.user → reduced to id only (drop username, email, ip)
///   * event.message → text scrub
///   * event.extra → recursive scrub
///   * event.tags → no scrub needed (we control these)
///   * event.contexts → no scrub (Flutter app/device contexts only)
///
/// Breadcrumbs are scrubbed in [_scrubBreadcrumb] (separate hook).
SentryEvent _stripPii(SentryEvent event) {
  final user = event.user;
  if (user != null) {
    event.user = SentryUser(id: user.id);
  }
  final msg = event.message;
  if (msg != null) {
    event.message = SentryMessage(
      _scrubText(msg.formatted),
      template: msg.template,
      params: msg.params,
    );
  }
  // Sentry 9 deprecated `extra` in favour of structured Contexts, but
  // existing capture sites (and third-party plugins) still write to it,
  // so we have to keep scrubbing it. Ignore the deprecation here only.
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null && extra.isNotEmpty) {
    // ignore: deprecated_member_use
    event.extra = (_scrubAny(extra) as Map).cast<String, dynamic>();
  }
  // Flavor tag — useful when consolidating into one project later.
  event.tags = {...?event.tags, 'flavor': F.name};
  return event;
}

/// Breadcrumb scrubber. Sentry calls this for every breadcrumb (nav,
/// http, log) before adding it to the event. Returning null drops the
/// crumb entirely; we keep it but scrub message + data.
Breadcrumb? _scrubBreadcrumb(Breadcrumb? crumb) {
  if (crumb == null) return null;
  if (crumb.message != null) {
    crumb.message = _scrubText(crumb.message!);
  }
  if (crumb.data != null) {
    crumb.data = (_scrubAny(crumb.data) as Map).cast<String, dynamic>();
  }
  return crumb;
}

// Used by tests / hot reload to verify bootstrap ran without exceptions.
@visibleForTesting
const bootstrapMarker = 'diaries_club_bootstrap_v1';
