import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/malaysia_city.dart';
import '../../models/trip_stop_location.dart';
import '../../services/route_optimizer.dart';
import '../../services/schedule_builder.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place;
import 'edit_schedule_screen.dart';
import 'trip_data.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
final _malaysiaBounds = LatLngBounds(
  const LatLng(0.5, 99.5),
  const LatLng(7.5, 119.5),
);
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// One color per day, cycled if there are more days than colors — lets the
/// map and list agree on "everything tagged this color belongs to day N".
const _dayColors = [
  Color(0xFF11998E),
  Color(0xFFFF7A59),
  Color(0xFF5C6BC0),
  Color(0xFFE0439A),
  Color(0xFF8E63CE),
  Color(0xFFCB9B2A),
];

class _WeatherOption {
  const _WeatherOption(this.label, this.icon, this.color, this.goodForOutdoor);
  final String label;
  final IconData icon;
  final Color color;
  final bool goodForOutdoor;
}

const _weatherOptions = [
  _WeatherOption('Sunny', Icons.wb_sunny_rounded, Color(0xFFFFB347), true),
  _WeatherOption(
    'Partly Cloudy',
    Icons.wb_cloudy_rounded,
    Color(0xFF2E9CCA),
    true,
  ),
  _WeatherOption('Rain Showers', Icons.grain_rounded, Color(0xFF5C6BC0), false),
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
    this.realStops = const [],
    this.startLabel,
    this.startPoint,
    this.endLabel,
    this.endPoint,
    this.dayCount = 1,
    this.startDate,
    this.dayStartTime = const TimeOfDay(hour: 9, minute: 0),
    this.startCity,
    this.endCity,
    this.dateRange,
    this.endTime,
    this.totalBudget = 0,
    this.autoRecommend = false,
    this.interests = const {},
  });

  final String tripName;
  final String description;
  final List<Place> places;
  final Set<String> recommendedNames;

  /// Real, geocoded stops from the map/search picker. When these (plus
  /// [startPoint]) are available, the screen shows the real hotel-anchored
  /// day plan (see [planDays]) instead of the simulated weather/day-split
  /// below, which only ever applies to the auto-recommend catalog flow.
  final List<TripStopLocation> realStops;
  final String? startLabel;
  final LatLng? startPoint;
  final String? endLabel;
  final LatLng? endPoint;
  final int dayCount;
  final DateTime? startDate;

  /// Time each day departs its hotel (or the trip's starting point, for
  /// the no-hotel fallback) — used to build the real day schedule.
  final TimeOfDay dayStartTime;

  /// The rest of the Create Trip form's raw input — this screen is what
  /// actually saves it all (see [TripService.createTrip]) once the
  /// traveler confirms with "Save Trip", having previewed the schedule.
  final MalaysiaCity? startCity;
  final MalaysiaCity? endCity;
  final DateTimeRange? dateRange;
  final TimeOfDay? endTime;
  final double totalBudget;
  final bool autoRecommend;
  final Set<String> interests;

  bool get _hasRealPlan => realStops.isNotEmpty && startPoint != null;

  static const _placesPerDay = 2;

  List<_DayPlan> _buildSchedule() {
    final dayCount = math.max(1, (places.length / _placesPerDay).ceil());
    final dayWeather = List.generate(
      dayCount,
      (i) => _weatherOptions[i % _weatherOptions.length],
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
                  ? 'Scheduled for clear weather'
                  : 'Rain possible — bring a light jacket')
            : 'Indoor-friendly, weather-flexible pick';
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
        'Walk',
        Icons.directions_walk_rounded,
        '${math.max(4, (delta * 12).round())} min',
      );
    } else if (delta < 6) {
      return _TransportLeg(
        'Rapid Penang Bus',
        Icons.directions_bus_filled_rounded,
        '${math.max(10, (delta * 4).round())} min',
      );
    }
    return _TransportLeg(
      'E-hailing (Grab)',
      Icons.local_taxi_rounded,
      '${math.max(10, (delta * 2.2).round())} min',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasRealPlan) return _RealItineraryView(screen: this);

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
              title: tripName.isEmpty ? 'Optimized Itinerary' : tripName,
              subtitle: description.isEmpty
                  ? 'Ordered by route, weather, and transport'
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
                        label: 'Stops',
                        value: '${places.length}',
                      ),
                      _SummaryStat(
                        icon: Icons.calendar_today_rounded,
                        label: 'Days',
                        value: '${days.length}',
                      ),
                      _SummaryStat(
                        icon: Icons.directions_transit_rounded,
                        label: 'Travel Time',
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
                  _SaveTripButton(
                    tripName: tripName,
                    // No real coordinates in this (catalog-only) flow, so
                    // there's nothing geographic to save beyond the trip
                    // itself — no stops, no schedule.
                    onSave: () => TripService().createTrip(
                      name: tripName.isEmpty ? 'My Trip' : tripName,
                      description: description,
                      startCity: startCity,
                      endCity: endCity,
                      dateRange: dateRange,
                      startTime: dateRange == null ? null : dayStartTime,
                      endTime: dateRange == null ? null : endTime,
                      totalBudget: totalBudget,
                      autoRecommend: autoRecommend,
                      interests: interests,
                      stops: const [],
                    ),
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

/// Real hotel-anchored day plan — shown instead of the simulated
/// weather/day-split view above whenever the trip has real, geocoded
/// stops and a start point (see [OptimizedItineraryScreen._hasRealPlan]).
class _RealItineraryView extends StatelessWidget {
  _RealItineraryView({required this.screen})
    : dayPlans = planDays(dayCount: screen.dayCount, stops: screen.realStops);

  final OptimizedItineraryScreen screen;
  final List<DayPlan> dayPlans;

  /// Each day's plan turned into a real clock schedule — arrival/departure
  /// times per stop and estimated travel legs between them.
  late final List<DaySchedule> daySchedules = [
    for (final plan in dayPlans) buildDaySchedule(plan: plan, startTime: screen.dayStartTime),
  ];

  bool get _hasHotels => dayPlans.any((d) => d.hotel != null);

  double get _totalDistanceKm {
    var total = 0.0;
    for (final plan in dayPlans) {
      final hotel = plan.hotel;
      if (hotel != null) {
        total += routeDistanceKm(
          start: LatLng(hotel.latitude, hotel.longitude),
          orderedStops: plan.stops,
          end: LatLng(hotel.latitude, hotel.longitude),
        );
      } else {
        total += routeDistanceKm(
          start: screen.startPoint!,
          orderedStops: plan.stops,
          end: screen.endPoint,
        );
      }
    }
    return roundKm(total);
  }

  int get _totalStops => dayPlans.fold(0, (sum, d) => sum + d.stops.length);

  String? _dayDateLabel(int dayIndex) {
    final start = screen.startDate;
    if (start == null) return null;
    final date = start.add(Duration(days: dayIndex));
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  Future<String> _save() {
    return TripService().createTrip(
      name: screen.tripName.isEmpty ? 'My Trip' : screen.tripName,
      description: screen.description,
      startCity: screen.startCity,
      endCity: screen.endCity,
      dateRange: screen.dateRange,
      startTime: screen.dateRange == null ? null : screen.dayStartTime,
      endTime: screen.dateRange == null ? null : screen.endTime,
      totalBudget: screen.totalBudget,
      autoRecommend: screen.autoRecommend,
      interests: screen.interests,
      stops: screen.realStops,
      daySchedules: daySchedules,
    );
  }

  List<TripStop> _previewItems() {
    var id = 1;
    final items = <TripStop>[];
    for (final day in daySchedules) {
      final hotel = day.hotel;
      if (hotel != null) {
        items.add(_tripStopFromLocation(
          id: id++,
          location: hotel,
          day: day.day,
          time: day.startTime,
          duration: Duration.zero,
        ));
      }
      for (final scheduled in day.stops) {
        final arrivalMinutes = scheduled.arrival.hour * 60 + scheduled.arrival.minute;
        final departureMinutes =
            scheduled.departure.hour * 60 + scheduled.departure.minute;
        final duration = Duration(
          minutes: (departureMinutes - arrivalMinutes + 24 * 60) % (24 * 60),
        );
        items.add(_tripStopFromLocation(
          id: id++,
          location: scheduled.stop,
          day: day.day,
          time: scheduled.arrival,
          duration: duration,
        ));
      }
      // The day header shows an end time that already accounts for the
      // trip back to the hotel (see `DaySchedule.endTime`) — reflect
      // that same arrival as its own entry, or the preview looks like
      // the day just stops after the last stop with no way back.
      if (hotel != null && day.stops.isNotEmpty) {
        items.add(
          _tripStopFromLocation(
            id: id++,
            location: hotel,
            day: day.day,
            time: day.endTime,
            duration: Duration.zero,
          ).copyWith(name: 'Back to ${hotel.name}'),
        );
      }
    }
    return items;
  }

  TripStop _tripStopFromLocation({
    required int id,
    required TripStopLocation location,
    required int day,
    required TimeOfDay time,
    required Duration duration,
  }) {
    final category = stopCategories.firstWhere(
      (item) => item.label.toLowerCase() == location.category.toLowerCase(),
      orElse: () => stopCategories.first,
    );
    return TripStop(
      id: id,
      name: location.name,
      day: day,
      time: time,
      duration: duration,
      icon: location.category == 'Hotel' ? Icons.hotel_rounded : category.icon,
      gradient: location.category == 'Hotel' ? AppColors.lagoon : category.gradient,
    );
  }

  Future<void> _openSchedulePreview(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditScheduleScreen(
          initialItems: _previewItems(),
          dayCount: screen.dayCount,
          previewMode: true,
          onConfirm: () async {
            await _save();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: context.colors.ink,
                content: Text(
                  screen.tripName.isEmpty
                      ? 'Trip created!'
                      : '"${screen.tripName}" created!',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startPoint = screen.startPoint!;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: screen.tripName.isEmpty ? 'Optimized Itinerary' : screen.tripName,
              subtitle: 'Planned day by day, based near each hotel',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SummaryBar(stopCount: _totalStops, distanceKm: _totalDistanceKm),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _RouteMap(
                    startLabel: screen.startLabel ?? 'Start',
                    startPoint: startPoint,
                    endLabel: screen.endLabel,
                    endPoint: screen.endPoint,
                    dayPlans: dayPlans,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _RouteStopTile(
                    label: screen.startLabel ?? 'Start',
                    subtitle: 'Starting point',
                    icon: Icons.flag_rounded,
                    color: const Color(0xFF11998E),
                    isLast: false,
                  ),
                  for (var d = 0; d < daySchedules.length; d++) ...[
                    if (_hasHotels)
                      _DayHeader(
                        day: daySchedules[d].day,
                        dateLabel: _dayDateLabel(d),
                        hotel: daySchedules[d].hotel,
                        color: _dayColors[d % _dayColors.length],
                        timeRange:
                            '${daySchedules[d].startTime.format(context)} – '
                            '${daySchedules[d].endTime.format(context)}',
                      ),
                    for (final entry in daySchedules[d].stops.asMap().entries) ...[
                      if (entry.value.travelFromPrevious != null)
                        _TransportConnector(
                          leg: _TransportLeg(
                            entry.value.travelFromPrevious!.mode,
                            entry.value.travelFromPrevious!.icon,
                            '${entry.value.travelFromPrevious!.durationMinutes} min',
                          ),
                        ),
                      _RouteStopTile(
                        label: entry.value.stop.name,
                        subtitle: '${entry.value.stop.category} · ${entry.value.stop.address}',
                        // Use one continuous sequence across the entire
                        // route; numbering must not restart at each day.
                        number:
                            daySchedules
                                .take(d)
                                .fold<int>(0, (total, day) => total + day.stops.length) +
                            entry.key +
                            1,
                        color: _hasHotels ? _dayColors[d % _dayColors.length] : null,
                        timeLabel: entry.value.arrival.format(context),
                        isLast: false,
                      ),
                    ],
                  ],
                  if (screen.endLabel != null)
                    _RouteStopTile(
                      label: screen.endLabel!,
                      subtitle: 'Final destination',
                      icon: Icons.sports_score_rounded,
                      color: const Color(0xFFFF7A59),
                      isLast: true,
                    ),
                  const SizedBox(height: 12),
                  _SaveTripButton(
                    tripName: screen.tripName,
                    label: 'Review Schedule',
                    icon: Icons.edit_calendar_rounded,
                    navigateOnly: true,
                    onSave: () async {
                      await _openSchedulePreview(context);
                      return '';
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

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.startLabel,
    required this.startPoint,
    required this.endLabel,
    required this.endPoint,
    required this.dayPlans,
  });

  final String startLabel;
  final LatLng startPoint;
  final String? endLabel;
  final LatLng? endPoint;
  final List<DayPlan> dayPlans;

  @override
  Widget build(BuildContext context) {
    final allPoints = <LatLng>[startPoint];
    for (final plan in dayPlans) {
      for (final stop in plan.stops) {
        allPoints.add(LatLng(stop.latitude, stop.longitude));
      }
    }
    if (endPoint != null) allPoints.add(endPoint!);

    final polylines = <Polyline>[];
    final markers = <Marker>[
      Marker(
        point: startPoint,
        width: 36,
        height: 36,
        child: const _EndpointPin(icon: Icons.flag_rounded, color: Color(0xFF11998E)),
      ),
      if (endPoint != null)
        Marker(
          point: endPoint!,
          width: 36,
          height: 36,
          child: const _EndpointPin(icon: Icons.sports_score_rounded, color: Color(0xFFFF7A59)),
        ),
    ];

    // The map shows the actual journey as one continuous line from the
    // selected starting city, through every optimized stop, to the chosen
    // ending city. Day grouping belongs in the schedule review, not in a
    // route that restarts its numbering at every overnight stay.
    final routeStops = [for (final plan in dayPlans) ...plan.stops];
    polylines.add(
      Polyline(
        points: [
          startPoint,
          for (final stop in routeStops) LatLng(stop.latitude, stop.longitude),
          if (endPoint != null) endPoint!,
        ],
        strokeWidth: 3.5,
        color: AppColors.accent,
      ),
    );
    for (var index = 0; index < routeStops.length; index++) {
      final stop = routeStops[index];
      markers.add(
        Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: 30,
          height: 30,
          child: _NumberedPin(
            number: index + 1,
            color: const Color(0xFF0B1D3A),
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: startPoint,
        initialZoom: 10,
        initialCameraFit: allPoints.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(allPoints),
                padding: const EdgeInsets.all(36),
              )
            : null,
        cameraConstraint: CameraConstraint.contain(bounds: _malaysiaBounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(urlTemplate: _osmTileUrl, userAgentPackageName: _osmUserAgent),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.stopCount, required this.distanceKm});

  final int stopCount;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
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
          Icon(Icons.route_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$stopCount stop${stopCount == 1 ? '' : 's'} · optimized route',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
          Text(
            '~$distanceKm km',
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.dateLabel,
    required this.hotel,
    required this.color,
    this.timeRange,
  });

  final int day;
  final String? dateLabel;
  final TripStopLocation? hotel;
  final Color color;

  /// e.g. "9:00 AM – 6:45 PM", when a real schedule is available.
  final String? timeRange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  dateLabel == null ? 'Day $day' : 'Day $day · $dateLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (hotel != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.hotel_rounded, size: 14, color: context.colors.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          hotel!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (timeRange != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                timeRange!,
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EndpointPin extends StatelessWidget {
  const _EndpointPin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _NumberedPin extends StatelessWidget {
  const _NumberedPin({required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  const _RouteStopTile({
    required this.label,
    required this.subtitle,
    required this.isLast,
    this.number,
    this.icon,
    this.color,
    this.timeLabel,
  });

  final String label;
  final String subtitle;
  final bool isLast;
  final int? number;
  final IconData? icon;
  final Color? color;

  /// e.g. "10:20 AM", when this tile represents a scheduled stop.
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? context.colors.ink;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: icon != null
                    ? Icon(icon, color: Colors.white, size: 15)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: context.colors.muted.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (timeLabel != null)
                        Text(
                          timeLabel!,
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: context.colors.muted, fontSize: 12),
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

/// "Save Trip" button that actually performs the save — this preview
/// screen is where the trip, its stops, and its schedule are first
/// written to Supabase (see [TripService.createTrip]), not Create Trip
/// itself, so the traveler can review the plan before anything's stored.
class _SaveTripButton extends StatefulWidget {
  const _SaveTripButton({
    required this.tripName,
    required this.onSave,
    this.label = 'Save Trip',
    this.icon = Icons.bookmark_added_rounded,
    this.navigateOnly = false,
  });

  final String tripName;
  final Future<String> Function() onSave;
  final String label;
  final IconData icon;
  final bool navigateOnly;

  @override
  State<_SaveTripButton> createState() => _SaveTripButtonState();
}

class _SaveTripButtonState extends State<_SaveTripButton> {
  bool _saving = false;

  Future<void> _handleTap() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save trip: $e'),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (widget.navigateOnly) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text(
          widget.tripName.isEmpty
              ? 'Trip saved to My Trips!'
              : '"${widget.tripName}" saved to My Trips!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      label: widget.label,
      icon: widget.icon,
      loading: _saving,
      onPressed: _saving ? () {} : _handleTap,
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
                  'Day ${day.dayNumber}',
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 10,
                              color: Color(0xFF8E63CE),
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Added for you',
                              style: TextStyle(
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
