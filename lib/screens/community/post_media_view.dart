import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

/// Renders a post's attached photo or video from its Storage URL (image:
/// plain network image; video: tap-to-play inline player). Falls back to a
/// static icon if video playback has no backend on this platform/build
/// (video_player has no desktop implementation), so the feed still shows
/// *something* instead of throwing.
class PostMediaView extends StatelessWidget {
  const PostMediaView({
    super.key,
    required this.url,
    required this.mediaType,
    this.height = 180,
  });

  final String url;
  final String mediaType;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: mediaType == 'video'
          ? _NetworkVideo(url: url)
          : Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: context.colors.card,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stack) => Container(
                color: context.colors.card,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_rounded,
                  color: context.colors.muted,
                ),
              ),
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
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Icon(
          Icons.videocam_off_rounded,
          color: Colors.white54,
          size: 32,
        ),
      );
    }
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white70,
        ),
      );
    }
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
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
  }
}
