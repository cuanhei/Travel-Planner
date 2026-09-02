import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../trip/trip_details_screen.dart';

/// Bookmarked / saved itineraries (draft or inspiration trips).
class SavedTripsScreen extends StatelessWidget {
  const SavedTripsScreen({super.key});

  List<
    ({
      String title,
      String place,
      String dates,
      List<Color> gradient,
      IconData icon,
    })
  >
  get _trips => [
    (
      title: tr('saved_trip1_title'),
      place: 'Penang, Malaysia',
      dates: 'Aug 14 – Aug 16',
      gradient: AppColors.horizon,
      icon: Icons.location_city_rounded,
    ),
    (
      title: tr('saved_trip2_title'),
      place: 'Ipoh, Malaysia',
      dates: tr('saved_trip_draft'),
      gradient: AppColors.dusk,
      icon: Icons.coffee_rounded,
    ),
    (
      title: tr('saved_trip3_title'),
      place: 'Sabah, Malaysia',
      dates: tr('saved_trip_draft'),
      gradient: AppColors.lagoon,
      icon: Icons.forest_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('saved_trips_title'),
              subtitle: tr('saved_trips_subtitle'),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: _trips.length,
                itemBuilder: (context, index) {
                  final t = _trips[index];
                  return Material(
                    color: context.colors.card,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TripDetailsScreen()),
                      ),
                      child: Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
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
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: t.gradient),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                t.icon,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    style: TextStyle(
                                      color: context.colors.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    '${t.place} · ${t.dates}',
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.bookmark_rounded,
                              color: AppColors.accent,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
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
