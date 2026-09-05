import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../theme/app_theme.dart';
import 'chat_composer.dart';

/// Shown right after picking a photo/video and before it actually
/// uploads — lets the traveler see exactly what they're about to send
/// (and add a caption) instead of it going out the moment it's picked.
/// Pops `null` if backed out (X or system back), or the caption text
/// (possibly empty, for "send with no caption") once "Send" is tapped.
class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.media, this.videoPath});

  final PickedChatMedia media;

  /// Local file path for a video pick — media_kit can play a file path
  /// directly, so this avoids re-writing the already-read [media.bytes]
  /// out to a temp file just to preview them.
  final String? videoPath;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _captionController = TextEditingController();
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    final path = widget.videoPath;
    if (path != null) {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      player.open(Media(path));
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context).pop(_captionController.text.trim());

  @override
  Widget build(BuildContext context) {
    final isImage = widget.videoPath == null;
    final videoController = _videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: isImage
                    ? Image.memory(widget.media.bytes, fit: BoxFit.contain)
                    : (videoController == null
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Video(controller: videoController)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
