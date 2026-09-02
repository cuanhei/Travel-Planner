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
/// `supabase/migrations/0010_community_module_repair.sql` for the RLS/
/// trigger/realtime setup that goes with them.
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

  /// Joins raw `posts` rows with their author's profile and whether the
  /// current user has liked each one. Shared by [watchFeed] (every post)
  /// and [watchPost] (a single post, for a shared-link deep link landing
  /// on `PostDetailScreen`).
  Future<List<CommunityPost>> _hydratePosts(List<Map<String, dynamic>> rows) async {
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
        .select('post_id')
        .eq('user_id', _uid)
        .inFilter('post_id', postIds);
    final likedPostIds = {
      for (final l in myLikes as List) l['post_id'] as String,
    };

    return rows
        .where((r) => profileById.containsKey(r['author_id']))
        .map(
          (r) => CommunityPost.fromMap(
            {...r, 'profiles': profileById[r['author_id']]},
            likedByMe: likedPostIds.contains(r['id']),
          ),
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
  }) async {
    await _client.from('posts').insert({
      'author_id': _uid,
      'place_name': placeName.trim(),
      'caption': caption.trim(),
      'category': category,
      'cover_gradient': coverGradient,
    });
  }

  /// Toggles the current user's like on [postId]. [currentlyLiked] is the
  /// state before this call, from the [CommunityPost] shown in the UI.
  Future<void> toggleLike(String postId, {required bool currentlyLiked}) async {
    if (currentlyLiked) {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', _uid);
    } else {
      // Plain insert, not upsert: unlike `posts`/`comments`/`reviews`,
      // `post_likes` wasn't a table this repo defined, so there's no
      // confirmed unique constraint on (post_id, user_id) to upsert
      // against — an insert either succeeds once or fails safely if a
      // like already exists, rather than assuming a constraint shape we
      // can't verify.
      try {
        await _client.from('post_likes').insert({
          'post_id': postId,
          'user_id': _uid,
        });
      } on PostgrestException catch (e) {
        // 23505 = unique_violation — already liked (e.g. a double-tap
        // race), not a real failure.
        if (e.code != '23505') rethrow;
      }
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
          final userIds = rows.map((r) => r['author_id'] as String).toSet().toList();
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

  Stream<List<PlaceReview>> watchReviews(String placeName) {
    return _client
        .from('reviews')
        .stream(primaryKey: ['id'])
        .eq('place_name', placeName)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <PlaceReview>[];
          final userIds = rows.map((r) => r['author_id'] as String).toSet().toList();
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

  /// Creates or replaces the current user's review for [placeName] (one
  /// review per user per place). Written as a select-then-write instead of
  /// `upsert(onConflict: ...)` because — same caveat as [toggleLike] —
  /// there's no confirmed unique constraint on (place_name, author_id) to
  /// upsert against on this hand-provisioned table.
  Future<void> upsertReview({
    required String placeName,
    required int rating,
    required String body,
  }) async {
    final existing = await _client
        .from('reviews')
        .select('id')
        .eq('place_name', placeName)
        .eq('author_id', _uid)
        .maybeSingle();

    if (existing == null) {
      await _client.from('reviews').insert({
        'place_name': placeName,
        'author_id': _uid,
        'rating': rating,
        'body': body.trim(),
      });
    } else {
      await _client
          .from('reviews')
          .update({'rating': rating, 'body': body.trim()})
          .eq('id', existing['id'] as String);
    }
  }

  Future<void> deleteReview(String reviewId) async {
    await _client.from('reviews').delete().eq('id', reviewId);
  }
}
