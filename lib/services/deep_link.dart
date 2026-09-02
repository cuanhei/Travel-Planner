import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../models/community_post.dart';

/// Parses a shared post ID out of the current page URL (e.g.
/// `https://your-deployment/post/<id>`, opened from a link shared via
/// [CommunityService.watchPost]'s companion share action in the feed).
///
/// Only meaningful on web — this app has no hosted URL on mobile/desktop,
/// so a link there can't reopen the app to a specific screen without native
/// deep-link registration (out of scope here); [SplashScreen] simply won't
/// find a pending post to jump to on those platforms.
String? parseSharedPostId() {
  if (!kIsWeb) return null;
  final segments = Uri.base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length >= 2 && segments[0] == 'post') {
    return segments[1];
  }
  return null;
}

/// The web URL for sharing [postId] — the current page's own origin plus
/// `/post/<id>`, so it always points at wherever this build is actually
/// hosted (localhost during development, or the real deployment URL once
/// published) rather than a guessed domain.
String sharedPostUrl(String postId) {
  final origin = Uri.base;
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/post/$postId',
  ).toString();
}

/// Opens the platform share sheet for [post]. On web this includes a real,
/// working link back to the post (see [sharedPostUrl]) — opening it lands
/// on `PostDetailScreen` via [parseSharedPostId]. On mobile/desktop builds
/// there's no hosted URL to link to (this app isn't deployed there), so
/// only the post's content is shared — a fabricated link that can't
/// actually open anything would be worse than no link.
Future<void> shareCommunityPost(CommunityPost post) async {
  final caption = post.caption.trim();
  final text = kIsWeb
      ? '${post.authorName} shared a moment at ${post.placeName}:\n'
            '"$caption"\n\n'
            '${sharedPostUrl(post.id)}'
      : '${post.authorName} shared a moment at ${post.placeName}:\n"$caption"\n\n'
            '— via TravelPlanner';
  await SharePlus.instance.share(
    ShareParams(text: text, subject: 'Travel moment at ${post.placeName}'),
  );
}
