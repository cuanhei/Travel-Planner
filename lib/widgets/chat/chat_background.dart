import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Backgrounds are a personal, per-device preference (like WhatsApp's
/// per-chat wallpaper) — stored locally, not shared with the group.
String _prefsKey(String tripId) => 'chat_bg_$tripId';

Future<String?> loadChatBackgroundKey(String tripId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey(tripId));
}

Future<void> saveChatBackgroundKey(String tripId, String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey(tripId), key);
}
