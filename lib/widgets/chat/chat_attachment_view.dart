import 'package:flutter/material.dart';

import '../../models/chat_attachment.dart';
import 'audio_message_player.dart';
import 'fullscreen_image_viewer.dart';
import 'fullscreen_video_viewer.dart';

/// Renders a [ChatAttachment] inside a chat bubble — a tappable
/// thumbnail for a photo or video (opening a full-screen viewer), or an
/// inline play/pause row for a voice note. Shared by Group Chat and
/// Direct Message screens.
class ChatAttachmentView extends StatelessWidget {
  const ChatAttachmentView({
    super.key,
    required this.attachment,
    required this.mine,
  });

  final ChatAttachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    switch (attachment.type) {
      case ChatAttachmentType.image:
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FullscreenImageViewer(url: attachment.url),
              fullscreenDialog: true,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              attachment.url,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
        );
      case ChatAttachmentType.video:
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FullscreenVideoViewer(url: attachment.url),
              fullscreenDialog: true,
            ),
          ),
          child: Container(
            width: 200,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        );
      case ChatAttachmentType.audio:
        return AudioMessagePlayer(
          url: attachment.url,
          mine: mine,
          knownDuration: attachment.duration,
        );
    }
  }
}
