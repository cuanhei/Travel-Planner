import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group_message.dart';
import 'supabase_config.dart';

/// Backend for the trip's group chat.
class ChatService {
  ChatService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<GroupMessage>> watchMessages(String tripId) {
    return _client
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        // Oldest-first: `order()` defaults to descending, which put the
        // newest message at the top of the plain top-to-bottom ListView.
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
          return rows
              .where((r) => profileById.containsKey(r['user_id']))
              .map(
                (r) => GroupMessage.fromMap({
                  ...r,
                  'profiles': profileById[r['user_id']],
                }),
              )
              .toList();
        });
  }

  Future<void> sendMessage({
    required String tripId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _client.from('group_messages').insert({
      'trip_id': tripId,
      'user_id': _uid,
      'body': trimmed,
    });
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.from('group_messages').delete().eq('id', messageId);
  }
}
