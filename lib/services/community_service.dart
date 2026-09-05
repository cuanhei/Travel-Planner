import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_feed_event.dart';
import '../models/community_post.dart';
import '../models/place_review.dart';
import '../models/post_comment.dart';
import 'post_location_service.dart';
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
/// columns + storage bucket [addPost] uploads to (extended to up to 3
/// attachments per post by `0027_post_multi_media.sql`), and
/// `supabase/migrations/0011_add_post_reactions.sql` for the
/// `reaction_type`/`reaction_counts` columns [setReaction] reads/writes,
/// and `supabase/migrations/0014_add_review_photos.sql` for the
/// `photo_urls` column + storage bucket [addReview] uploads to.
class CommunityService {
  CommunityService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// The signed-in user's own profile (display name, avatar color, and
  /// avatar photo/design), for "Posting as …" headers.
  Future<Map<String, dynamic>?> getMyProfile() async {
    return _client
        .from('profiles')
        .select('display_name, avatar_color, avatar_url')
        .eq('id', _uid)
        .maybeSingle();
  }

  // ---- Feed ---------------------------------------------------------

  /// Joins raw `posts` rows with their author's profile and the current
  /// user's own reaction on each one (if any). Used by [fetchFeedPage].
  Future<List<CommunityPost>> _hydratePosts(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return <CommunityPost>[];

    final userIds = rows.map((r) => r['author_id'] as String).toSet().toList();
    final postIds = rows.map((r) => r['id'] as String).toList();

    final profiles = await _client
        .from('profiles')
        .select(
          'id, display_name, avatar_color, avatar_url, location_sharing_enabled',
        )
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

  /// One page of the feed, newest first, optionally narrowed to
  /// [category] — for `CommunityTab`'s pull-to-refresh/infinite-scroll
  /// list. Replaced the old unbounded `watchFeed()` Realtime stream (which
  /// pulled every row in `posts` up front); pagination and a live
  /// subscription of an unbounded, filterable set don't mix, so the feed
  /// now re-fetches on pull-to-refresh instead of updating live.
  Future<List<CommunityPost>> fetchFeedPage({
    String? category,
    required int offset,
    int limit = 10,
  }) async {
    final query = _client.from('posts').select();
    final filtered = category == null ? query : query.eq('category', category);
    final rows = await filtered
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return _hydratePosts(List<Map<String, dynamic>>.from(rows));
  }

  /// Lightweight companion to [fetchFeedPage]: rather than streaming every
  /// row of `posts` (what the old `watchFeed()` did, incompatible with
  /// pagination), this only ever emits small deltas — a signal that a new
  /// post exists upstream, or a counts patch for a post already loaded —
  /// for [CommunityTab] to apply to its in-memory page without re-fetching.
  Stream<CommunityFeedEvent> watchFeedActivity() {
    late final StreamController<CommunityFeedEvent> controller;
    late final RealtimeChannel channel;

    void emit(CommunityFeedEvent event) {
      if (!controller.isClosed) controller.add(event);
    }

    controller = StreamController<CommunityFeedEvent>.broadcast(
      onListen: () {
        channel = _client
            .channel('community-feed-activity')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'posts',
              callback: (payload) {
                // Own posts are already picked up by the refresh CommunityTab
                // triggers right after AddPostScreen returns — only a post
                // from someone else counts as "new" here.
                if (payload.newRecord['author_id'] == _uid) return;
                emit(const NewPostAvailable());
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'posts',
              callback: (payload) {
                final row = payload.newRecord;
                final rawCounts =
                    row['reaction_counts'] as Map<String, dynamic>? ?? const {};
                emit(
                  PostReactionsChanged(
                    postId: row['id'] as String,
                    reactionCounts: rawCounts.map(
                      (k, v) => MapEntry(k, v as int),
                    ),
                    likesCount: row['likes_count'] as int,
                  ),
                );
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'comments',
              callback: (payload) {
                emit(
                  PostCommentCountChanged(
                    postId: payload.newRecord['post_id'] as String,
                    delta: 1,
                  ),
                );
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: 'comments',
              callback: (payload) {
                // `comments` has replica identity full (see
                // 0009_community_module.sql), so the full old row —
                // including post_id — survives into a DELETE payload.
                final postId = payload.oldRecord['post_id'] as String?;
                if (postId == null) return;
                emit(PostCommentCountChanged(postId: postId, delta: -1));
              },
            )
            .subscribe();
      },
      onCancel: () => _client.removeChannel(channel),
    );

    return controller.stream;
  }

  /// Up to 3 photos/videos per post — see [addPost]/[updatePost].
  static const maxPostMedia = 3;

  Future<void> addPost({
    required String placeName,
    required String caption,
    required String category,
    required String coverGradient,
    List<(Uint8List bytes, String extension, String mediaType)> media =
        const [],
  }) async {
    assert(media.length <= maxPostMedia);
    final uploaded = await Future.wait([
      for (var i = 0; i < media.length; i++)
        _uploadPostMedia(
          bytes: media[i].$1,
          extension: media[i].$2,
          mediaType: media[i].$3,
          index: i,
        ),
    ]);

    // Captured on every post regardless of the Location Sharing setting —
    // that setting only gates whether PostCard *displays* this later (see
    // `_hydratePosts` and `post_location_service.dart`), not whether it's
    // recorded. Column is still named `ip_address` (see
    // `0026_post_ip_and_location_sharing.sql`), but holds a resolved area
    // name like "George Town" now, not a raw IP.
    final areaName = await PostLocationService().resolveCurrentAreaName();

    final row = await _client
        .from('posts')
        .insert({
          'author_id': _uid,
          'place_name': placeName.trim(),
          'caption': caption.trim(),
          'category': category,
          'cover_gradient': coverGradient,
          if (uploaded.isNotEmpty) ...{
            'media_urls': uploaded,
            'media_types': [for (final m in media) m.$3],
          },
        })
        .select('id')
        .single();

    // A follow-up write rather than setting `ip_address` in the insert
    // above: the `posts` table was hand-provisioned directly on the
    // shared Supabase project (see the class doc comment above), and
    // apparently carries a server-side trigger there that captures the
    // request's real IP into this column on insert regardless of what
    // the client sends — this second write runs after that trigger has
    // already fired, so it's what the column actually ends up holding.
    await _client
        .from('posts')
        .update({'ip_address': areaName})
        .eq('id', row['id'] as String);
  }

  /// Edits [postId] in place — only the author can, per the
  /// `posts_update_own` RLS policy, so a caller that isn't the author gets
  /// [StateError] rather than a silent no-op.
  ///
  /// [keepMedia] are attachments already on the post the user chose not to
  /// remove; [newMedia] are fresh picks to upload, appended after them —
  /// together they replace `media_urls`/`media_types` outright, since
  /// there's no way to patch an array column in place. Passing both empty
  /// clears the post's media entirely.
  Future<void> updatePost({
    required String postId,
    required String placeName,
    required String caption,
    required String category,
    List<PostMedia> keepMedia = const [],
    List<(Uint8List bytes, String extension, String mediaType)> newMedia =
        const [],
  }) async {
    assert(keepMedia.length + newMedia.length <= maxPostMedia);
    final uploaded = await Future.wait([
      for (var i = 0; i < newMedia.length; i++)
        _uploadPostMedia(
          bytes: newMedia[i].$1,
          extension: newMedia[i].$2,
          mediaType: newMedia[i].$3,
          index: i,
        ),
    ]);
    final mediaUrls = [...keepMedia.map((m) => m.url), ...uploaded];
    final mediaTypes = [
      ...keepMedia.map((m) => m.type),
      ...newMedia.map((m) => m.$3),
    ];

    final updated = await _client
        .from('posts')
        .update({
          'place_name': placeName.trim(),
          'caption': caption.trim(),
          'category': category,
          'media_urls': mediaUrls.isEmpty ? null : mediaUrls,
          'media_types': mediaTypes.isEmpty ? null : mediaTypes,
        })
        .eq('id', postId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        'Post update for "$postId" matched no row — it may not exist, or '
        'an RLS policy is blocking the write.',
      );
    }
  }

  /// Deletes [postId] outright — only the author can, per the
  /// `posts_delete_own` RLS policy, so a caller that isn't the author gets
  /// [StateError] rather than a silent no-op. Its likes/comments cascade
  /// with it (`on delete cascade` on both tables' `post_id`).
  Future<void> deletePost(String postId) async {
    final deleted = await _client
        .from('posts')
        .delete()
        .eq('id', postId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError(
        'Post delete for "$postId" matched no row — it may already be '
        'gone, or an RLS policy is blocking the write.',
      );
    }
  }

  /// Uploads a post's photo/video to the `post-media` bucket under
  /// `<uid>/<timestamp>-<index>.<ext>` (the folder-per-user layout the
  /// storage RLS policies check ownership against) and returns its public
  /// URL. [index] (this attachment's position within the same submit's
  /// batch) keeps two files uploaded in the same millisecond from
  /// colliding on the same path.
  Future<String> _uploadPostMedia({
    required Uint8List bytes,
    required String extension,
    required String mediaType,
    required int index,
  }) async {
    final path =
        '$_uid/${DateTime.now().millisecondsSinceEpoch}-$index.$extension';
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
              .select('id, display_name, avatar_color, avatar_url')
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

  /// [parentCommentId] makes this a reply, shown nested under that
  /// comment — always a top-level comment's own id, never another
  /// reply's, so a reply-to-a-reply still flattens into the same thread
  /// (see [CommentsSection._replyTargetRootId]).
  Future<void> addComment(
    String postId,
    String body, {
    String? parentCommentId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _client.from('comments').insert({
      'post_id': postId,
      'author_id': _uid,
      'body': trimmed,
      'parent_comment_id': ?parentCommentId,
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
              .select('id, display_name, avatar_color, avatar_url')
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
  ///
  /// [photos] (bytes + extension pairs from `AddReviewScreen`'s picker) are
  /// uploaded to `review-media` first — same folder-per-user layout as
  /// [_uploadPostMedia] — and their URLs stored on the row.
  Future<void> addReview({
    required String placeName,
    required int rating,
    required String body,
    List<(Uint8List bytes, String extension)> photos = const [],
  }) async {
    final photoUrls = await Future.wait(
      photos.map((p) => _uploadReviewPhoto(bytes: p.$1, extension: p.$2)),
    );
    await _client.from('reviews').insert({
      'place_name': placeName,
      'author_id': _uid,
      'rating': rating,
      'body': body.trim(),
      if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
    });
  }

  /// Edits [reviewId] in place — only the author can, per the
  /// `reviews_update_own` RLS policy. [keepPhotoUrls] are photos already on
  /// the review the user chose not to remove; [newPhotos] are fresh picks
  /// to upload, appended after them — together they replace `photo_urls`
  /// outright, since there's no way to patch an array column in place.
  Future<void> updateReview({
    required String reviewId,
    required int rating,
    required String body,
    List<String> keepPhotoUrls = const [],
    List<(Uint8List bytes, String extension)> newPhotos = const [],
  }) async {
    final newUrls = await Future.wait(
      newPhotos.map((p) => _uploadReviewPhoto(bytes: p.$1, extension: p.$2)),
    );
    final photoUrls = [...keepPhotoUrls, ...newUrls];

    final updated = await _client
        .from('reviews')
        .update({
          'rating': rating,
          'body': body.trim(),
          'photo_urls': photoUrls.isEmpty ? null : photoUrls,
        })
        .eq('id', reviewId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        'Review update for "$reviewId" matched no row — it may not exist, '
        'or an RLS policy is blocking the write.',
      );
    }
  }

  /// Uploads one review photo to the `review-media` bucket under
  /// `<uid>/<timestamp>-<n>.<ext>` and returns its public URL. The random
  /// suffix (rather than just a timestamp, as [_uploadPostMedia] uses) is
  /// needed because a review can attach several photos picked in the same
  /// batch, which can otherwise collide on the same millisecond.
  Future<String> _uploadReviewPhoto({
    required Uint8List bytes,
    required String extension,
  }) async {
    final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage
        .from('review-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(extension, 'image'),
          ),
        );
    return _client.storage.from('review-media').getPublicUrl(path);
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
