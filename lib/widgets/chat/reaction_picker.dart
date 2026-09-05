import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

const quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

Future<String?> showReactionPicker(
  BuildContext context, {
  String? selectedEmoji,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: sheetContext.colors.card,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in quickReactionEmojis)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(sheetContext).pop(emoji),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: emoji == selectedEmoji
                        ? BoxDecoration(
                            color: sheetContext.colors.ink.withValues(
                              alpha: 0.1,
                            ),
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ReactionsBar extends StatelessWidget {
  const ReactionsBar({super.key, required this.reactionsByUser, this.onTap});

  final Map<String, String> reactionsByUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (reactionsByUser.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    for (final emoji in reactionsByUser.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 13)),
                    if (entry.value > 1) ...[
                      const SizedBox(width: 2),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.colors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
