#!/usr/bin/env bash
# Stable Flutter run for a physical iPhone using flutter build + devicectl.
# `flutter run` intermittently fails to install on physical iOS devices
# ("Could not run build/ios/iphoneos/Runner.app"). This script builds a
# signed debug .app with Flutter and installs/launches it with Apple's
# devicectl, which is the same mechanism Xcode uses.
#
# Usage:
#   ./scripts/run_ios_dev.sh
#   ./scripts/run_ios_dev.sh 00008110-001035420A28401E
#   RELEASE=1 ./scripts/run_ios_dev.sh 00008110-001035420A28401E
set -euo pipefail

# Use the supplied UDID if given, otherwise fall back to the device name.
DEVICE="${1:-iPhone}"
BUNDLE_ID="com.diariesclub.app"
BUILD_MODE="${RELEASE:-0}"

if [[ "$BUILD_MODE" == "1" ]]; then
  MODE_FLAG="--release"
  MODE_NAME="release"
else
  MODE_FLAG="--debug"
  MODE_NAME="debug"
fi

echo "==> Building signed iOS ${MODE_NAME}..."
flutter build ios \
  -t lib/main_dev.dart \
  "${MODE_FLAG}" \
  --dart-define-from-file=env/dev.json

echo "==> Installing on ${DEVICE}..."
xcrun devicectl device install app \
  --device "${DEVICE}" \
  build/ios/iphoneos/Runner.app

echo "==> Launching ${BUNDLE_ID}..."
xcrun devicectl device process launch \
  --device "${DEVICE}" \
  "${BUNDLE_ID}"
