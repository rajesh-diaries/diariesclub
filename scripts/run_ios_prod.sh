#!/usr/bin/env bash
# Stable Flutter run for a physical iPhone (prod flavor) using flutter build + devicectl.
# Usage:
#   ./scripts/run_ios_prod.sh
#   ./scripts/run_ios_prod.sh 00008110-001035420A28401E
set -euo pipefail

DEVICE="${1:-iPhone}"
BUNDLE_ID="com.diariesclub.app"

echo "==> Building signed iOS release..."
flutter build ios \
  -t lib/main_prod.dart \
  --release \
  --dart-define-from-file=env/prod.json

echo "==> Installing on ${DEVICE}..."
xcrun devicectl device install app \
  --device "${DEVICE}" \
  build/ios/iphoneos/Runner.app

echo "==> Launching ${BUNDLE_ID}..."
xcrun devicectl device process launch \
  --device "${DEVICE}" \
  "${BUNDLE_ID}"
