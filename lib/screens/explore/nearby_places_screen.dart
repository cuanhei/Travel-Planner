import 'package:flutter/material.dart';

import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'explore_tab.dart';
import 'place_details_screen.dart';

/// Places sorted by proximity to the traveler's current (dummy) location.
class NearbyPlacesScreen extends StatefulWidget {
  const NearbyPlacesScreen({super.key});

  @override
  State<NearbyPlacesScreen> createState() => _NearbyPlacesScreenState();
}

class _NearbyPlacesScreenState extends State<NearbyPlacesScreen> {
  /// Live average rating + review count per destination name — see
  /// `_ExploreTabState._ratingsStream` in `explore_tab.dart` for why this
  /// is a stream rather than a one-shot fetch.
  late final Stream<Map<String, ({double average, int count})>> _ratingsStream =
      CommunityService().watchRatingSummaries(
        places.map((p) => p.name).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final sorted = [...places]
      ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Nearby Places',
              subtitle: 'Sorted by distance from you',
            ),
            Expanded(
              child: StreamBuilder<Map<String, ({double average, int count})>>(
                stream: _ratingsStream,
                builder: (context, snapshot) {
                  final ratings = snapshot.data ?? const {};
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final p = sorted[index];
                      final rating = ratings[p.name];
                      final displayRating = rating?.average ?? 0.0;
                      final displayCount = rating?.count ?? 0;
                      return Material(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlaceDetailsScreen(place: p),
                            ),
                          ),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
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
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: p.gradient,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    p.icon,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        p.area,
                                        style: TextStyle(
                                          color: context.colors.muted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${p.distanceKm} km',
                                      style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
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
                              ],
                            ),
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
