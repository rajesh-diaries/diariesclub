# BUGS

Running log of post-merge bugs. New entries at the top.

---

## BUG-001: dart:io Platform usage breaks web build (FIXED)

- Discovered: 2026-05-04 post-Session 10
- Symptom: splash screen hangs forever
- Fix: kIsWeb + defaultTargetPlatform pattern
- Status: Fixed

### Files changed

- `lib/core/providers/app_version_provider.dart` — dropped `dart:io`,
  added `kIsWeb` early-return that short-circuits the version check to
  `upToDate` (web has no app store), used `defaultTargetPlatform` to
  pick the venue_config column on mobile.
- `lib/features/force_update/force_update_screen.dart` — same swap;
  store-URL button gated through a private `_isIOS()` helper. Web
  visitors who somehow hit this screen now get the Play Store URL as a
  sensible fallback (shouldn't happen because the version check exits
  before reaching this screen on web).

### Pattern to use going forward

```dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
```

Never `import 'dart:io'` for Platform checks — only acceptable use of
`dart:io` in the Flutter codebase is `File` for path-based bytes, and
even that breaks on web (see follow-ups below).

### Follow-ups (not yet broken on web, same anti-pattern)

These files still import `dart:io` for `File` (image picker results).
They don't crash splash, but adding/editing a child photo from Chrome
will fail. Web fix is `XFile` + `await xfile.readAsBytes()`:

- `lib/features/profile/edit_child_screen.dart`
- `lib/features/profile/add_child_screen.dart`
- `lib/features/onboarding/child_details_screen.dart`
