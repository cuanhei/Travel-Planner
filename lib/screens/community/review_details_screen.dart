import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/place_review.dart';
import '../../services/community_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_ago.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/user_avatar.dart';
import 'add_review_screen.dart';

/// Full review list for a place, with a rating breakdown and an entry
/// point to add a new review. Backed by `reviews`.
class ReviewDetailsScreen extends StatefulWidget {
  const ReviewDetailsScreen({super.key, required this.placeName});

  final String placeName;

  @override
  State<ReviewDetailsScreen> createState() => _ReviewDetailsScreenState();
}

class _ReviewDetailsScreenState extends State<ReviewDetailsScreen> {
  final _service = CommunityService();

  /// Whether the user can review this place — true once they have an
  /// unused visit (via [TripService.visitCount]) not yet spent on a review
  /// (via [CommunityService.myReviewCount]).
  bool _canReview = false;

  /// Whether the place has ever been visited at all, once loaded — used to
  /// pick the disabled-button message.
  bool _everVisited = false;

  /// Star rating the user has chosen to filter the list by, via the chip
  /// row — `null` means "All".
  int? _selectedStar;

  @override
  void initState() {
    super.initState();
    _loadCanReview();
  }

  /// Re-checked after `AddReviewScreen` returns (see the "Write a Review"
  /// button below), not just once in [initState] — posting a review spends
  /// the visit that unlocked it, so the button needs to go back to
  /// disabled without requiring the user to leave and reopen this screen.
  Future<void> _loadCanReview() async {
    final results = await Future.wait([
      TripService().visitCount(widget.placeName),
      _service.myReviewCount(widget.placeName),
    ]);
    if (!mounted) return;
    final visits = results[0];
    final reviewsSoFar = results[1];
    setState(() {
      _everVisited = visits > 0;
      _canReview = visits > reviewsSoFar;
    });
  }

  /// Deleting frees up the visit that review spent, so [_loadCanReview] is
  /// re-run afterward the same way it is after `AddReviewScreen` returns —
  /// otherwise "Write a Review" would stay disabled until the traveler left
  /// and reopened this screen.
  Future<void> _confirmDeleteReview(PlaceReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete review?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This review will be removed for everyone.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteReview(review.id);
      await _loadCanReview();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not delete review: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<List<PlaceReview>>(
          stream: _service.watchReviews(widget.placeName),
          builder: (context, snapshot) {
            final reviews = snapshot.data ?? const <PlaceReview>[];
            final avg = reviews.isEmpty
                ? 0.0
                : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                      reviews.length;
            final filteredReviews = _selectedStar == null
                ? reviews
                : reviews
                      .where((r) => r.rating.round() == _selectedStar)
                      .toList();

            return Column(
              children: [
                DetailHeader(title: 'Reviews', subtitle: widget.placeName),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Column(
                          children: [
                            Text(
                              avg.toStringAsFixed(1),
                              style: TextStyle(
                                color: context.colors.ink,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Row(
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < avg.round()
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: const Color(0xFFFFB347),
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            children: List.generate(5, (i) {
                              final star = 5 - i;
                              final count = reviews
                                  .where((r) => r.rating.round() == star)
                                  .length;
                              final ratio = reviews.isEmpty
                                  ? 0.0
                                  : count / reviews.length;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '$star',
                                      style: TextStyle(
                                        color: context.colors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: ratio,
                                          minHeight: 6,
                                          backgroundColor:
                                              context.colors.surface,
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                Color(0xFFFFB347),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _RatingChip(
                          label: 'All',
                          selected: _selectedStar == null,
                          onTap: () => setState(() => _selectedStar = null),
                        ),
                        for (final star in const [5, 4, 3, 2, 1])
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _RatingChip(
                              label: '$star',
                              selected: _selectedStar == star,
                              onTap: () => setState(() => _selectedStar = star),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : reviews.isEmpty
                      ? Center(
                          child: Text(
                            'No reviews yet — be the first!',
                            style: TextStyle(color: context.colors.muted),
                          ),
                        )
                      : filteredReviews.isEmpty
                      ? Center(
                          child: Text(
                            'No $_selectedStar-star reviews.',
                            style: TextStyle(color: context.colors.muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                          itemCount: filteredReviews.length,
                          itemBuilder: (context, index) {
                            final review = filteredReviews[index];
                            return _ReviewTile(
                              review: review,
                              onEdit: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AddReviewScreen(
                                    placeName: widget.placeName,
                                    existingReview: review,
                                  ),
                                ),
                              ),
                              onDelete: () => _confirmDeleteReview(review),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Opacity(
                    opacity: _canReview ? 1 : 0.5,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (!_canReview) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  _everVisited
                                      ? "You've already reviewed this "
                                            'place — visit it again to '
                                            'write another review.'
                                      : 'You can review a destination '
                                            'after visiting it on a trip '
                                            "that's finished.",
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => AddReviewScreen(
                                    placeName: widget.placeName,
                                  ),
                                ),
                              )
                              .then((_) => _loadCanReview());
                        },
                        icon: const Icon(Icons.rate_review_rounded, size: 18),
                        label: const Text('Write a Review'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.ink,
                          side: BorderSide(color: context.colors.ink),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? context.colors.ink : context.colors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            if (label != 'All') ...[
              const SizedBox(width: 4),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: selected ? Colors.white : const Color(0xFFFFB347),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.onEdit,
    required this.onDelete,
  });

  final PlaceReview review;

  /// Opens the review for editing — only shown when [review.authorId]
  /// matches the signed-in user, checked below.
  final VoidCallback onEdit;

  /// Deletes the review — only shown alongside [onEdit], same ownership
  /// check.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isOwnReview =
        review.authorId == Supabase.instance.client.auth.currentUser?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: review.authorName,
                avatarUrl: review.authorAvatarUrl,
                size: 32,
                borderWidth: 0,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.authorName,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      timeAgo(review.createdAt),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwnReview) ...[
                GestureDetector(
                  onTap: onEdit,
                  child: Icon(
                    Icons.edit_outlined,
                    color: context.colors.muted,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: context.colors.muted,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFFFB347),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            review.body,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          if (review.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    review.photoUrls[i],
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 72,
                        height: 72,
                        color: context.colors.surface,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                    errorBuilder: (context, error, stack) => Container(
                      width: 72,
                      height: 72,
                      color: context.colors.surface,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
