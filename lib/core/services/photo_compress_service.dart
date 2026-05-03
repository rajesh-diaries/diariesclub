import 'dart:typed_data';

import 'package:image/image.dart' as img_lib;

/// Resizes uploads to 1080×1080 max, JPEG ~80% quality, ~500 KB cap.
class PhotoCompressService {
  PhotoCompressService._();

  /// Returns compressed JPEG bytes. Throws [FormatException] if the input
  /// can't be decoded; throws [StateError] if the image can't be squeezed
  /// under the 500 KB cap even at quality 50.
  static Future<Uint8List> compress(Uint8List input) async {
    var img = img_lib.decodeImage(input);
    if (img == null) {
      throw const FormatException('unreadable_image');
    }

    if (img.width > 1080 || img.height > 1080) {
      img = img_lib.copyResize(
        img,
        width: img.width > img.height ? 1080 : null,
        height: img.height > img.width ? 1080 : null,
        interpolation: img_lib.Interpolation.cubic,
      );
    }

    var quality = 85;
    while (true) {
      final jpeg = Uint8List.fromList(img_lib.encodeJpg(img, quality: quality));
      if (jpeg.length <= 500 * 1024) return jpeg;
      quality -= 10;
      if (quality < 50) {
        throw StateError('photo_too_large (final size > 500KB at q=50)');
      }
    }
  }
}
