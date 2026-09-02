import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place;

class _WeatherOption {
  const _WeatherOption(this.label, this.icon, this.color, this.goodForOutdoor);
  final String label;
  final IconData icon;
  final Color color;
  final bool goodForOutdoor;
}

/// A function (not a `const`/`static final` list) so the weather labels
/// re-run tr() on every call and pick up language changes.
List<_WeatherOption> _weatherOptions() => [
  _WeatherOption(
    tr('trip_weather_sunny'),
    Icons.wb_sunny_rounded,
    const Color(0xFFFFB347),
    true,
  ),
  _WeatherOption(
    tr('trip_weather_partly_cloudy'),
    Icons.wb_cloudy_rounded,
    const Color(0xFF2E9CCA),
    true,
  ),
  _WeatherOption(
    tr('trip_weather_rain_showers'),
    Icons.grain_rounded,
    const Color(0xFF5C6BC0),
    false,
  ),
];

class _TransportLeg {
  const _TransportLeg(this.mode, this.icon, this.duration);
  final String mode;
  final IconData icon;
  final String duration;
}

class _ScheduledStop {
  const _ScheduledStop(this.place, this.reason, this.legFromPrevious);
  final Place place;
  final String reason;
  final _TransportLeg? legFromPrevious;
}

class _DayPlan {
  const _DayPlan(this.dayNumber, this.weather, this.stops);
  final int dayNumber;
  final _WeatherOption weather;
  final List<_ScheduledStop> stops;
}

/// UI-only "smart" result screen for the Choose Places flow: groups the
/// traveler's picked places into days, picks a plausible day-weather fit,
/// orders stops for a shorter path, and suggests transport between them.
/// All logic here is a presentable simulation over local dummy data —
/// there is no real routing, weather, or transit API involved.
class OptimizedItineraryScreen extends StatelessWidget {
  const OptimizedItineraryScreen({
    super.key,
    required this.places,
    this.tripName = '',
    this.description = '',
    this.recommendedNames = const {},
  });

  final String tripName;
  final String description;
  final List<Place> places;
  final Set<String> recommendedNames;

  static const _placesPerDay = 2;

  List<_DayPlan> _buildSchedule() {
    final dayCount = math.max(1, (places.length / _placesPerDay).ceil());
    final weatherOptions = _weatherOptions();
    final dayWeather = List.generate(
      dayCount,
      (i) => weatherOptions[i % weatherOptions.length],
    );

    final outdoor =
        places
            .where((p) => p.category == 'Beach' || p.category == 'Nature')
            .toList()
          ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    final flexible = places.where((p) => !outdoor.contains(p)).toList()
      ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

    final buckets = List.generate(dayCount, (_) => <Place>[]);

    for (final place in outdoor) {
      final dayIndex = _firstAvailable(
        buckets,
        preferGoodWeather: true,
        dayWeather: dayWeather,
      );
      buckets[dayIndex].add(place);
    }
    for (final place in flexible) {
      final dayIndex = _firstAvailable(
        buckets,
        preferGoodWeather: false,
        dayWeather: dayWeather,
      );
      buckets[dayIndex].add(place);
    }

    final days = <_DayPlan>[];
    for (var d = 0; d < dayCount; d++) {
      final dayPlaces = [...buckets[d]]
        ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
      final stops = <_ScheduledStop>[];
      for (var i = 0; i < dayPlaces.length; i++) {
        final place = dayPlaces[i];
        final isOutdoor = outdoor.contains(place);
        final reason = isOutdoor
            ? (dayWeather[d].goodForOutdoor
                  ? tr('trip_reason_clear_weather')
                  : tr('trip_reason_rain_possible'))
            : tr('trip_reason_indoor_flexible');
        _TransportLeg? leg;
        if (i > 0) {
          leg = _legBetween(dayPlaces[i - 1], place);
        }
        stops.add(_ScheduledStop(place, reason, leg));
      }
      days.add(_DayPlan(d + 1, dayWeather[d], stops));
    }
    return days;
  }

  int _firstAvailable(
    List<List<Place>> buckets, {
    required bool preferGoodWeather,
    required List<_WeatherOption> dayWeather,
  }) {
    if (preferGoodWeather) {
      for (var i = 0; i < buckets.length; i++) {
        if (dayWeather[i].goodForOutdoor && buckets[i].length < _placesPerDay) {
          return i;
        }
      }
    }
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].length < _placesPerDay) return i;
    }
    return buckets.length - 1;
  }

  _TransportLeg _legBetween(Place a, Place b) {
    final delta = ((b.distanceKm ?? 0) - (a.distanceKm ?? 0)).abs();
    if (delta < 2) {
      return _TransportLeg(
        tr('trip_transport_walk'),
        Icons.directions_walk_rounded,
        '${math.max(4, (delta * 12).round())} min',
      );
    } else if (delta < 6) {
      return _TransportLeg(
        tr('trip_transport_rapid_bus'),
        Icons.directions_bus_filled_rounded,
        '${math.max(10, (delta * 4).round())} min',
      );
    }
    return _TransportLeg(
      tr('trip_transport_ehailing'),
      Icons.local_taxi_rounded,
      '${math.max(10, (delta * 2.2).round())} min',
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildSchedule();
    final totalLegs = days
        .expand((d) => d.stops)
        .where((s) => s.legFromPrevious != null);
    final totalTravelMinutes = totalLegs.fold<int>(
      0,
      (sum, s) =>
          sum +
          (int.tryParse(s.legFromPrevious!.duration.split(' ').first) ?? 0),
    );

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tripName.isEmpty
                  ? tr('trip_optimized_itinerary_title')
                  : tripName,
              subtitle: description.isEmpty
                  ? tr('trip_optimized_itinerary_subtitle')
                  : description,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Row(
                    children: [
                      _SummaryStat(
                        icon: Icons.flag_rounded,
                        label: tr('trip_stat_stops'),
                        value: '${places.length}',
                      ),
                      _SummaryStat(
                        icon: Icons.calendar_today_rounded,
                        label: tr('trip_stat_days'),
                        value: '${days.length}',
                      ),
                      _SummaryStat(
                        icon: Icons.directions_transit_rounded,
                        label: tr('trip_stat_travel_time'),
                        value: '${totalTravelMinutes}m',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...days.map(
                    (day) => _DaySection(
                      day: day,
                      recommendedNames: recommendedNames,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GradientButton(
                    label: tr('trip_save_trip_button'),
                    icon: Icons.bookmark_added_rounded,
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: context.colors.ink,
                          content: Text(
                            tripName.isEmpty
                                ? tr('trip_trip_saved_generic')
                                : '"$tripName" ${tr('trip_saved_to_my_trips_suffix')}',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accent, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.recommendedNames});

  final _DayPlan day;
  final Set<String> recommendedNames;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: day.weather.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(day.weather.icon, color: day.weather.color, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${tr('trip_day_word')} ${day.dayNumber}',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${day.weather.label}',
                  style: TextStyle(
                    color: day.weather.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < day.stops.length; i++) ...[
            if (day.stops[i].legFromPrevious != null)
              _TransportConnector(leg: day.stops[i].legFromPrevious!),
            _StopCard(
              stop: day.stops[i],
              isRecommended: recommendedNames.contains(day.stops[i].place.name),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransportConnector extends StatelessWidget {
  const _TransportConnector({required this.leg});

  final _TransportLeg leg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 23),
          Container(
            width: 2,
            height: 18,
            color: context.colors.muted.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 14),
          Icon(leg.icon, size: 15, color: context.colors.muted),
          const SizedBox(width: 6),
          Text(
            '${leg.mode} · ${leg.duration}',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop, this.isRecommended = false});

  final _ScheduledStop stop;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final place = stop.place;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: place.gradient),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(place.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isRecommended)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF8E63CE,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 10,
                              color: Color(0xFF8E63CE),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              tr('trip_added_for_you'),
                              style: const TextStyle(
                                color: Color(0xFF8E63CE),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  place.area,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    stop.reason,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
