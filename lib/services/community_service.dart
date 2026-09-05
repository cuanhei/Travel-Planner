import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_feed_event.dart';
import '../models/community_post.dart';
import '../models/place_review.dart';
import '../models/post_comment.dart';
import 'supabase_config.dart';

class CommunityService {
  CommunityService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<Map<String, dynamic>?> getMyProfile() async {
    return _client
        .from('profiles')
        .select('display_name, avatar_color, avatar_url')
        .eq('id', _uid)
        .maybeSingle();
  }

  Future<List<CommunityPost>> _hydratePosts(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return <CommunityPost>[];

    final userIds = rows.map((r) => r['author_id'] as String).toSet().toList();
    final postIds = rows.map((r) => r['id'] as String).toList();

    final profiles = await _client
        .from('profiles')
        .select('id, display_name, avatar_color, avatar_url')
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

    await _client.from('posts').insert({
      'author_id': _uid,
      'place_name': placeName.trim(),
      'caption': caption.trim(),
      'category': category,
      'cover_gradient': coverGradient,
      if (uploaded.isNotEmpty) ...{
        'media_urls': uploaded,
        'media_types': [for (final m in media) m.$3],
      },
    });
  }

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

    try {
      await _client.from('post_likes').insert({
        'post_id': postId,
        'user_id': _uid,
        'reaction_type': reactionType,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

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

  Future<int> myReviewCount(String placeName) async {
    final rows = await _client
        .from('reviews')
        .select('id')
        .eq('place_name', placeName)
        .eq('author_id', _uid);
    return rows.length;
  }

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
