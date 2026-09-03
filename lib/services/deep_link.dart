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
/// find a pending post to jump to on those platforms. Within the app
/// itself, [showSharePostSheet] routes straight to the post instead of
/// relying on this.
String? parseSharedPostId() {
  if (!kIsWeb) return null;
  return postIdFromSharedLink(Uri.base.toString());
}

/// Extracts the post ID from a `.../post/<id>` link — one built by
/// [sharedPostUrl], whether typed by the user, tapped from [LinkifiedText],
/// or pasted into a caption/comment — or `null` if [url] isn't one (an
/// unrelated link, or not a valid URL at all).
String? postIdFromSharedLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length >= 2 && segments[0] == 'post') {
    return segments[1];
  }
  return null;
}

/// Placeholder origin used to build a share link on platforms that aren't
/// web — this app isn't deployed anywhere yet, so there's no real domain to
/// point to. Swap this for the real deployment's URL once one exists.
const _placeholderOrigin = 'https://travelplanner.app';

/// The URL for sharing [postId] — on web, the current page's own origin
/// plus `/post/<id>`, so it always points at wherever this build is
/// actually hosted (localhost during development, or the real deployment
/// URL once published). On other platforms, the same path under
/// [_placeholderOrigin], since there's no hosted build to link to yet — it
/// won't resolve externally, but it renders and behaves like a real link
/// (see [shareCommunityPost], [LinkifiedText]) and — inside this app, via
/// [showSharePostSheet] — taps straight to the post.
String sharedPostUrl(String postId) {
  final origin = kIsWeb ? Uri.base : Uri.parse(_placeholderOrigin);
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/post/$postId',
  ).toString();
}

/// Opens the platform share sheet for [post], with a link back to the post
/// (see [sharedPostUrl]) included on every platform. On web, opening it
/// lands on `PostDetailScreen` via [parseSharedPostId]; elsewhere it's a
/// placeholder link (not yet live externally) that still renders and taps
/// like a real one wherever it's shared to, and opens the post directly
/// when tapped inside this app (see [showSharePostSheet]).
Future<void> shareCommunityPost(CommunityPost post) async {
  final caption = post.caption.trim();
  final text =
      '${post.authorName} shared a moment at ${post.placeName}:\n'
      '"$caption"\n\n'
      '${sharedPostUrl(post.id)}';
  await SharePlus.instance.share(
    ShareParams(text: text, subject: 'Travel moment at ${post.placeName}'),
  );
}
