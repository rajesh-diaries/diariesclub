#!/usr/bin/env bash
# Run the Diaries Staff app on a connected Android device (staffDev flavor).
#
# Loads env/staff_dev.json so the build has SUPABASE_URL +
# SUPABASE_ANON_KEY. Without --dart-define-from-file the staff app boots
# with an empty Supabase URL and login fails with:
#   "invalid arguments: no host specified in URL /auth/v1/token?grant_type=password"
#
# Prereqs (one-time):
#   1. Android device connected via USB, "Allow USB debugging" tapped.
#   2. `flutter devices` shows the device.
#   3. Android Studio / SDK installed (flutter doctor must be green for Android).
#
# Usage:
#   ./run_staff_dev_android.sh
#
# Notes:
#   - applicationId is com.diariesclub.staff.dev (separate from the
#     customer app), so this installs side-by-side with the customer dev app.
#   - Debug mode is fine on Android (Flutter 3.41.6 debug crash is iOS 26.x only).

set -e
cd "$(dirname "$0")"

flutter pub get
flutter run \
  --flavor staffDev \
  -t lib/main_staff_dev.dart \
  --dart-define-from-file=env/staff_dev.json
