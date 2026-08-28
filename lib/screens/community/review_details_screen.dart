import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/detail_header.dart';
import 'add_review_screen.dart';
import 'community_tab.dart';

/// Full review list for a place, with a rating breakdown and an entry
/// point to add a new review.
class ReviewDetailsScreen extends StatelessWidget {
  const ReviewDetailsScreen({super.key, required this.placeName});

  final String placeName;

  static final _reviews = [
    Review(
      author: 'Mei Ling',
      avatarColor: Color(0xFFFF7A59),
      rating: 5,
      date: '2 days ago',
      text:
          'Absolutely stunning, go at sunset for the best light. Loved every minute!',
    ),
    Review(
      author: 'Arif Hakim',
      avatarColor: Color(0xFF5C6BC0),
      rating: 4,
      date: '1 week ago',
      text: 'Great spot, a bit crowded on weekends but still worth it.',
    ),
    Review(
      author: 'Sophia Tan',
      avatarColor: Color(0xFF11998E),
      rating: 5,
      date: '3 weeks ago',
      text:
          'One of the highlights of our whole trip. Highly recommend for photos.',
    ),
    Review(
      author: 'Daniel Wong',
      avatarColor: Color(0xFFFFB347),
      rating: 4,
      date: '1 month ago',
      text: 'Nice experience overall, could use better signage though.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final avg =
        _reviews.map((r) => r.rating).reduce((a, b) => a + b) / _reviews.length;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Reviews', subtitle: placeName),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.ink.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: Offset(0, 5),
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
                              color: Color(0xFFFFB347),
                              size: 16,
                            ),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '${_reviews.length} reviews',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: List.generate(5, (i) {
                          final star = 5 - i;
                          final count = _reviews
                              .where((r) => r.rating.round() == star)
                              .length;
                          final ratio = count / _reviews.length;
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  '$star',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 6,
                                      backgroundColor: context.colors.surface,
                                      valueColor: AlwaysStoppedAnimation(
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
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                itemCount: _reviews.length,
                itemBuilder: (context, index) {
                  final r = _reviews[index];
                  return _ReviewTile(review: r);
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddReviewScreen(placeName: placeName),
                    ),
                  ),
                  icon: Icon(Icons.rate_review_rounded, size: 18),
                  label: Text('Write a Review'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.ink,
                    side: BorderSide(color: context.colors.ink),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: review.avatarColor,
                child: Text(
                  review.author[0],
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.author,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      review.date,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Color(0xFFFFB347),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            review.text,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          SizedBox(height: 8),
          GestureDetector(
            onTap: () => showComingSoon(context, 'Reply'),
            child: Text(
              'Reply',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
