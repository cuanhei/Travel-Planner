import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/chat_attachment.dart';
import '../../theme/app_theme.dart';
import 'media_preview_screen.dart';

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

class ComposerReplyTarget {
  const ComposerReplyTarget({
    required this.messageId,
    required this.senderLabel,
    required this.body,
    required this.hasAttachment,
  });

  final String messageId;
  final String senderLabel;
  final String? body;
  final bool hasAttachment;
}

const _mentionAllId = '__all__';

class MentionCandidate {
  const MentionCandidate({
    required this.userId,
    required this.label,
    required this.avatarColor,
  });

  final String userId;
  final String label;
  final int avatarColor;
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendMedia,
    this.replyTarget,
    this.onCancelReply,
    this.mentionCandidates = const [],
    this.onTyping,
  });

  final Future<void> Function(
    String text, {
    String? replyToId,
    List<String>? mentionedUserIds,
  })
  onSendText;
  final Future<void> Function(
    PickedChatMedia media, {
    String? replyToId,
    String? caption,
  })
  onSendMedia;

  final ComposerReplyTarget? replyTarget;
  final VoidCallback? onCancelReply;

  final List<MentionCandidate> mentionCandidates;

  final VoidCallback? onTyping;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isBusy = false;
  Timer? _typingThrottle;

  final Set<String> _mentionedIds = {};

  String? _mentionQuery;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _typingThrottle?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    if (hasText && widget.onTyping != null && _typingThrottle == null) {
      widget.onTyping!();

      _typingThrottle = Timer(const Duration(seconds: 2), () {
        _typingThrottle = null;
      });
    }

    if (widget.mentionCandidates.isEmpty) return;
    final selection = _controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final upToCursor = text.substring(0, cursor.clamp(0, text.length));
    final at = upToCursor.lastIndexOf('@');
    if (at == -1) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    final rawQuery = upToCursor.substring(at + 1);

    final nextQuery = rawQuery.contains(' ') ? null : rawQuery;
    if (nextQuery != _mentionQuery) setState(() => _mentionQuery = nextQuery);
  }

  List<MentionCandidate> get _mentionMatches {
    final query = _mentionQuery;
    if (query == null) return const [];
    final lower = query.toLowerCase();
    final matches = widget.mentionCandidates
        .where((c) => c.label.toLowerCase().startsWith(lower))
        .toList();

    if (widget.mentionCandidates.isNotEmpty && 'all'.startsWith(lower)) {
      matches.insert(
        0,
        const MentionCandidate(
          userId: _mentionAllId,
          label: 'All',
          avatarColor: 0xFF616161,
        ),
      );
    }
    return matches;
  }

  void _pickMention(MentionCandidate candidate) {
    final text = _controller.text;
    final cursor = _controller.selection.isValid
        ? _controller.selection.baseOffset
        : text.length;
    final upToCursor = text.substring(0, cursor.clamp(0, text.length));
    final at = upToCursor.lastIndexOf('@');
    if (at == -1) return;
    final before = text.substring(0, at);
    final after = text.substring(cursor.clamp(0, text.length));
    final inserted = '@${candidate.label} ';
    final caretOffset = (before + inserted).length;
    _controller.value = TextEditingValue(
      text: '$before$inserted$after',
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    if (candidate.userId == _mentionAllId) {
      _mentionedIds.addAll(widget.mentionCandidates.map((c) => c.userId));
    } else {
      _mentionedIds.add(candidate.userId);
    }
    setState(() => _mentionQuery = null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(offset: caretOffset);
    });
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final replyToId = widget.replyTarget?.messageId;
    final mentionedUserIds = _mentionedIds.toList();
    _controller.clear();
    _mentionedIds.clear();
    setState(() => _mentionQuery = null);
    widget.onCancelReply?.call();

    _focusNode.requestFocus();
    try {
      await widget.onSendText(
        text,
        replyToId: replyToId,
        mentionedUserIds: mentionedUserIds,
      );
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

    if (!mounted) return;

    final caption = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          media: media,
          videoPath: kind == ChatAttachmentType.video ? file.path : null,
        ),
        fullscreenDialog: true,
      ),
    );
    if (caption == null || !mounted) return;

    setState(() => _isBusy = true);
    final replyToId = widget.replyTarget?.messageId;
    try {
      await widget.onSendMedia(
        media,
        replyToId: replyToId,
        caption: caption.isEmpty ? null : caption,
      );
      widget.onCancelReply?.call();
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

  Widget _buildReplyBanner() {
    final target = widget.replyTarget;
    if (target == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${target.senderLabel}',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  target.body ?? (target.hasAttachment ? 'Photo/Video' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 18,
            onPressed: widget.onCancelReply,
            icon: Icon(Icons.close_rounded, color: context.colors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildMentionSuggestions() {
    final matches = _mentionMatches;
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        children: [
          for (final candidate in matches)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Color(candidate.avatarColor),
                child: candidate.userId == _mentionAllId
                    ? const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : Text(
                        candidate.label[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
              ),
              title: Text(
                candidate.userId == _mentionAllId
                    ? 'All members'
                    : candidate.label,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              onTap: () => _pickMention(candidate),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMentionSuggestions(),
        _buildReplyBanner(),
        Row(
          children: [
            IconButton(
              onPressed: _isBusy ? null : _pickMedia,
              icon: Icon(
                Icons.attach_file_rounded,
                color: context.colors.muted,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
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
        ),
      ],
    );
  }
}
