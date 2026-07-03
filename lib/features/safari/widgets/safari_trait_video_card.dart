import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariTraitVideoCard extends StatefulWidget {
  final String title;
  final String description;
  final String scenario;
  final String placeholderImage;
  final String videoAsset;

  const SafariTraitVideoCard({
    super.key,
    required this.title,
    required this.description,
    required this.scenario,
    required this.placeholderImage,
    this.videoAsset = '',
  });

  @override
  State<SafariTraitVideoCard> createState() => _SafariTraitVideoCardState();
}

class _SafariTraitVideoCardState extends State<SafariTraitVideoCard> {
  VideoPlayerController? _controller;
  bool _hasVideo = false;
  bool _isMuted = true;
  bool _lastIsPlaying = false;
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    _hasVideo = widget.videoAsset.isNotEmpty;
    if (_hasVideo) {
      _controller = VideoPlayerController.asset(widget.videoAsset);
      _controller!
          .initialize()
          .then((_) {
            if (!mounted) return;
            _controller!
              ..setLooping(true)
              ..setVolume(0)
              ..addListener(_onControllerUpdate);
            setState(() {});
            // Only auto-play if this card is actually on-screen.
            _scheduleVisibilityCheck();
          })
          .catchError((_) {
            // If the asset is missing or fails to decode, fall back to placeholder.
            if (mounted) {
              setState(() => _hasVideo = false);
            }
          });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Track the enclosing scrollable so we can pause off-screen videos.
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_updateVisibility);
      _scrollPosition = position;
      _scrollPosition?.addListener(_updateVisibility);
      _scheduleVisibilityCheck();
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_updateVisibility);
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibility();
    });
  }

  // Play only while the card is meaningfully on-screen; pause otherwise.
  void _updateVisibility() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final size = renderObject.size;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final top = topLeft.dy;
    final bottom = topLeft.dy + size.height;
    final isVisible = bottom > screenHeight * 0.15 && top < screenHeight * 0.85;
    if (isVisible) {
      if (!controller.value.isPlaying) controller.play();
    } else {
      if (controller.value.isPlaying) controller.pause();
    }
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final isPlaying = controller.value.isPlaying;
    if (isPlaying != _lastIsPlaying) {
      _lastIsPlaying = isPlaying;
      if (mounted) setState(() {});
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0 : 1);
    });
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SafariColors.warmGray,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SafariColors.jungleGreen.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: AppTextStyles.bodyLarge(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.description,
            style: AppTextStyles.caption(context, color: SafariColors.slate),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: SafariColors.jungleGreen.withValues(alpha: 0.08),
                child: _hasVideo ? _videoPlayer() : _placeholder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: SafariColors.lightSage,
          child: Image.asset(widget.placeholderImage, fit: BoxFit.contain),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Text(
            widget.scenario,
            style: AppTextStyles.body(
              context,
              color: Colors.white,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              PhosphorIconsRegular.play,
              color: SafariColors.jungleGreen,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoPlayer() {
    final controller = _controller;
    final isInitialized = controller != null && controller.value.isInitialized;

    if (!isInitialized) {
      return _placeholder();
    }

    final isPlaying = controller.value.isPlaying;

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          // Subtle vignette so the controls and text remain readable.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.25),
                ],
              ),
            ),
          ),
          // Center play/pause indicator (fades out when playing).
          if (!isPlaying)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsRegular.play,
                  color: SafariColors.jungleGreen,
                  size: 28,
                ),
              ),
            ),
          // Bottom-right controls.
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      isPlaying
                          ? PhosphorIconsRegular.pause
                          : PhosphorIconsRegular.play,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _toggleMute,
                    icon: Icon(
                      _isMuted
                          ? PhosphorIconsRegular.speakerSimpleX
                          : PhosphorIconsRegular.speakerSimpleHigh,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
