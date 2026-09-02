import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/chat_attachment.dart';
import '../../theme/app_theme.dart';

/// A photo/video/voice-note file picked or recorded in [ChatComposer],
/// ready to be uploaded and attached to a message.
class PickedChatMedia {
  const PickedChatMedia({
    required this.bytes,
    required this.fileExt,
    required this.contentType,
    required this.type,
    this.durationMs,
  });

  final Uint8List bytes;
  final String fileExt;
  final String contentType;
  final ChatAttachmentType type;
  final int? durationMs;
}

/// Message input row shared by Group Chat and Direct Message screens: a
/// text field plus an attach button (photo/video) and a
/// mic-that-becomes-send button, mirroring WhatsApp's composer —
/// tapping the mic starts recording a voice note in place of the text
/// field, with a timer and cancel/send controls.
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
  final _recorder = AudioRecorder();
  bool _hasText = false;
  bool _isRecording = false;
  bool _isBusy = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;
  DateTime? _recordingStartedAt;

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
    _recordingTimer?.cancel();
    _recorder.dispose();
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

    final source = await _showOptionSheet<ImageSource>([
      (Icons.camera_alt_rounded, 'Camera', ImageSource.camera),
      (Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
    ]);
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = kind == ChatAttachmentType.image
        ? await picker.pickImage(source: source, imageQuality: 85)
        : await picker.pickVideo(source: source);
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

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _showError('Microphone permission is needed to send a voice message');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: path);
      if (!mounted) return;
      _recordingStartedAt = DateTime.now();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(
            () => _recordingElapsed = DateTime.now().difference(
              _recordingStartedAt!,
            ),
          );
        }
      });
      setState(() {
        _isRecording = true;
        _recordingElapsed = Duration.zero;
      });
    } catch (e) {
      _showError('Could not start recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {
      // Best-effort — the recording's being thrown away either way.
    }
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _finishRecording() async {
    _recordingTimer?.cancel();
    final elapsed = _recordingElapsed;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      _showError('Could not finish recording: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isBusy = true;
    });
    try {
      if (path == null) {
        _showError('Recording produced no audio — please try again');
        return;
      }
      // record_web's stop() returns a blob: object URL rather than a
      // filesystem path — fetchable within the page via http, unlike a
      // real path which needs a File read.
      final bytes = kIsWeb
          ? (await http.get(Uri.parse(path))).bodyBytes
          : await File(path).readAsBytes();
      if (bytes.isEmpty) {
        _showError('Recording produced no audio — please try again');
        return;
      }
      await widget.onSendMedia(
        PickedChatMedia(
          bytes: bytes,
          fileExt: 'm4a',
          contentType: 'audio/mp4',
          type: ChatAttachmentType.audio,
          durationMs: elapsed.inMilliseconds,
        ),
      );
    } catch (e) {
      _showError('Could not send voice message: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecording) {
      return Row(
        children: [
          IconButton(
            onPressed: _cancelRecording,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.fiber_manual_record_rounded,
                  color: Colors.redAccent,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatElapsed(_recordingElapsed),
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Recording…',
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Material(
            color: context.colors.ink,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isBusy ? null : _finishRecording,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      );
    }

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
            onTap: _isBusy ? null : (_hasText ? _sendText : _startRecording),
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
                      _hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
