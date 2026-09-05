/// The quoted snippet of a message being replied to — resolved
/// client-side from a message's `reply_to_id`, the same way sender
/// profiles are (realtime streams don't support embedded joins).
/// Shared by [GroupMessage] and `DirectMessage`.
class ChatReplyPreview {
  const ChatReplyPreview({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.hasAttachment,
    required this.isDeleted,
  });

  final String messageId;
  final String senderId;

  /// Resolved by [ChatService] (which already has nicknames/profiles in
  /// hand) for a group reply — left empty by [DirectMessageService],
  /// which doesn't fetch profile data itself; a DM screen already knows
  /// the other participant's name and derives display text from
  /// [senderId] instead ('You' vs the other person) rather than this.
  final String senderName;

  /// Null for a media-only original message.
  final String? body;
  final bool hasAttachment;

  /// The original message has since been deleted — shown as "Original
  /// message deleted" instead of a real snippet.
  final bool isDeleted;
}
