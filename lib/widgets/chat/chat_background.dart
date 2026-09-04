import 'package:flutter/material.dart';

import '../../services/supabase_config.dart';

/// One choice in Group Chat's "Change Background" picker. An empty
/// [colors] list means "no wallpaper" — just the theme's own surface
/// color, so it stays correct in both light and dark mode.
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

/// Backgrounds are a personal preference — never visible to anyone
/// else in the chat — but saved server-side (`chat_background_preferences`)
/// rather than to on-device storage, so it survives a reinstall and
/// follows the signed-in user to another device too. [conversationId]
/// scopes the choice to one chat: a trip's Group Chat can just use its
/// trip id, while a Direct Message uses something that also identifies
/// the other participant (e.g. `'$tripId/dm/$otherUserId'`) so each DM
/// keeps its own background.
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
