/// The kind of media a chat message can carry instead of (or alongside)
/// text — shared by [GroupMessage] and `DirectMessage`.
enum ChatAttachmentType { image, video, audio }

/// A photo, video, or voice note attached to a chat message.
class ChatAttachment {
  const ChatAttachment({
    required this.type,
    required this.url,
    this.durationMs,
  });

  final ChatAttachmentType type;
  final String url;

  /// Playback length in milliseconds — only meaningful (and only ever
  /// set) for [ChatAttachmentType.audio], where the player needs it to
  /// show "0:00 / 0:12" before the audio itself has loaded.
  final int? durationMs;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// Reads `attachment_type`/`attachment_url`/`attachment_duration_ms`
  /// off a raw message row, or null if the message carries no
  /// attachment (a plain text message).
  static ChatAttachment? fromMap(Map<String, dynamic> map) {
    final rawType = map['attachment_type'] as String?;
    final url = map['attachment_url'] as String?;
    if (rawType == null || url == null) return null;
    return ChatAttachment(
      type: ChatAttachmentType.values.firstWhere(
        (t) => t.name == rawType,
        orElse: () => ChatAttachmentType.image,
      ),
      url: url,
      durationMs: map['attachment_duration_ms'] as int?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'attachment_type': type.name,
    'attachment_url': url,
    'attachment_duration_ms': durationMs,
  };
}
