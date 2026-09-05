import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/chat_attachment.dart';

class ChatMediaViewerScreen extends StatefulWidget {
  const ChatMediaViewerScreen({
    super.key,
    required this.attachments,
    required this.initialIndex,
  });

  final List<ChatAttachment> attachments;
  final int initialIndex;

  @override
  State<ChatMediaViewerScreen> createState() => _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<ChatMediaViewerScreen> {
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.attachments.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1} / $count',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final attachment = widget.attachments[i];
              return attachment.type == ChatAttachmentType.image
                  ? _ZoomableImage(url: attachment.url)
                  : _InlineVideo(url: attachment.url);
            },
          ),
          if (_index > 0)
            Positioned(
              left: 8,
              child: _NavArrowButton(
                icon: Icons.chevron_left_rounded,
                onTap: () => _goTo(_index - 1),
              ),
            ),
          if (_index < count - 1)
            Positioned(
              right: 8,
              child: _NavArrowButton(
                icon: Icons.chevron_right_rounded,
                onTap: () => _goTo(_index + 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavArrowButton extends StatelessWidget {
  const _NavArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.url});

  final String url;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  static const _doubleTapZoom = 3.0;
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_controller.value != Matrix4.identity()) {
      _controller.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (_doubleTapZoom - 1),
        -position.dy * (_doubleTapZoom - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(_doubleTapZoom, _doubleTapZoom, _doubleTapZoom, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: _minScale,
        maxScale: _maxScale,
        child: Center(child: Image.network(widget.url, fit: BoxFit.contain)),
      ),
    );
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({required this.url});

  final String url;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(controller: _controller);
}
