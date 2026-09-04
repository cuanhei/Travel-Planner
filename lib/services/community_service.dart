import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_post.dart';
import '../models/place_review.dart';
import '../models/post_comment.dart';
import 'supabase_config.dart';

/// Backend for the Community module: the travel-experience feed (with
/// likes/comments) and per-place reviews. Talks to `posts`, `comments`,
/// `reviews`, and `post_likes` — these tables were already provisioned by
/// hand on the shared Supabase project (not created by any file in this
/// repo), so every column name here was reverse-engineered against the
/// live schema rather than designed from scratch; see
/// `supabase/migrations/0009_community_module.sql` for the RLS/
/// trigger/realtime setup that goes with them, and
/// `supabase/migrations/0010_add_post_media.sql` for the post media
/// columns + storage bucket [addPost] uploads to, and
/// `supabase/migrations/0011_add_post_reactions.sql` for the
/// `reaction_type`/`reaction_counts` columns [setReaction] reads/writes.
class CommunityService {
  CommunityService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// The signed-in user's own profile (display name + avatar color), for
  /// "Posting as …" headers.
  Future<Map<String, dynamic>?> getMyProfile() async {
    return _client
        .from('profiles')
        .select('display_name, avatar_color')
        .eq('id', _uid)
        .maybeSingle();
  }

  // ---- Feed ---------------------------------------------------------

  /// Joins raw `posts` rows with their author's profile and the current
  /// user's own reaction on each one (if any). Shared by [watchFeed]
  /// (every post) and [watchPost] (a single post, for a shared-link deep
  /// link landing on `PostDetailScreen`).
  Future<List<CommunityPost>> _hydratePosts(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return <CommunityPost>[];

    final userIds = rows.map((r) => r['author_id'] as String).toSet().toList();
    final postIds = rows.map((r) => r['id'] as String).toList();

    final profiles = await _client
        .from('profiles')
        .select('id, display_name, avatar_color')
        .inFilter('id', userIds);
    final profileById = {
      for (final p in profiles as List) p['id'] as String: p,
    };

    final myLikes = await _client
        .from('post_likes')
        .select('post_id, reaction_type')
        .eq('user_id', _uid)
        .inFilter('post_id', postIds);
    final myReactionByPostId = {
      for (final l in myLikes as List)
        l['post_id'] as String: l['reaction_type'] as String,
    };

    // Counted live from `comments` rather than trusting `posts.comments_count`
    // — that column is a trigger-maintained cache that can silently drift
    // from the real row count (e.g. a delete whose trigger didn't fire), so
    // reads always fall back to the source of truth instead of risking a
    // stale number on screen.
    final commentRows = await _client
        .from('comments')
        .select('post_id')
        .inFilter('post_id', postIds);
    final commentsCountByPostId = <String, int>{};
    for (final c in commentRows as List) {
      final postId = c['post_id'] as String;
      commentsCountByPostId[postId] = (commentsCountByPostId[postId] ?? 0) + 1;
    }

    return rows
        .where((r) => profileById.containsKey(r['author_id']))
        .map(
          (r) => CommunityPost.fromMap({
            ...r,
            'profiles': profileById[r['author_id']],
            'comments_count': commentsCountByPostId[r['id']] ?? 0,
          }, myReaction: myReactionByPostId[r['id']]),
        )
        .toList();
  }

  Stream<List<CommunityPost>> watchFeed() {
    return _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap(_hydratePosts);
  }

  /// Live view of a single post, for `PostDetailScreen` (the landing
  /// screen for a shared post link). Emits `null` if the post was deleted.
  Stream<CommunityPost?> watchPost(String postId) {
    return _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .eq('id', postId)
        .asyncMap((rows) async {
          final hydrated = await _hydratePosts(rows);
          return hydrated.isEmpty ? null : hydrated.first;
        });
  }

  Future<void> addPost({
    required String placeName,
    required String caption,
    required String category,
    required String coverGradient,
    Uint8List? mediaBytes,
    String? mediaExtension,
    String? mediaType,
  }) async {
    String? mediaUrl;
    if (mediaBytes != null && mediaExtension != null && mediaType != null) {
      mediaUrl = await _uploadPostMedia(
        bytes: mediaBytes,
        extension: mediaExtension,
        mediaType: mediaType,
      );
    }

    await _client.from('posts').insert({
      'author_id': _uid,
      'place_name': placeName.trim(),
      'caption': caption.trim(),
      'category': category,
      'cover_gradient': coverGradient,
      if (mediaUrl != null) ...{'media_url': mediaUrl, 'media_type': mediaType},
    });
  }

  /// Uploads a post's photo/video to the `post-media` bucket under
  /// `<uid>/<timestamp>.<ext>` (the folder-per-user layout the storage RLS
  /// policies check ownership against) and returns its public URL.
  Future<String> _uploadPostMedia({
    required Uint8List bytes,
    required String extension,
    required String mediaType,
  }) async {
    final path = '$_uid/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from('post-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(extension, mediaType),
          ),
        );
    return _client.storage.from('post-media').getPublicUrl(path);
  }

  String _contentTypeFor(String extension, String mediaType) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return mediaType == 'video' ? 'video/mp4' : 'image/jpeg';
    }
  }

  /// Sets, changes, or clears the current user's reaction on [postId].
  /// [reactionType] is one of 'like'/'love'/'wow', or `null` to remove
  /// whatever reaction they currently have. [currentReaction] is the state
  /// before this call, from the [CommunityPost] shown in the UI — passed in
  /// rather than re-fetched so a rapid tap doesn't round-trip twice.
  Future<void> setReaction(
    String postId, {
    required String? reactionType,
    required String? currentReaction,
  }) async {
    if (reactionType == currentReaction) return;

    if (reactionType == null) {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _uid);
      return;
    }

    if (currentReaction != null) {
      await _client
          .from('post_likes')
          .update({'reaction_type': reactionType})
          .eq('post_id', postId)
          .eq('user_id', _uid);
      return;
    }

    // Plain insert, not upsert: unlike `posts`/`comments`/`reviews`,
    // `post_likes` wasn't a table this repo defined, so there's no
    // confirmed unique constraint on (post_id, user_id) to upsert
    // against — an insert either succeeds once or fails safely if a
    // reaction already exists (e.g. a double-tap race), rather than
    // assuming a constraint shape we can't verify.
    try {
      await _client.from('post_likes').insert({
        'post_id': postId,
        'user_id': _uid,
        'reaction_type': reactionType,
      });
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — already reacted, not a real failure.
      if (e.code != '23505') rethrow;
    }
  }

  // ---- Comments -------------------------------------------------------

  Stream<List<PostComment>> watchComments(String postId) {
    return _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', postId)
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <PostComment>[];
          final userIds = rows
              .map((r) => r['author_id'] as String)
              .toSet()
              .toList();
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          return rows
              .where((r) => profileById.containsKey(r['author_id']))
              .map(
                (r) => PostComment.fromMap({
                  ...r,
                  'profiles': profileById[r['author_id']],
                }),
              )
              .toList();
        });
  }

  Future<void> addComment(String postId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _client.from('comments').insert({
      'post_id': postId,
      'author_id': _uid,
      'body': trimmed,
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _client.from('comments').delete().eq('id', commentId);
  }

  // ---- Reviews --------------------------------------------------------

  /// One-shot average rating + review count for each of [placeNames], from
  /// `reviews` — for Explore's destination list, which shows a summary per
  /// place rather than the full live list a single place's screen needs
  /// (see [watchReviews]). A place with no reviews yet is simply absent
  /// from the result map.
  Future<Map<String, ({double average, int count})>> fetchRatingSummaries(
    List<String> placeNames,
  ) async {
    if (placeNames.isEmpty) return {};
    final rows = await _client
        .from('reviews')
        .select('place_name, rating')
        .inFilter('place_name', placeNames);

    final ratingsByPlace = <String, List<int>>{};
    for (final r in rows as List) {
      (ratingsByPlace[r['place_name'] as String] ??= []).add(
        r['rating'] as int,
      );
    }
    return {
      for (final entry in ratingsByPlace.entries)
        entry.key: (
          average: entry.value.reduce((a, b) => a + b) / entry.value.length,
          count: entry.value.length,
        ),
    };
  }

  /// Live version of [fetchRatingSummaries] — re-aggregates on every insert/
  /// update/delete to `reviews`, so a destination card showing a summary
  /// (Explore's list, Home's carousel) doesn't go stale the moment a review
  /// is added after the screen first loaded. Streams the whole table
  /// unfiltered (no `.eq`/`.inFilter` on `.stream()`) and filters to
  /// [placeNames] client-side, since a per-row filter would need
  /// `replica identity full` on `reviews` to reliably deliver delete events
  /// — see `supabase/migrations/0008_expenses_polls_members_replica_identity_full.sql`
  /// for the same issue on other tables.
  Stream<Map<String, ({double average, int count})>> watchRatingSummaries(
    List<String> placeNames,
  ) {
    final wanted = placeNames.toSet();
    return _client.from('reviews').stream(primaryKey: ['id']).map((rows) {
      final ratingsByPlace = <String, List<int>>{};
      for (final r in rows) {
        final name = r['place_name'] as String;
        if (!wanted.contains(name)) continue;
        (ratingsByPlace[name] ??= []).add(r['rating'] as int);
      }
      return {
        for (final entry in ratingsByPlace.entries)
          entry.key: (
            average: entry.value.reduce((a, b) => a + b) / entry.value.length,
            count: entry.value.length,
          ),
      };
    });
  }

  Stream<List<PlaceReview>> watchReviews(String placeName) {
    return _client
        .from('reviews')
        .stream(primaryKey: ['id'])
        .eq('place_name', placeName)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <PlaceReview>[];
          final userIds = rows
              .map((r) => r['author_id'] as String)
              .toSet()
              .toList();
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          return rows
              .where((r) => profileById.containsKey(r['author_id']))
              .map(
                (r) => PlaceReview.fromMap({
                  ...r,
                  'profiles': profileById[r['author_id']],
                }),
              )
              .toList();
        });
  }

  /// How many reviews the current user has already left for [placeName] —
  /// compared against [TripService.visitCount] to gate "Add Review": each
  /// visit is worth one review, so this only blocks *another* review once
  /// they've used up every visit they've got.
  Future<int> myReviewCount(String placeName) async {
    final rows = await _client
        .from('reviews')
        .select('id')
        .eq('place_name', placeName)
        .eq('author_id', _uid);
    return rows.length;
  }

  /// Adds a new review of [placeName] from the current user. Every visit
  /// earns one review, so — unlike a typical "one review per place"
  /// design — this always inserts a fresh row rather than overwriting a
  /// previous one; the caller (`AddReviewScreen`) only allows reaching this
  /// once [myReviewCount] is below [TripService.visitCount].
  Future<void> addReview({
    required String placeName,
    required int rating,
    required String body,
  }) async {
    await _client.from('reviews').insert({
      'place_name': placeName,
      'author_id': _uid,
      'rating': rating,
      'body': body.trim(),
    });
  }

  Future<void> deleteReview(String reviewId) async {
    // Same "did this actually match a row" check as [upsertReview] used to
    // do for its update — a DELETE an RLS policy silently hides also just
    // returns success with nothing deleted.
    final deleted = await _client
        .from('reviews')
        .delete()
        .eq('id', reviewId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError(
        'Review delete for "$reviewId" matched no row — it may already be '
        'gone, or an RLS policy is blocking the write.',
      );
    }
  }
}
