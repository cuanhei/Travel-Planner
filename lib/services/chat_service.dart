import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_attachment.dart';
import '../models/chat_reply_preview.dart';
import '../models/group_message.dart';
import '../models/reaction_event.dart';
import 'chat_media_service.dart';
import 'supabase_config.dart';

class ChatService {
  ChatService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;
  final _media = ChatMediaService();

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<GroupMessage>> watchMessages(String tripId) {
    return _client
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          final userIds = rows
              .map((r) => r['user_id'] as String)
              .toSet()
              .toList();
          if (userIds.isEmpty) return <GroupMessage>[];
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };

          var nicknameByUserId = <String, String>{};
          try {
            final members = await _client
                .from('trip_members')
                .select('user_id, nickname')
                .eq('trip_id', tripId)
                .inFilter('user_id', userIds);
            nicknameByUserId = {
              for (final m in members as List)
                if (m['nickname'] != null)
                  m['user_id'] as String: m['nickname'] as String,
            };
          } catch (_) {}
          final rowById = {for (final r in rows) r['id'] as String: r};
          String nameFor(String userId) {
            final profile = profileById[userId];
            final nickname = nicknameByUserId[userId];
            return nickname ?? (profile?['display_name'] as String? ?? '?');
          }

          return rows.where((r) => profileById.containsKey(r['user_id'])).map((
            r,
          ) {
            final userId = r['user_id'] as String;
            final profile = profileById[userId]!;

            final mergedProfile = <String, dynamic>{
              ...profile,
              if (nicknameByUserId[userId] != null)
                'display_name': nicknameByUserId[userId],
            };
            var message = GroupMessage.fromMap({
              ...r,
              'profiles': mergedProfile,
            });
            final replyToId = message.replyToId;
            if (replyToId != null) {
              final target = rowById[replyToId];
              if (target != null) {
                message = message.withReplyPreview(
                  ChatReplyPreview(
                    messageId: replyToId,
                    senderId: target['user_id'] as String,
                    senderName: nameFor(target['user_id'] as String),
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
    String? body,
    ChatAttachment? attachment,
    String? replyToId,
    List<String>? mentionedUserIds,
  }) async {
    final trimmed = body?.trim();
    if ((trimmed == null || trimmed.isEmpty) && attachment == null) return;
    await _client.from('group_messages').insert({
      'trip_id': tripId,
      'user_id': _uid,
      if (trimmed != null && trimmed.isNotEmpty) 'body': trimmed,
      if (attachment != null) ...attachment.toInsertMap(),
      if (replyToId != null) 'reply_to_id': replyToId,
      if (mentionedUserIds != null && mentionedUserIds.isNotEmpty)
        'mentioned_user_ids': mentionedUserIds,
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
        .from('group_messages')
        .update({
          'body': trimmed.isEmpty ? null : trimmed,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId);
  }

  Future<void> deleteMessage(String messageId) async {
    await _client
        .from('group_messages')
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
    String? messageId,
  }) async {
    await _client.rpc(
      'set_pinned_group_message',
      params: {'p_trip_id': tripId, 'p_message_id': messageId},
    );
  }

  Stream<Map<String, Map<String, DateTime>>> watchReadReceipts(String tripId) {
    return _client
        .from('group_message_reads')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) {
          final byMessage = <String, Map<String, DateTime>>{};
          for (final r in rows) {
            final messageId = r['message_id'] as String;
            byMessage.putIfAbsent(messageId, () => {})[r['user_id'] as String] =
                DateTime.parse(r['read_at'] as String);
          }
          return byMessage;
        });
  }

  Future<void> markMessagesRead({
    required String tripId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    await _client
        .from('group_message_reads')
        .upsert(
          [
            for (final id in messageIds)
              {'message_id': id, 'trip_id': tripId, 'user_id': _uid},
          ],
          onConflict: 'message_id,user_id',
          ignoreDuplicates: true,
        );
  }

  Stream<Map<String, Map<String, String>>> watchReactions(String tripId) {
    return _client
        .from('group_message_reactions')
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
        .from('group_message_reactions')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) => rows.map(ReactionEvent.fromMap).toList());
  }

  Future<void> setReaction({
    required String tripId,
    required String messageId,
    required String emoji,
  }) async {
    await _client.from('group_message_reactions').upsert({
      'message_id': messageId,
      'trip_id': tripId,
      'user_id': _uid,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id');
  }

  Future<void> removeReaction(String messageId) async {
    await _client
        .from('group_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _uid);
  }

  RealtimeChannel? _typingChannel;
  String? _typingChannelTripId;
  bool _typingSubscribed = false;

  RealtimeChannel _typingChannelFor(String tripId) {
    if (_typingChannel == null || _typingChannelTripId != tripId) {
      _typingChannel?.unsubscribe();
      _typingChannel = _client.channel('typing:group:$tripId');
      _typingChannelTripId = tripId;
      _typingSubscribed = false;
    }
    return _typingChannel!;
  }

  void _ensureTypingSubscribed(String tripId) {
    final channel = _typingChannelFor(tripId);
    if (!_typingSubscribed) {
      _typingSubscribed = true;
      channel.subscribe();
    }
  }

  void sendTyping(String tripId) {
    _ensureTypingSubscribed(tripId);
    _typingChannelFor(
      tripId,
    ).sendBroadcastMessage(event: 'typing', payload: {'user_id': _uid});
  }

  Stream<String> watchTyping(String tripId) {
    final controller = StreamController<String>.broadcast();
    final channel = _typingChannelFor(tripId);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final userId = payload['user_id'] as String?;
        if (userId != null && userId != _uid) controller.add(userId);
      },
    );
    _ensureTypingSubscribed(tripId);
    return controller.stream;
  }
}
