import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place_environment.dart';
import '../../models/trip_schedule.dart';
import '../../models/trip_schedule_input.dart';
import '../../services/stop_weather_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/opening_hours_check.dart';
import '../../utils/weather_display.dart';
import '../../widgets/detail_header.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatShortDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

/// Parses Postgres' canonical "HH:MM:SS" `time` text into minutes since
/// midnight — null (falls back to the caller's own default) if [value]
/// is null or unparseable.
int? _minutesFromTimeString(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

String _minutesToClock(int minutesSinceMidnight) {
  final wrapped = minutesSinceMidnight % (24 * 60);
  final normalized = wrapped < 0 ? wrapped + 24 * 60 : wrapped;
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String _durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}hr';
  return '${h}hr ${m}min';
}

String _travelLabel(TripScheduleLeg leg) {
  final minutes = leg.durationMinutes;
  if (minutes == null) return 'Travel time unavailable';
  return minutes < 1 ? 'Travel < 1 min' : 'Travel $minutes min';
}

String _environmentLabel(PlaceEnvironment env) {
  switch (env) {
    case PlaceEnvironment.indoor:
      return 'Indoor';
    case PlaceEnvironment.outdoor:
      return 'Outdoor';
    case PlaceEnvironment.mixed:
      return 'Indoor / Outdoor';
    case PlaceEnvironment.unknown:
      return 'Unknown';
  }
}

/// Read-only view of a trip's saved schedule — every day tab, each with
/// its vertical timeline of origin → stops → accommodation/trip-end,
/// travel legs, and weather flags, exactly as saved by Create Trip's
/// `saveTripSchedule`. No editing, reordering, or optimizing here — this
/// is a plain "what did we plan" view, not a second Create Trip flow.
class DailyTimelineScreen extends StatefulWidget {
  const DailyTimelineScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen> {
  final _tripService = TripService();
  final _stopWeatherService = StopWeatherService();

  TripSchedule? _schedule;
  bool _loading = true;
  String? _error;
  int _selectedDay = 0;

  /// Freshly-checked weather per stop, keyed by identity — supersedes the
  /// snapshot saved on [TripScheduleStop] at Create Trip time (which goes
  /// stale the moment MET Malaysia's forecast updates, or the trip's
  /// dates approach and fall inside the forecast window for the first
  /// time). Null while a stop's check is still in flight.
  final Map<TripScheduleStop, StopWeatherCheck?> _liveWeather = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedule = await _tripService.getTripSchedule(widget.tripId);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
        if (_selectedDay >= schedule.days.length) _selectedDay = 0;
      });
      unawaited(_checkWeather(schedule));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Live-checks every outdoor/mixed stop, across every day, against the
  /// current forecast — one at a time, updating as each resolves, rather
  /// than trusting the saved-at-creation snapshot forever.
  Future<void> _checkWeather(TripSchedule schedule) async {
    for (final day in schedule.days) {
      if (!StopWeatherService.isWithinForecastWindow(day.date)) continue;
      for (final stop in day.stops) {
        final env = stop.location.environment;
        if (env != PlaceEnvironment.outdoor && env != PlaceEnvironment.mixed) {
          continue;
        }
        if (!mounted) return;
        setState(() => _liveWeather[stop] = null);
        final result = await _stopWeatherService.check(
          position: LatLng(stop.location.latitude, stop.location.longitude),
          date: day.date,
          arrivalMinutes: stop.arrivalMinutes,
          endMinutes: stop.endMinutes,
        );
        if (!mounted) return;
        setState(() => _liveWeather[stop] = result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Daily Timeline',
              subtitle: 'Your saved day-by-day schedule',
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final schedule = _schedule!;
    if (schedule.days.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _DayTabBar(
          days: schedule.days,
          selected: _selectedDay,
          onSelect: (i) => setState(() => _selectedDay = i),
        ),
        const SizedBox(height: 16),
        _DayScheduleCard(
          day: schedule.days[_selectedDay],
          fallbackStartTime: schedule.tripStartTime,
          liveWeather: _liveWeather,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_rounded,
              color: context.colors.muted,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              'No saved schedule yet',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This trip has no day-by-day timeline saved.',
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.muted,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load the schedule',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 14,
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

class _DayTabBar extends StatelessWidget {
  const _DayTabBar({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<TripScheduleDay> days;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(i),
            child: Container(
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : context.colors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Day ${days[i].dayNumber}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatShortDate(days[i].date),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.9)
                          : context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayScheduleCard extends StatelessWidget {
  const _DayScheduleCard({
    required this.day,
    required this.fallbackStartTime,
    required this.liveWeather,
  });

  final TripScheduleDay day;

  /// The trip's own start time ("HH:MM:SS"), used when this day has no
  /// override of its own.
  final String? fallbackStartTime;

  final Map<TripScheduleStop, StopWeatherCheck?> liveWeather;

  @override
  Widget build(BuildContext context) {
    final startMinutes =
        _minutesFromTimeString(day.startTimeOverride) ??
        _minutesFromTimeString(fallbackStartTime) ??
        8 * 60;
    final legs = day.legs;
    final stops = day.stops;
    final originLabel = legs.isNotEmpty
        ? legs.first.fromName
        : 'Starting point';
    final trailingLeg = legs.length > stops.length ? legs.last : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day ${day.dayNumber} — ${_formatShortDate(day.date)}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _OriginNode(time: _minutesToClock(startMinutes), label: originLabel),
          for (var i = 0; i < stops.length; i++) ...[
            if (i < legs.length) _TravelConnector(leg: legs[i]),
            _StopNode(
              stop: stops[i],
              date: day.date,
              liveWeather: liveWeather[stops[i]],
            ),
          ],
          if (trailingLeg != null) ...[
            _TravelConnector(leg: trailingLeg),
            _TrailingNode(leg: trailingLeg),
          ],
          if (stops.isEmpty && trailingLeg == null) ...[
            const SizedBox(height: 8),
            Text(
              'No stops planned for this day.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OriginNode extends StatelessWidget {
  const _OriginNode({required this.time, required this.label});
  final String time;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            time,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.flag_circle_rounded,
          color: AppColors.accent,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _TravelConnector extends StatelessWidget {
  const _TravelConnector({required this.leg});
  final TripScheduleLeg leg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 52),
          const SizedBox(width: 10),
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 16,
            color: context.colors.muted,
          ),
          const SizedBox(width: 6),
          Text(
            _travelLabel(leg),
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            leg.transportMode == 'transit'
                ? Icons.directions_bus_filled_rounded
                : Icons.directions_car_rounded,
            size: 13,
            color: context.colors.muted,
          ),
        ],
      ),
    );
  }
}

class _StopNode extends StatelessWidget {
  const _StopNode({required this.stop, required this.date, this.liveWeather});
  final TripScheduleStop stop;
  final DateTime date;

  /// Null while a live check is in flight (or hasn't started) — falls
  /// back to [stop]'s saved-at-creation snapshot in that case.
  final StopWeatherCheck? liveWeather;

  @override
  Widget build(BuildContext context) {
    final location = stop.location;
    final env = location.environment;
    final hours = location.openingHours;
    final permanentlyClosed = location.businessStatus == 'CLOSED_PERMANENTLY';
    final closedNow =
        !permanentlyClosed &&
        isClosedDuringVisit(
          periods: location.openingHoursPeriods,
          date: date,
          arrivalMinutes: stop.arrivalMinutes,
          endMinutes: stop.endMinutes,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            _minutesToClock(stop.arrivalMinutes),
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.trip_origin, color: AppColors.accent, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      location.categoryIcon,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.name,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _Tag(_environmentLabel(env)),
                              _Tag(location.category),
                              if (location.businessStatus ==
                                  'CLOSED_PERMANENTLY')
                                _Tag('Permanently closed', warning: true),
                              if (location.businessStatus ==
                                  'CLOSED_TEMPORARILY')
                                _Tag('Temporarily closed', warning: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Visit: ${_durationLabel(stop.visitMinutes)} · Ends ${_minutesToClock(stop.endMinutes)}',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                if (hours != null && hours.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: context.colors.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hours.first,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (permanentlyClosed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.block_rounded,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This place is permanently closed — you may want to rearrange this stop.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (closedNow)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Closed at this scheduled time — try another day or time.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (env == PlaceEnvironment.outdoor ||
                    env == PlaceEnvironment.mixed) ...[
                  const SizedBox(height: 6),
                  _WeatherRow(stop: stop, live: liveWeather),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeatherRow extends StatelessWidget {
  const _WeatherRow({required this.stop, required this.live});
  final TripScheduleStop stop;

  /// The freshly re-checked result — null while a check is still in
  /// flight (or before one's started), in which case the saved-at-Create-
  /// Trip snapshot on [stop] is shown as a fallback instead.
  final StopWeatherCheck? live;

  @override
  Widget build(BuildContext context) {
    if (live != null && live!.isResolved) {
      return _row(
        context,
        phrase: live!.forecast!.summaryForecast,
        flagged: live!.isBad,
        badPeriods: live!.badPeriods.map((p) => p.name).toList(),
        checkedNowLabel: true,
      );
    }

    final phrase = stop.weatherForecastPhrase;
    if (phrase == null) {
      return Row(
        children: [
          if (live == null) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 8),
            Text(
              'Checking current weather…',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            Icon(
              Icons.cloud_off_rounded,
              size: 14,
              color: context.colors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              'No forecast available for this stop',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      );
    }
    return _row(
      context,
      phrase: phrase,
      flagged: stop.weatherFlagged,
      badPeriods: stop.weatherBadPeriods,
      checkedNowLabel: false,
    );
  }

  Widget _row(
    BuildContext context, {
    required String phrase,
    required bool flagged,
    required List<String> badPeriods,
    required bool checkedNowLabel,
  }) {
    if (flagged) {
      final periods = badPeriods.map(_capitalize).join(' & ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(weatherIconFor(phrase), size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Weather: ${translateWeather(phrase)}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (periods.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                checkedNowLabel
                    ? 'Rain is currently forecast in the $periods.'
                    : 'Rain was forecast in the $periods when this trip was saved.',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(weatherIconFor(phrase), size: 14, color: context.colors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Weather: ${translateWeather(phrase)} — suitable',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _TrailingNode extends StatelessWidget {
  const _TrailingNode({required this.leg});
  final TripScheduleLeg leg;

  @override
  Widget build(BuildContext context) {
    final isAccommodation = leg.legKind == TripLegKind.accommodation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 52),
        const SizedBox(width: 10),
        Icon(
          isAccommodation ? Icons.hotel_rounded : Icons.flag_rounded,
          color: isAccommodation
              ? const Color(0xFF1E88E5)
              : const Color(0xFFE53935),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isAccommodation
                ? 'Stay — ${leg.toName}'
                : 'Trip Ends — ${leg.toName}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warning = false});
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? Colors.red : context.colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
