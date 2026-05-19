#!/usr/bin/env bash
# Run the Diaries Club customer app on a connected iPhone (dev flavor).
#
# Loads env/dev.json so the build matches founder's actual test setup:
#   - OTP_MODE=real      → MSG91 sends real SMS to the phone
#   - RAZORPAY_MODE=test → real Razorpay test sheet (rzp_test_...)
#   - SENTRY_DSN         → errors flow to Sentry
#   - BRANCH_KEY         → Branch deep-link SDK ready
# Mock mode is no longer the default — to use it temporarily, comment
# the `--dart-define-from-file` line and uncomment the SUPABASE_URL +
# SUPABASE_ANON_KEY pair below.
#
# Prereqs (one-time):
#   1. iPhone connected via USB, unlocked, "Trust this computer" tapped.
#   2. Apple ID signed into Xcode → Settings → Accounts.
#   3. Runner signing team set in Xcode (open ios/Runner.xcworkspace,
#      Runner target → Signing & Capabilities → Team).
#   4. After first install, on the iPhone:
#      Settings → General → VPN & Device Management → trust the cert.
#
# Usage:
#   ./run_dev_iphone.sh

set -e
cd "$(dirname "$0")"

flutter pub get
# Profile mode: Flutter 3.41.6 debug mode crashes on iOS 26.1 with an
# EXC_BAD_ACCESS (code=50) in the Dart VM worker — iOS 26.x tightened
# pointer-auth / memory-tag enforcement and the JIT-style debug snapshot
# trips it. Profile mode uses AOT and runs cleanly. Trade-off is no hot
# reload; acceptable during E2E since you'd be retesting full flows anyway.
# Re-evaluate after `flutter upgrade` to a stable that supports iOS 26.x.
flutter run -d iPhone --profile -t lib/main_dev.dart \
  --dart-define-from-file=env/dev.json
