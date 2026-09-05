class PlaceReview {
  const PlaceReview({
    required this.id,
    required this.placeName,
    required this.authorId,
    required this.authorName,
    required this.authorColor,
    this.authorAvatarUrl,
    required this.rating,
    required this.body,
    required this.createdAt,
    this.photoUrls = const [],
  });

  final String id;
  final String placeName;
  final String authorId;
  final String authorName;
  final int authorColor;
  final String? authorAvatarUrl;
  final int rating;
  final String body;
  final DateTime createdAt;
  final List<String> photoUrls;

  factory PlaceReview.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return PlaceReview(
      id: map['id'] as String,
      placeName: map['place_name'] as String,
      authorId: map['author_id'] as String,
      authorName: profile['display_name'] as String,
      authorColor: profile['avatar_color'] as int,
      authorAvatarUrl: profile['avatar_url'] as String?,
      rating: map['rating'] as int,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      photoUrls:
          (map['photo_urls'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}
