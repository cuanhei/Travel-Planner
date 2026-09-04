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
  const PostMediaView({super.key, required this.url, required this.mediaType});

  final String url;
  final String mediaType;

  @override
  Widget build(BuildContext context) {
    if (mediaType == 'video') {
      return _NetworkVideo(url: url);
    }
    return Image.network(
      url,
      width: double.infinity,
      fit: BoxFit.fitWidth,
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
  }

  Widget _placeholder(BuildContext context, {required Widget child}) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        color: context.colors.card,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _NetworkVideo extends StatefulWidget {
  const _NetworkVideo({required this.url});

  final String url;

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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) {
      return AspectRatio(
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
      return AspectRatio(
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
    // Sized to the video's own aspect ratio rather than cropped/stretched
    // into a preset box — VideoPlayer fills whatever box it's given, so
    // matching the box to `controller.value.aspectRatio` is enough on its
    // own, no FittedBox/cover needed.
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: GestureDetector(
        onTap: _toggle,
        child: Stack(
          alignment: Alignment.center,
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
      ),
    );
  }
}
