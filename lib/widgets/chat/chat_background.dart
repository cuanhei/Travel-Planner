import 'package:flutter/material.dart';

import '../../services/supabase_config.dart';

class ChatBackground {
  const ChatBackground(this.key, this.label, this.colors);

  final String key;
  final String label;
  final List<Color> colors;
}

const chatBackgrounds = [
  ChatBackground('default', 'Default', []),
  ChatBackground('mint', 'Mint', [Color(0xFFB2F0E8), Color(0xFFEAFBF8)]),
  ChatBackground('peach', 'Peach', [Color(0xFFFFD9C4), Color(0xFFFFF3EA)]),
  ChatBackground('lavender', 'Lavender', [
    Color(0xFFE0D4FF),
    Color(0xFFF5F0FF),
  ]),
  ChatBackground('sky', 'Sky', [Color(0xFFCDEBFF), Color(0xFFF0FAFF)]),
  ChatBackground('sunset', 'Sunset', [Color(0xFFFFC9C9), Color(0xFFFFE8D6)]),
  ChatBackground('slate', 'Slate', [Color(0xFFDDE3EA), Color(0xFFF3F5F7)]),
];

ChatBackground chatBackgroundByKey(String? key) => chatBackgrounds.firstWhere(
  (b) => b.key == key,
  orElse: () => chatBackgrounds.first,
);

Future<String?> loadChatBackgroundKey(String conversationId) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await SupabaseConfig.client
      .from('chat_background_preferences')
      .select('background_key')
      .eq('user_id', uid)
      .eq('conversation_id', conversationId)
      .maybeSingle();
  return row?['background_key'] as String?;
}

Future<void> saveChatBackgroundKey(String conversationId, String key) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return;
  await SupabaseConfig.client.from('chat_background_preferences').upsert({
    'user_id': uid,
    'conversation_id': conversationId,
    'background_key': key,
  }, onConflict: 'user_id,conversation_id');
}
