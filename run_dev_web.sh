#!/usr/bin/env bash
# Run the Diaries Club customer app in Chrome (dev flavor, mock OTP +
# mock Razorpay). Same env vars as iOS so the same Supabase data shows.
# Usage:
#   ./run_dev_web.sh

set -e
cd "$(dirname "$0")"

SUPABASE_URL="https://stpxtenyatjwcazuxhtu.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0cHh0ZW55YXRqd2NhenV4aHR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3OTk1NTIsImV4cCI6MjA5MzM3NTU1Mn0.Wt1n15Q7AkJHYe4BsbRlACW3fh-BTV0XXkFMGzXNW8I"

flutter pub get
flutter run -d chrome -t lib/main_dev.dart \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
