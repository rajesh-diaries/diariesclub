import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves a `child-photos` storage path (stored on `children.photo_url`)
/// into a signed URL valid for 1 hour. Cached per-path for ~50 minutes via
/// `keepAlive` + a self-disposing timer; subsequent reads after expiry
/// trigger a fresh signing request.
///
/// Returns `null` for empty/null paths or if signing fails (the UI shows a
/// fallback initial-letter avatar in that case).
final signedChildPhotoUrlProvider =
    FutureProvider.autoDispose.family<String?, String?>((ref, path) async {
  if (path == null || path.isEmpty) return null;

  // Hold the value alive long enough to be useful, then release so the
  // next read re-signs. The 1-hour signed URL expires *after* the cache
  // window, leaving a 10-minute safety margin.
  final keep = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 50), keep.close);
  ref.onDispose(timer.cancel);

  try {
    return await Supabase.instance.client.storage
        .from('child-photos')
        .createSignedUrl(path, 3600);
  } catch (e) {
    debugPrint('signed URL failed for $path: $e');
    return null;
  }
});
