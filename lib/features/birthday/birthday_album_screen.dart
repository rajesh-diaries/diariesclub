import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/providers/signed_birthday_photo_url_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/error_screen.dart';
import 'providers/reservation_providers.dart';

/// Birthday album — hero cover + birthday hero cards section + photo grid.
/// All photo URLs are signed (private bucket). Long-pressing a photo
/// toggles `is_in_album` so a parent can hide an unflattering shot. The
/// grid + lightbox use the same signed URL provider so revisiting the
/// screen within the hour re-uses the cache.
class BirthdayAlbumScreen extends ConsumerWidget {
  final String reservationId;
  const BirthdayAlbumScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservation = ref.watch(reservationByIdProvider(reservationId));
    final photos = ref.watch(birthdayPhotosProvider(reservationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Album'),
      ),
      body: reservation.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-ALB',
          userMessage: "Couldn't load the album",
          technicalDetails: e.toString(),
        ),
        data: (r) {
          if (r == null) {
            return const FriendlyErrorScreen(
              code: 'E-ALB-404',
              userMessage: "We couldn't find this album.",
            );
          }
          if (r['album_ready_at'] == null) {
            return const _AlbumPendingState();
          }
          return _AlbumBody(
            reservation: r,
            photosAsync: photos,
          );
        },
      ),
    );
  }
}

class _AlbumPendingState extends StatelessWidget {
  const _AlbumPendingState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              PhosphorIconsFill.images,
              color: AppColors.lightTextSecondary,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              'Your little memory is on its way',
              style: AppTextStyles.h3(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "We'll share it here once it's ready.",
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  final Map<String, dynamic> reservation;
  final AsyncValue<List<Map<String, dynamic>>> photosAsync;
  const _AlbumBody({
    required this.reservation,
    required this.photosAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final child = children.firstWhere(
      (c) => c['id'] == reservation['child_id'],
      orElse: () => const <String, dynamic>{},
    );
    final childName = (child['name'] as String?) ?? 'Birthday';

    return photosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyErrorScreen(
        code: 'E-ALB-PHOTOS',
        userMessage: "Couldn't load photos",
        technicalDetails: e.toString(),
      ),
      data: (photos) {
        // Cover = first album photo; admin can re-order via sort_order.
        final albumPhotos = photos.where((p) => p['is_in_album'] == true).toList();
        final coverPath = albumPhotos.isEmpty
            ? null
            : albumPhotos.first['photo_url'] as String?;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Cover(
                coverPath: coverPath,
                childName: childName,
                reservation: reservation,
              ),
            ),
            if (reservation['birthday_hero_card_id'] != null)
              SliverToBoxAdapter(
                child: _HeroCardSection(
                  cardId: reservation['birthday_hero_card_id'] as String,
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${photos.length} photo${photos.length == 1 ? '' : 's'} from the celebration',
                  style: AppTextStyles.bodyLarge(context),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (c, i) => _GridTile(
                    photos: photos,
                    index: i,
                    onOpen: () => _openLightbox(c, photos, i),
                  ),
                  childCount: photos.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  void _openLightbox(
    BuildContext context,
    List<Map<String, dynamic>> photos,
    int initialIndex,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _Lightbox(photos: photos, initialIndex: initialIndex),
        fullscreenDialog: true,
      ),
    );
  }
}

class _Cover extends ConsumerWidget {
  final String? coverPath;
  final String childName;
  final Map<String, dynamic> reservation;
  const _Cover({
    required this.coverPath,
    required this.childName,
    required this.reservation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(signedBirthdayPhotoUrlProvider(coverPath));
    final dateStr = reservation['slot_date'] as String?;

    return Stack(
      children: [
        SizedBox(
          height: 280,
          width: double.infinity,
          child: urlAsync.when(
            data: (url) => url == null
                ? Container(color: AppColors.gold.withValues(alpha: 0.20))
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.gold.withValues(alpha: 0.20),
                    ),
                  ),
            loading: () => Container(color: AppColors.lightBackground),
            error: (_, __) =>
                Container(color: AppColors.gold.withValues(alpha: 0.20)),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$childName's birthday",
                style: AppTextStyles.h1(context, color: Colors.white),
              ),
              if (dateStr != null)
                Text(
                  dateStr,
                  style: AppTextStyles.body(
                    context,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCardSection extends StatelessWidget {
  final String cardId;
  const _HeroCardSection({required this.cardId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.25),
            AppColors.rafiCoral.withValues(alpha: 0.25),
          ],
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'A special card earned today',
            style: AppTextStyles.h3(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Birthday-exclusive — only earned on a Diaries Club celebration.',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _BirthdayCardThumb(cardId: cardId),
        ],
      ),
    );
  }
}

class _BirthdayCardThumb extends StatelessWidget {
  final String cardId;
  const _BirthdayCardThumb({required this.cardId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadCard(cardId),
      builder: (c, snap) {
        final card = snap.data;
        if (card == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final imageUrl = card['image_url'] as String?;
        final name = card['name'] as String?;
        return Column(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl == null
                    ? Container(
                        height: 200,
                        width: 150,
                        color: AppColors.lightBorder,
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 200,
                        width: 150,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(name ?? 'Birthday card', style: AppTextStyles.bodyLarge(c)),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _loadCard(String id) async {
    final row = await Supabase.instance.client
        .from('hero_card_definitions')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}

class _GridTile extends ConsumerWidget {
  final List<Map<String, dynamic>> photos;
  final int index;
  final VoidCallback onOpen;
  const _GridTile({
    required this.photos,
    required this.index,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = photos[index];
    final isInAlbum = photo['is_in_album'] == true;
    final path = photo['photo_url'] as String?;

    return GestureDetector(
      onTap: isInAlbum ? onOpen : null,
      onLongPress: () => _showPhotoMenu(context, photo),
      child: !isInAlbum
          ? Container(
              color: AppColors.lightBorder,
              alignment: Alignment.center,
              child: Text(
                'Hidden',
                style: AppTextStyles.caption(context, color: Colors.white),
              ),
            )
          : Consumer(
              builder: (c, ref, _) {
                final urlAsync =
                    ref.watch(signedBirthdayPhotoUrlProvider(path));
                return urlAsync.when(
                  data: (url) => url == null
                      ? Container(color: AppColors.lightBorder)
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppColors.lightBorder),
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.lightBorder),
                        ),
                  loading: () => Container(color: AppColors.lightBorder),
                  error: (_, __) => Container(color: AppColors.lightBorder),
                );
              },
            ),
    );
  }

  void _showPhotoMenu(BuildContext context, Map<String, dynamic> photo) {
    final isHidden = photo['is_in_album'] != true;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isHidden
                    ? PhosphorIconsRegular.eye
                    : PhosphorIconsRegular.eyeSlash,
              ),
              title: Text(isHidden ? 'Show in album' : 'Hide from album'),
              onTap: () async {
                Navigator.of(c).pop();
                await Supabase.instance.client
                    .from('birthday_party_photos')
                    .update({'is_in_album': isHidden})
                    .eq('id', photo['id'] as String);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Lightbox extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  const _Lightbox({required this.photos, required this.initialIndex});

  @override
  ConsumerState<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends ConsumerState<_Lightbox> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _showChrome = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _shareCurrent() async {
    final photo = widget.photos[_index];
    final path = photo['photo_url'] as String?;
    final url = await ref.read(signedBirthdayPhotoUrlProvider(path).future);
    if (url == null) return;
    await Share.shareUri(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.photos[_index]['caption'] as String?;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showChrome
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                '${_index + 1} of ${widget.photos.length}',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.shareNetwork),
                  onPressed: _shareCurrent,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            final path = widget.photos[i]['photo_url'] as String?;
            final urlAsync = ref.watch(signedBirthdayPhotoUrlProvider(path));
            return InteractiveViewer(
              child: Center(
                child: urlAsync.when(
                  data: (url) => url == null
                      ? const Icon(
                          PhosphorIconsFill.imageBroken,
                          color: Colors.white54,
                          size: 64,
                        )
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          placeholder: (_, __) =>
                              const CircularProgressIndicator(),
                          errorWidget: (_, __, ___) => const Icon(
                            PhosphorIconsFill.imageBroken,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const Icon(
                    PhosphorIconsFill.imageBroken,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomSheet: _showChrome && caption != null && caption.isNotEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}
