import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves a `birthday-photos` storage path (stored on
/// `birthday_party_photos.photo_url`) into a signed URL valid for 1 hour.
/// Cached per-path for ~50 minutes via `keepAlive` + a self-disposing
/// timer. Mirrors `signedChildPhotoUrlProvider` from Session 5b.
///
/// RLS on the bucket lets the family of the reservation read their own
/// folder (`{reservation_id}/...`); other paths return null.
final signedBirthdayPhotoUrlProvider =
    FutureProvider.autoDispose.family<String?, String?>((ref, path) async {
  if (path == null || path.isEmpty) return null;

  final keep = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 50), keep.close);
  ref.onDispose(timer.cancel);

  try {
    return await Supabase.instance.client.storage
        .from('birthday-photos')
        .createSignedUrl(path, 3600);
  } catch (e) {
    debugPrint('signed birthday URL failed for $path: $e');
    return null;
  }
});
