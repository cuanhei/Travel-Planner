import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_attachment.dart';
import '../models/chat_reply_preview.dart';
import '../models/direct_message.dart';
import '../models/reaction_event.dart';
import 'chat_media_service.dart';
import 'supabase_config.dart';

class DirectMessageService {
  DirectMessageService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;
  final _media = ChatMediaService();

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<DirectMessage>> watchConversation({
    required String tripId,
    required String otherUserId,
  }) {
    final myUid = _uid;
    return _client
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: true)
        .map((rows) {
          final conversationRows = rows
              .where(
                (r) =>
                    (r['sender_id'] == myUid &&
                        r['recipient_id'] == otherUserId) ||
                    (r['sender_id'] == otherUserId &&
                        r['recipient_id'] == myUid),
              )
              .toList();
          final rowById = {
            for (final r in conversationRows) r['id'] as String: r,
          };
          return conversationRows.map((r) {
            var message = DirectMessage.fromMap(r);
            final replyToId = message.replyToId;
            if (replyToId != null) {
              final target = rowById[replyToId];
              if (target != null) {
                message = message.withReplyPreview(
                  ChatReplyPreview(
                    messageId: replyToId,
                    senderId: target['sender_id'] as String,

                    senderName: '',
                    body: target['body'] as String?,
                    hasAttachment: target['attachment_url'] != null,
                    isDeleted: target['deleted_at'] != null,
                  ),
                );
              }
            }
            return message;
          }).toList();
        });
  }

  Future<void> sendMessage({
    required String tripId,
    required String recipientId,
    String? body,
    ChatAttachment? attachment,
    String? replyToId,
  }) async {
    final trimmed = body?.trim();
    if ((trimmed == null || trimmed.isEmpty) && attachment == null) return;
    await _client.from('direct_messages').insert({
      'trip_id': tripId,
      'sender_id': _uid,
      'recipient_id': recipientId,
      if (trimmed != null && trimmed.isNotEmpty) 'body': trimmed,
      if (attachment != null) ...attachment.toInsertMap(),
      if (replyToId != null) 'reply_to_id': replyToId,
    });
  }

  Future<String> uploadAttachment({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
    required String contentType,
  }) {
    return _media.upload(
      tripId: tripId,
      bytes: bytes,
      fileExt: fileExt,
      contentType: contentType,
    );
  }

  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {
    final trimmed = body.trim();
    await _client
        .from('direct_messages')
        .update({
          'body': trimmed.isEmpty ? null : trimmed,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId);
  }

  Future<void> deleteMessage(String messageId) async {
    await _client
        .from('direct_messages')
        .update({
          'body': null,
          'attachment_type': null,
          'attachment_url': null,
          'attachment_duration_ms': null,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId);
  }

  Future<void> setPinnedMessage({
    required String tripId,
    required String otherUserId,
    String? messageId,
  }) async {
    await _client.rpc(
      'set_pinned_direct_message',
      params: {
        'p_trip_id': tripId,
        'p_other_user_id': otherUserId,
        'p_message_id': messageId,
      },
    );
  }

  Stream<List<DirectMessage>> watchAllMyMessages(String tripId) {
    return _client
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(DirectMessage.fromMap).toList());
  }

  Stream<Map<String, DateTime>> watchAllLastRead(String tripId) {
    return _client
        .from('direct_message_reads')
        .stream(primaryKey: ['trip_id', 'user_id', 'other_user_id'])
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .map(
          (rows) => {
            for (final r in rows)
              r['other_user_id'] as String: DateTime.parse(
                r['last_read_at'] as String,
              ),
          },
        );
  }

  Future<void> markConversationRead({
    required String tripId,
    required String otherUserId,
  }) async {
    await _client.from('direct_message_reads').upsert({
      'trip_id': tripId,
      'user_id': _uid,
      'other_user_id': otherUserId,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'trip_id,user_id,other_user_id');
  }

  Stream<DateTime?> watchTheirLastRead({
    required String tripId,
    required String otherUserId,
  }) {
    final myUid = _uid;
    return _client
        .from('direct_message_reads')
        .stream(primaryKey: ['trip_id', 'user_id', 'other_user_id'])
        .eq('trip_id', tripId)
        .eq('user_id', otherUserId)
        .eq('other_user_id', myUid)
        .map(
          (rows) => rows.isEmpty
              ? null
              : DateTime.parse(rows.first['last_read_at'] as String),
        );
  }

  Stream<Map<String, Map<String, String>>> watchReactions(String tripId) {
    return _client
        .from('direct_message_reactions')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) {
          final byMessage = <String, Map<String, String>>{};
          for (final r in rows) {
            byMessage.putIfAbsent(
              r['message_id'] as String,
              () => {},
            )[r['user_id'] as String] = r['emoji'] as String;
          }
          return byMessage;
        });
  }

  Stream<List<ReactionEvent>> watchReactionEvents(String tripId) {
    return _client
        .from('direct_message_reactions')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) => rows.map(ReactionEvent.fromMap).toList());
  }

  Future<void> setReaction({
    required String tripId,
    required String messageId,
    required String emoji,
  }) async {
    await _client.from('direct_message_reactions').upsert({
      'message_id': messageId,
      'trip_id': tripId,
      'user_id': _uid,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id');
  }

  Future<void> removeReaction(String messageId) async {
    await _client
        .from('direct_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _uid);
  }

  RealtimeChannel? _typingChannel;
  String? _typingChannelKey;
  bool _typingSubscribed = false;

  RealtimeChannel _typingChannelFor(String tripId, String otherUserId) {
    final pair = [_uid, otherUserId]..sort();
    final key = 'typing:dm:$tripId:${pair.join('-')}';
    if (_typingChannel == null || _typingChannelKey != key) {
      _typingChannel?.unsubscribe();
      _typingChannel = _client.channel(key);
      _typingChannelKey = key;
      _typingSubscribed = false;
    }
    return _typingChannel!;
  }

  void _ensureTypingSubscribed(String tripId, String otherUserId) {
    final channel = _typingChannelFor(tripId, otherUserId);
    if (!_typingSubscribed) {
      _typingSubscribed = true;
      channel.subscribe();
    }
  }

  void sendTyping({required String tripId, required String otherUserId}) {
    _ensureTypingSubscribed(tripId, otherUserId);
    _typingChannelFor(
      tripId,
      otherUserId,
    ).sendBroadcastMessage(event: 'typing', payload: {'user_id': _uid});
  }

  Stream<void> watchTyping({
    required String tripId,
    required String otherUserId,
  }) {
    final controller = StreamController<void>.broadcast();
    final channel = _typingChannelFor(tripId, otherUserId);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final userId = payload['user_id'] as String?;
        if (userId == otherUserId) controller.add(null);
      },
    );
    _ensureTypingSubscribed(tripId, otherUserId);
    return controller.stream;
  }
}
