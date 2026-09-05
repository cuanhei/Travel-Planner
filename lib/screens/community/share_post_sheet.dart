import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/community_post.dart';
import '../../services/deep_link.dart';
import '../../theme/app_theme.dart';
import '../../widgets/linkified_text.dart';
import 'post_detail_screen.dart';

/// Opens the "Share post" bottom sheet: the post's link (tappable — see
/// [LinkifiedText]/[openLink]) with a "Copy link" action, plus "Share via
/// app" for the platform share sheet (WhatsApp, Messages, etc. via
/// [shareCommunityPost]).
///
/// [sharedPostUrl] returns a placeholder link on platforms without a real
/// hosted build — it won't resolve yet, but still renders and behaves like a
/// real link here (and wherever it's shared to) until a real deployment
/// replaces the placeholder. Tapping it here always opens [post] right in
/// the app (via [PostDetailScreen]) rather than an external browser, since
/// it's a link back into this app's own content; only an *external* tap —
/// e.g. from inside WhatsApp, once this is a real deployed domain — needs
/// native Android App Links / iOS Universal Links to do the same.
Future<void> showSharePostSheet(BuildContext context, CommunityPost post) {
  final link = sharedPostUrl(post.id);
  return showModalBottomSheet(
    context: context,
    backgroundColor: context.colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share post',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: LinkifiedText(
                link,
                style: TextStyle(color: context.colors.ink, fontSize: 13),
                onTapLink: (_) {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: post.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Link copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      shareCommunityPost(post);
                    },
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share via app'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
