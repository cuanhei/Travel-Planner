import 'supabase_config.dart';

Future<DateTime?> loadReactionsSeenAt(String conversationId) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await SupabaseConfig.client
      .from('chat_reaction_seen_state')
      .select('last_seen_at')
      .eq('user_id', uid)
      .eq('conversation_id', conversationId)
      .maybeSingle();
  final value = row?['last_seen_at'] as String?;
  return value == null ? null : DateTime.parse(value);
}

Future<void> saveReactionsSeenAt(String conversationId, DateTime when) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return;
  await SupabaseConfig.client.from('chat_reaction_seen_state').upsert({
    'user_id': uid,
    'conversation_id': conversationId,
    'last_seen_at': when.toUtc().toIso8601String(),
  }, onConflict: 'user_id,conversation_id');
}
