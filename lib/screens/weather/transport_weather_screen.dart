import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_schedule.dart';
import '../../models/weather_condition.dart';
import '../../models/weather_forecast.dart';
import '../../services/stop_weather_service.dart';
import '../../services/trip_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
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

/// One day's resolved (or unresolvable) forecast, anchored at that day's
/// own starting location rather than the traveler's live GPS position.
class _DayWeather {
  const _DayWeather({
    required this.dayNumber,
    required this.date,
    required this.originName,
    this.areaLabel,
    this.forecast,
    this.unavailableReason,
  });

  final int dayNumber;
  final DateTime date;
  final String originName;

  /// The MET Malaysia area this was actually resolved against (may read
  /// slightly differently from [originName], e.g. "Georgetown" vs
  /// "George Town") — shown alongside it so it's clear where the numbers
  /// came from.
  final String? areaLabel;
  final WeatherForecast? forecast;

  /// Why there's no [forecast] — outside the forecast window, no
  /// starting location for this day, or the lookup itself failed.
  final String? unavailableReason;
}

/// Per-day weather for a trip's own itinerary — unlike [WeatherForecastScreen]
/// (single forecast for wherever the traveler is standing right now), this
/// resolves one forecast per day at *that day's own starting location*
/// (the trip's starting location on Day 1, otherwise the previous night's
/// accommodation — see [TripScheduleLeg.fromName]/[TripScheduleDay.legs]),
/// so a multi-city trip shows "Day 1 (George Town)", "Day 2 (Perlis)", …
/// each against its own local forecast rather than one blanket reading.
class TransportWeatherScreen extends StatefulWidget {
  const TransportWeatherScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TransportWeatherScreen> createState() => _TransportWeatherScreenState();
}

class _TransportWeatherScreenState extends State<TransportWeatherScreen> {
  final _tripService = TripService();
  final _weatherService = WeatherService();

  bool _loading = true;
  String? _error;
  List<_DayWeather> _days = [];

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
      final results = <_DayWeather>[];
      // Consecutive days often share a starting point (e.g. two nights at
      // the same hotel) — cache each resolved window by rounded
      // coordinates so those days don't refetch the same forecast twice.
      final cache = <String, ResolvedWeatherWindow>{};

      for (final day in schedule.days) {
        final origin = day.legs.isNotEmpty ? day.legs.first : null;
        if (origin == null) {
          results.add(
            _DayWeather(
              dayNumber: day.dayNumber,
              date: day.date,
              originName: 'Starting point not set',
              unavailableReason: 'No starting location saved for this day yet.',
            ),
          );
          continue;
        }
        if (!StopWeatherService.isWithinForecastWindow(day.date)) {
          results.add(
            _DayWeather(
              dayNumber: day.dayNumber,
              date: day.date,
              originName: origin.fromName,
              unavailableReason: 'Forecast not available this far ahead yet.',
            ),
          );
          continue;
        }
        final key =
            '${origin.fromLatitude.toStringAsFixed(3)},${origin.fromLongitude.toStringAsFixed(3)}';
        try {
          final window = cache[key] ??= await _weatherService
              .getForecastsForPosition(
                LatLng(origin.fromLatitude, origin.fromLongitude),
              );
          final forecast = _forecastForDate(window.forecasts, day.date);
          results.add(
            _DayWeather(
              dayNumber: day.dayNumber,
              date: day.date,
              originName: origin.fromName,
              areaLabel: window.areaLabel,
              forecast: forecast,
              unavailableReason: forecast == null
                  ? 'No forecast published for this date yet.'
                  : null,
            ),
          );
        } catch (e) {
          results.add(
            _DayWeather(
              dayNumber: day.dayNumber,
              date: day.date,
              originName: origin.fromName,
              unavailableReason: 'Could not load a forecast for this location.',
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _days = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  WeatherForecast? _forecastForDate(
    List<WeatherForecast> forecasts,
    DateTime date,
  ) {
    for (final forecast in forecasts) {
      if (forecast.date.year == date.year &&
          forecast.date.month == date.month &&
          forecast.date.day == date.day) {
        return forecast;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Transport Weather',
              subtitle: "Each day's forecast at that day's own starting point",
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
      return _MessageState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load the schedule',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_days.isEmpty) {
      return const _MessageState(
        icon: Icons.event_busy_rounded,
        title: 'No saved schedule yet',
        message: 'This trip has no day-by-day itinerary saved.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _days.length,
      itemBuilder: (context, i) => _DayWeatherCard(day: _days[i]),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.colors.muted, size: 32),
            const SizedBox(height: 10),
            Text(
              title,
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
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayWeatherCard extends StatelessWidget {
  const _DayWeatherCard({required this.day});

  final _DayWeather day;

  @override
  Widget build(BuildContext context) {
    final forecast = day.forecast;
    final gradient = forecast == null
        ? null
        : weatherGradientFor(forecast.summaryForecast);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient != null
            ? LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: gradient == null ? context.colors.card : null,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (gradient != null ? gradient.first : context.colors.ink)
                .withValues(alpha: gradient != null ? 0.25 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Day ${day.dayNumber}',
                style: TextStyle(
                  color: forecast != null ? Colors.white : context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatShortDate(day.date),
                style: TextStyle(
                  color: forecast != null
                      ? Colors.white70
                      : context.colors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 14,
                color: forecast != null ? Colors.white70 : context.colors.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  day.areaLabel != null && day.areaLabel != day.originName
                      ? '${day.originName} (${day.areaLabel})'
                      : day.originName,
                  style: TextStyle(
                    color: forecast != null
                        ? Colors.white70
                        : context.colors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (forecast == null)
            Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: context.colors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    day.unavailableReason ?? 'Forecast unavailable.',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Icon(
                  weatherIconFor(forecast.summaryForecast),
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${forecast.minTemp}° – ${forecast.maxTemp}°C',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        translateWeather(forecast.summaryForecast),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PeriodChip(
                    label: 'Morning',
                    text: forecast.morningForecast,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodChip(
                    label: 'Afternoon',
                    text: forecast.afternoonForecast,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodChip(
                    label: 'Night',
                    text: forecast.nightForecast,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bad = isBadWeatherPhrase(text);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: bad ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Icon(weatherIconFor(text), color: Colors.white, size: 16),
          const SizedBox(height: 4),
          Text(
            translateWeather(text),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
