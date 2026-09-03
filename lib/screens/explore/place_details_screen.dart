import 'package:flutter/material.dart';

import '../../models/place_review.dart';
import '../../services/community_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../community/add_review_screen.dart';
import '../community/review_details_screen.dart';
import '../trip/add_to_trip_screen.dart';
import 'explore_tab.dart';

/// Full place profile: hero, tags, description, opening hours, and a
/// reviews preview linking into the Community module. The rating shown
/// throughout is the live average from `reviews` (via [CommunityService
/// .watchReviews]) once this place has any, falling back to [Place]'s seed
/// rating/count until then (see [_PlaceDetailsScreenState.build]).
class PlaceDetailsScreen extends StatefulWidget {
  const PlaceDetailsScreen({super.key, required this.place});

  final Place place;

  @override
  State<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}

class _PlaceDetailsScreenState extends State<PlaceDetailsScreen> {
  bool _saved = false;
  final _service = CommunityService();

  /// Whether the user can review this place — only once they've actually
  /// visited it on a completed trip (see [TripService.hasVisited]).
  /// Defaults to not-yet-eligible while loading, so the button doesn't
  /// briefly flash enabled before the check comes back.
  bool _canReview = false;

  @override
  void initState() {
    super.initState();
    TripService().hasVisited(widget.place.name).then((canReview) {
      if (mounted) setState(() => _canReview = canReview);
    });
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    return StreamBuilder<List<PlaceReview>>(
      stream: _service.watchReviews(place.name),
      builder: (context, snapshot) {
        // Falls back to the destination's seed rating/count until real
        // reviews load, and forever if it has none yet — see
        // [_ExploreTabState._ratings] for why (an empty "0.0 · 0 reviews"
        // header would look broken for a place nobody's reviewed yet).
        final reviews = snapshot.data;
        final rating = reviews == null || reviews.isEmpty
            ? place.rating
            : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                  reviews.length;
        final reviewCount = reviews == null || reviews.isEmpty
            ? place.reviews
            : reviews.length;
        return _PlaceDetailsBody(
          place: place,
          rating: rating,
          reviewCount: reviewCount,
          saved: _saved,
          onToggleSaved: () => setState(() => _saved = !_saved),
          canReview: _canReview,
        );
      },
    );
  }
}

class _PlaceDetailsBody extends StatelessWidget {
  const _PlaceDetailsBody({
    required this.place,
    required this.rating,
    required this.reviewCount,
    required this.saved,
    required this.canReview,
    required this.onToggleSaved,
  });

  final Place place;
  final double rating;
  final int reviewCount;
  final bool saved;
  final bool canReview;
  final VoidCallback onToggleSaved;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: place.gradient.last,
            leading: Padding(
              padding: EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.25),
                  child: IconButton(
                    onPressed: onToggleSaved,
                    icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: place.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  place.icon,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 72,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: context.colors.muted,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        place.area,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      _Tag(label: place.category),
                      SizedBox(width: 8),
                      Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFB347),
                        size: 18,
                      ),
                      SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        ' ($reviewCount)',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  Text(
                    'About',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    place.description,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          color: AppColors.accent,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Open today · 9:00 AM – 10:00 PM',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppColors.accent,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Average budget',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${place.avgBudget} / person',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        'Reviews',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ReviewDetailsScreen(placeName: place.name),
                          ),
                        ),
                        child: Text(
                          'See all',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFB347),
                        size: 20,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '${rating.toStringAsFixed(1)} out of 5',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        ' from $reviewCount reviews',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: canReview ? 1 : 0.5,
                          child: GradientButton(
                            label: 'Add Review',
                            icon: Icons.rate_review_rounded,
                            colors: AppColors.dusk,
                            height: 48,
                            onPressed: () {
                              if (!canReview) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                      'You can review a destination after '
                                      "visiting it on a trip that's "
                                      'finished.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AddReviewScreen(placeName: place.name),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: 'Add to Trip',
                          icon: Icons.playlist_add_check_rounded,
                          height: 48,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AddToTripScreen(place: place),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
