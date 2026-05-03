# Build Flavors

Three Dart entry points with separate env files:

| Flavor | Entry point | Env file | Bundle ID (Android) | Bundle ID (iOS) |
|---|---|---|---|---|
| dev | `lib/main_dev.dart` | `env/dev.json` | `com.diariesclub.app.dev` | `com.diariesclub.app` *(see below)* |
| staging | `lib/main_staging.dart` | `env/staging.json` | `com.diariesclub.app.staging` | `com.diariesclub.app` *(see below)* |
| prod | `lib/main_prod.dart` | `env/prod.json` | `com.diariesclub.app` | `com.diariesclub.app` |

## Run / build

```bash
# Dev
flutter run \
  --flavor dev \
  -t lib/main_dev.dart \
  --dart-define-from-file=env/dev.json

# Staging
flutter run \
  --flavor staging \
  -t lib/main_staging.dart \
  --dart-define-from-file=env/staging.json

# Prod
flutter run \
  --release \
  -t lib/main_prod.dart \
  --dart-define-from-file=env/prod.json
```

## Android — fully wired ✅

`android/app/build.gradle.kts` defines three product flavors. Each gets its own `applicationIdSuffix`, `versionNameSuffix`, and `app_name` resource. **You can install dev + staging + prod side-by-side on the same device.**

## iOS — single bundle ID for now ⚠️

The default Flutter iOS scaffold has a single Runner scheme + three build configurations (Debug/Profile/Release). Adding three full schemes (Runner-dev/-staging/-prod) with per-scheme bundle IDs requires Xcode UI work that's hard to do reliably from the CLI without breaking project.pbxproj.

**Current state:** all three iOS builds use bundle ID `com.diariesclub.app`. Dart-level env separation (Supabase URL, Razorpay key, Sentry, Branch) works correctly — but you can't install dev + prod side-by-side on iOS.

**Follow-up (Session 4 or whenever you next open Xcode):**

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the Runner project → Info tab → Configurations. Duplicate Debug/Profile/Release into Debug-dev / Profile-dev / Release-dev (and -staging, -prod).
3. Manage Schemes → New scheme `Runner-dev` using the *-dev configurations. Same for staging and prod.
4. In each new configuration's Build Settings, override `PRODUCT_BUNDLE_IDENTIFIER` to `com.diariesclub.app.dev` (and `.staging`).
5. After this, `flutter run --flavor dev` etc. will build the right scheme automatically.

This is ~30 min of Xcode UI work. Skip until you actually need side-by-side install.
