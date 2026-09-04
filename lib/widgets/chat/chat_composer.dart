import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/chat_attachment.dart';
import '../../theme/app_theme.dart';

/// A photo/video file picked in [ChatComposer], ready to be uploaded
/// and attached to a message.
class PickedChatMedia {
  const PickedChatMedia({
    required this.bytes,
    required this.fileExt,
    required this.contentType,
    required this.type,
  });

  final Uint8List bytes;
  final String fileExt;
  final String contentType;
  final ChatAttachmentType type;
}

/// Message input row shared by Group Chat and Direct Message screens: a
/// text field, an attach button (photo/video), and a send button.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendMedia,
  });

  final Future<void> Function(String text) onSendText;
  final Future<void> Function(PickedChatMedia media) onSendMedia;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  bool _hasText = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    try {
      await widget.onSendText(text);
    } catch (e) {
      _showError('Could not send: $e');
    }
  }

  String _fileExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  String _imageContentType(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  String _videoContentType(String ext) => switch (ext) {
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };

  Future<T?> _showOptionSheet<T>(List<(IconData, String, T)> options) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, label, value) in options)
              ListTile(
                leading: Icon(icon, color: sheetContext.colors.ink),
                title: Text(
                  label,
                  style: TextStyle(color: sheetContext.colors.ink),
                ),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia() async {
    final kind = await _showOptionSheet<ChatAttachmentType>([
      (Icons.photo_camera_rounded, 'Photo', ChatAttachmentType.image),
      (Icons.videocam_rounded, 'Video', ChatAttachmentType.video),
    ]);
    if (kind == null || !mounted) return;

    final picker = ImagePicker();
    final file = kind == ChatAttachmentType.image
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = _fileExt(file.name);
      final media = kind == ChatAttachmentType.image
          ? PickedChatMedia(
              bytes: bytes,
              fileExt: ext,
              contentType: _imageContentType(ext),
              type: ChatAttachmentType.image,
            )
          : PickedChatMedia(
              bytes: bytes,
              fileExt: ext,
              contentType: _videoContentType(ext),
              type: ChatAttachmentType.video,
            );
      await widget.onSendMedia(media);
    } catch (e) {
      _showError('Could not send: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _isBusy ? null : _pickMedia,
          icon: Icon(Icons.attach_file_rounded, color: context.colors.muted),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !_isBusy,
            style: TextStyle(color: context.colors.ink, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Message…',
              hintStyle: TextStyle(color: context.colors.muted),
              filled: true,
              fillColor: context.colors.card,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _sendText(),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: context.colors.ink,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _isBusy || !_hasText ? null : _sendText,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      color: _hasText
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      size: 18,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
