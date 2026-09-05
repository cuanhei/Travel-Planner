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

  final String senderName;

  final String? body;
  final bool hasAttachment;

  final bool isDeleted;
}
