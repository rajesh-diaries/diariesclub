import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'photo_compress_service.dart';

/// Uploads a child's photo to the private `child-photos` bucket and returns
/// the *storage path* (not a public URL — the bucket is private). Callers
/// pass the path to `child_create` / `child_update` RPCs as `p_photo_url`,
/// then resolve it for display via [signedChildPhotoUrlProvider].
///
/// Path layout: `{family_id}/{child_id}/{uuid}.jpg`
/// Matches the storage RLS policy in 0001_initial_schema.sql which only
/// allows `storage.foldername(name)[1] == auth.uid()::text`.
class ChildPhotoService {
  ChildPhotoService._();

  /// Compresses [rawBytes] (≤500 KB JPEG, max 1080×1080) and uploads under
  /// `{familyId}/{childId}/{uuid}.jpg`. Returns the new storage path.
  static Future<String> uploadCompressed({
    required String familyId,
    required String childId,
    required Uint8List rawBytes,
  }) async {
    final compressed = await PhotoCompressService.compress(rawBytes);
    final fileName = '${const Uuid().v4()}.jpg';
    final path = '$familyId/$childId/$fileName';

    await Supabase.instance.client.storage.from('child-photos').uploadBinary(
          path,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    return path;
  }

  /// Best-effort delete of an old photo when replacing. Failures are
  /// swallowed — the orphaned file is left for a future sweep job, never
  /// blocks the user-facing update.
  static Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await Supabase.instance.client.storage
          .from('child-photos')
          .remove([path]);
    } catch (_) {
      // No-op: the orphan is acceptable; logging it would be noisy.
    }
  }
}
