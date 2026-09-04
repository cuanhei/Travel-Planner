import 'package:flutter/material.dart';

import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../explore/explore_tab.dart';
import '../explore/place_details_screen.dart';

/// Bookmarked places, grouped as a simple grid.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final _saved = {places[0].name, places[2].name, places[3].name};

  /// Live average rating + review count per destination name — see
  /// `_ExploreTabState._ratingsStream` in `explore_tab.dart` for why this
  /// is a stream rather than a one-shot fetch.
  late final Stream<Map<String, ({double average, int count})>> _ratingsStream =
      CommunityService().watchRatingSummaries(
        places.map((p) => p.name).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final results = places.where((p) => _saved.contains(p.name)).toList();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Saved Places',
              subtitle: 'Your bookmarked spots',
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No saved places yet',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : StreamBuilder<Map<String, ({double average, int count})>>(
                      stream: _ratingsStream,
                      builder: (context, snapshot) {
                        final ratings = snapshot.data ?? const {};
                        return GridView.builder(
                          padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                          itemCount: results.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.82,
                              ),
                          itemBuilder: (context, index) {
                            final p = results[index];
                            final rating = ratings[p.name];
                            final displayRating = rating?.average ?? 0.0;
                            final displayCount = rating?.count ?? 0;
                            return GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PlaceDetailsScreen(place: p),
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: context.colors.card,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.colors.ink.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 12,
                                      offset: Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          height: 100,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: p.gradient,
                                            ),
                                            borderRadius: BorderRadius.vertical(
                                              top: Radius.circular(20),
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            p.icon,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: GestureDetector(
                                            onTap: () => setState(
                                              () => _saved.remove(p.name),
                                            ),
                                            child: Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.bookmark_rounded,
                                                size: 14,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: context.colors.ink,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.star_rounded,
                                                color: Color(0xFFFFB347),
                                                size: 13,
                                              ),
                                              Text(
                                                '${displayRating.toStringAsFixed(1)} ($displayCount)',
                                                style: TextStyle(
                                                  color: context.colors.muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
