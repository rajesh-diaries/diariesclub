import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/signed_child_photo_url_provider.dart';
import '../theme/app_colors.dart';

/// Round avatar for a child. Resolves the storage path (stored on
/// `children.photo_url`) into a signed URL via [signedChildPhotoUrlProvider]
/// and renders the photo, falling back to a tinted initial when no photo
/// is set or signing fails.
class ChildAvatar extends ConsumerWidget {
  /// Storage path (e.g. `{family_id}/{child_id}/{uuid}.jpg`). Pass null
  /// to skip the lookup and go straight to the initial fallback.
  final String? photoPath;

  /// Used for the fallback initial.
  final String name;

  /// Tint behind the initial when there's no photo. Defaults to gold-tinted.
  final Color? fallbackTint;

  /// Diameter in logical pixels.
  final double size;

  const ChildAvatar({
    super.key,
    required this.name,
    required this.size,
    this.photoPath,
    this.fallbackTint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = fallbackTint ?? AppColors.gold.withValues(alpha: 0.18);
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Text(
            initial,
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.42,
            ),
          ),
        );

    if (photoPath == null || photoPath!.isEmpty) return fallback();

    final urlAsync = ref.watch(signedChildPhotoUrlProvider(photoPath));
    return urlAsync.when(
      data: (url) {
        if (url == null) return fallback();
        return ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback(),
            errorWidget: (_, __, ___) => fallback(),
          ),
        );
      },
      loading: () => fallback(),
      error: (_, __) => fallback(),
    );
  }
}
