import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../trip/trip_details_screen.dart';

List<({String title, String place, String dates, List<Color> gradient, IconData icon})> _travelHistory() => [
  (
    title: tr('saved_trip1_title'),
    place: tr('home_demo_destination'),
    dates: 'Aug 14 – Aug 16, 2026',
    gradient: AppColors.horizon,
    icon: Icons.location_city_rounded,
  ),
  (
    title: tr('auth_history_trip_langkawi'),
    place: tr('auth_history_place_langkawi'),
    dates: 'Mar 2 – Mar 5, 2026',
    gradient: AppColors.lagoon,
    icon: Icons.beach_access_rounded,
  ),
  (
    title: tr('auth_history_trip_kl_weekend'),
    place: tr('auth_history_place_kl'),
    dates: 'Jan 18 – Jan 19, 2026',
    gradient: AppColors.dusk,
    icon: Icons.location_city_rounded,
  ),
  (
    title: tr('auth_history_trip_malacca'),
    place: tr('auth_history_place_malacca'),
    dates: 'Nov 8, 2025',
    gradient: AppColors.sunset,
    icon: Icons.church_rounded,
  ),
];

/// Past trips with a quick summary of the traveler's journey stats.
class TravelHistoryScreen extends StatelessWidget {
  const TravelHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = _travelHistory();
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_travel_history'),
              subtitle: '4 ${tr('trip_word_plural')} · 3 ${tr('auth_history_states_visited_suffix')}',
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final t = history[index];
                  final isLast = index == history.length - 1;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: t.gradient),
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  margin: EdgeInsets.symmetric(vertical: 4),
                                  color: context.colors.muted.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                            child: Material(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () async {
                                  final tripId = await TripService()
                                      .ensureDemoTrip();
                                  final trip = await TripService().getTrip(
                                    tripId,
                                  );
                                  if (!context.mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TripDetailsScreen(trip: trip),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: context.colors.ink.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: t.gradient,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          t.icon,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.title,
                                              style: TextStyle(
                                                color: context.colors.ink,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            SizedBox(height: 3),
                                            Text(
                                              '${t.place}\n${t.dates}',
                                              style: TextStyle(
                                                color: context.colors.muted,
                                                fontSize: 11.5,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
