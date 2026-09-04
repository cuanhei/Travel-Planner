import 'package:flutter/material.dart';

import '../../models/chat_attachment.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat/fullscreen_image_viewer.dart';
import '../../widgets/chat/fullscreen_video_viewer.dart';
import '../../widgets/detail_header.dart';

/// Grid of every photo/video sent in a conversation — tapping one opens
/// the same full-screen viewer as tapping it in the chat itself.
class ChatMediaScreen extends StatelessWidget {
  const ChatMediaScreen({
    super.key,
    required this.subtitle,
    required this.attachments,
  });

  final String subtitle;

  /// Newest first.
  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Media', subtitle: subtitle),
            Expanded(
              child: attachments.isEmpty
                  ? Center(
                      child: Text(
                        'No photos or videos yet',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                      itemCount: attachments.length,
                      itemBuilder: (context, index) {
                        final attachment = attachments[index];
                        final isImage =
                            attachment.type == ChatAttachmentType.image;
                        return GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => isImage
                                  ? FullscreenImageViewer(url: attachment.url)
                                  : FullscreenVideoViewer(url: attachment.url),
                              fullscreenDialog: true,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: isImage
                                ? Image.network(
                                    attachment.url,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.black87,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
