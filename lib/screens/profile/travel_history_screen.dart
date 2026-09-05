import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/locale_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../trip/trip_details_screen.dart';

const _historyGradients = [
  AppColors.horizon,
  AppColors.lagoon,
  AppColors.dusk,
  AppColors.sunset,
];

const _historyIcons = [
  Icons.flight_takeoff_rounded,
  Icons.beach_access_rounded,
  Icons.location_city_rounded,
  Icons.terrain_rounded,
];

List<Color> _gradientFor(int index) =>
    _historyGradients[index % _historyGradients.length];

IconData _iconFor(int index) => _historyIcons[index % _historyIcons.length];

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  final _tripService = TripService();
  List<Trip>? _pastTrips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final trips = await _tripService.myTrips();
      final past = trips.where((t) => t.status == TripStatus.past).toList()
        ..sort((a, b) {
          final aEnd = a.endDate ?? a.createdAt;
          final bEnd = b.endDate ?? b.createdAt;
          return bEnd.compareTo(aEnd);
        });
      if (!mounted) return;
      setState(() => _pastTrips = past);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pastTrips = _pastTrips;
    final placesVisited = pastTrips == null
        ? 0
        : {
            for (final t in pastTrips)
              if (t.destination.isNotEmpty) t.destination,
          }.length;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_travel_history'),
              subtitle: pastTrips == null || pastTrips.isEmpty
                  ? null
                  : '${pastTrips.length} '
                        '${pastTrips.length == 1 ? tr('trip_word_singular') : tr('trip_word_plural')} '
                        '· $placesVisited ${tr('auth_history_places_visited_suffix')}',
            ),
            Expanded(
              child: _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : pastTrips == null
                  ? const Center(child: CircularProgressIndicator())
                  : pastTrips.isEmpty
                  ? const _EmptyHistory()
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: pastTrips.length,
                      itemBuilder: (context, index) {
                        final trip = pastTrips[index];
                        final isLast = index == pastTrips.length - 1;
                        final gradient = _gradientFor(index);
                        final icon = _iconFor(index);
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
                                      gradient: LinearGradient(
                                        colors: gradient,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        margin: EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
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
                                  padding: EdgeInsets.only(
                                    bottom: isLast ? 0 : 20,
                                  ),
                                  child: Material(
                                    color: context.colors.card,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              TripDetailsScreen(trip: trip),
                                        ),
                                      ),
                                      child: Container(
                                        padding: EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: context.colors.ink
                                                  .withValues(alpha: 0.05),
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
                                                  colors: gradient,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              alignment: Alignment.center,
                                              child: Icon(
                                                icon,
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
                                                    trip.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: context.colors.ink,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                  SizedBox(height: 3),
                                                  Text(
                                                    '${trip.routeLabel ?? trip.destination}\n'
                                                    '${trip.dateRangeLabel}',
                                                    style: TextStyle(
                                                      color:
                                                          context.colors.muted,
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, color: context.colors.muted, size: 44),
            const SizedBox(height: 16),
            Text(
              tr('auth_history_empty_title'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('auth_history_empty_subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load your travel history',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
