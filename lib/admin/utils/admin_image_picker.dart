import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Picks a single image from the admin's device and compresses it before
/// upload. Always returns JPEG bytes. Throws a human-friendly [Exception] on
/// failure so callers can surface the message.
Future<Uint8List?> pickAndCompressImage({
  int maxDimension = 1024,
  int quality = 80,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;

  final raw = result.files.single.bytes;
  if (raw == null || raw.isEmpty) {
    throw Exception('Selected image has no data.');
  }

  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw Exception('Unsupported image format.');
  }

  img.Image processed = decoded;
  final largest = math.max(processed.width, processed.height);
  if (largest > maxDimension) {
    final scale = maxDimension / largest;
    processed = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
    );
  }

  return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
}

/// Uploads compressed image bytes to Supabase Storage and returns the public
/// URL. Uses a UUID filename under [folder] inside [bucket].
Future<String> uploadImageBytes({
  required Uint8List bytes,
  required String bucket,
  required String folder,
  int timeoutSeconds = 30,
}) async {
  final fileName = '${const Uuid().v4()}.jpg';
  final path = folder.isEmpty ? fileName : '$folder/$fileName';
  await Supabase.instance.client.storage
      .from(bucket)
      .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      )
      .timeout(Duration(seconds: timeoutSeconds));
  return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
}
