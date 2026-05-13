#!/usr/bin/env bash
# Run the Diaries Club customer app on a connected iPhone (dev flavor,
# mock OTP + mock Razorpay). Usage:
#   ./run_dev_ios.sh
#
# Prereqs:
#   - iPhone connected via USB with Developer Mode on
#   - Xcode signing configured under your own Apple ID / team
#   - flutter pub get + pod install already done (script handles this)

set -e

cd "$(dirname "$0")"

SUPABASE_URL="https://stpxtenyatjwcazuxhtu.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0cHh0ZW55YXRqd2NhenV4aHR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3OTk1NTIsImV4cCI6MjA5MzM3NTU1Mn0.Wt1n15Q7AkJHYe4BsbRlACW3fh-BTV0XXkFMGzXNW8I"

flutter pub get
(cd ios && pod install)

# Auto-pick the connected iPhone so flutter doesn't ask + doesn't
# accidentally build for the Android emulator. `flutter devices` lists
# one line per device; we grep for "ios" and pull the device ID
# (second column when split on comma+spaces).
IPHONE_ID=$(flutter devices --machine 2>/dev/null \
  | python3 -c "import sys, json; ds=json.load(sys.stdin); print(next((d['id'] for d in ds if d.get('targetPlatform','').startswith('ios')), ''))")

if [ -z "$IPHONE_ID" ]; then
  echo ""
  echo "No iOS device detected. Make sure your iPhone is:"
  echo "  • plugged in via USB"
  echo "  • unlocked"
  echo "  • Developer Mode is on (Settings → Privacy & Security)"
  echo "  • has tapped Trust when prompted"
  echo ""
  exit 1
fi

echo "Running on iOS device: $IPHONE_ID"
flutter run -t lib/main_dev.dart \
  -d "$IPHONE_ID" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
