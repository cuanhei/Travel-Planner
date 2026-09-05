import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

/// Renders a post's attached photo or video from its Storage URL, sized to
/// its own aspect ratio (scaled to the card's width) rather than forced
/// into a fixed-height crop — whatever the poster cropped (for a photo) or
/// recorded (for a video) is exactly what shows here. Falls back to a
/// fixed-ratio placeholder while loading/on error, since real dimensions
/// aren't known yet, and to a static icon if video playback has no backend
/// on this platform/build (video_player has no desktop implementation).
class PostMediaView extends StatelessWidget {
  const PostMediaView({
    super.key,
    required this.url,
    required this.mediaType,
    this.boxSize,
  });

  final String url;
  final String mediaType;

  /// When set, renders as a fixed [boxSize] x [boxSize] square cropped to
  /// cover — for a multi-attachment post's carousel, where every tile
  /// needs the same size regardless of its own aspect ratio. `null` (the
  /// default, and a single-attachment post's only tile) keeps the normal
  /// behavior described above: sized to the media's own aspect ratio.
  final double? boxSize;

  @override
  Widget build(BuildContext context) {
    if (mediaType == 'video') {
      return _NetworkVideo(url: url, boxSize: boxSize);
    }
    final size = boxSize;
    final image = Image.network(
      url,
      width: size ?? double.infinity,
      height: size,
      fit: size != null ? BoxFit.cover : BoxFit.fitWidth,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(
          context,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
      errorBuilder: (context, error, stack) => _placeholder(
        context,
        child: Icon(Icons.broken_image_rounded, color: context.colors.muted),
      ),
    );
    return size == null
        ? image
        : SizedBox(width: size, height: size, child: image);
  }

  Widget _placeholder(BuildContext context, {required Widget child}) {
    final size = boxSize;
    final placeholder = Container(
      color: context.colors.card,
      alignment: Alignment.center,
      child: child,
    );
    if (size != null) {
      return SizedBox(width: size, height: size, child: placeholder);
    }
    return AspectRatio(aspectRatio: 4 / 3, child: placeholder);
  }
}

class _NetworkVideo extends StatefulWidget {
  const _NetworkVideo({required this.url, this.boxSize});

  final String url;
  final double? boxSize;

  @override
  State<_NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<_NetworkVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  Widget _box({required double aspectRatio, required Widget child}) {
    final size = widget.boxSize;
    if (size == null) {
      return AspectRatio(aspectRatio: aspectRatio, child: child);
    }
    return SizedBox(width: size, height: size, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) {
      return _box(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: const Icon(
            Icons.videocam_off_rounded,
            color: Colors.white54,
            size: 32,
          ),
        ),
      );
    }
    if (!controller.value.isInitialized) {
      return _box(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }
    final overlay = GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          VideoPlayer(controller),
          AnimatedOpacity(
            opacity: controller.value.isPlaying ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ],
      ),
    );
    final size = widget.boxSize;
    if (size == null) {
      // Sized to the video's own aspect ratio rather than cropped/
      // stretched into a preset box — VideoPlayer fills whatever box it's
      // given, so matching the box to `controller.value.aspectRatio` is
      // enough on its own, no FittedBox/cover needed.
      return AspectRatio(aspectRatio: controller.value.aspectRatio, child: overlay);
    }
    // A carousel tile needs every item the same size regardless of its own
    // aspect ratio, so this crops to cover instead: fit the video at its
    // natural size, then let the fixed SizedBox clip whatever spills over.
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: overlay,
          ),
        ),
      ),
    );
  }
}
