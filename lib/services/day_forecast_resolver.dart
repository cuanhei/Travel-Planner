import 'package:latlong2/latlong.dart';

import '../models/trip_day.dart';
import '../models/weather_forecast.dart';
import 'weather_service.dart';

/// Resolves the [WeatherForecast] for a [TripDay], when its date falls
/// within MET Malaysia's forecast window — shared by
/// `WeatherAdjustmentService` and `GapFillingService`, both of which
/// need the same "is this day even forecastable, and if so what's the
/// forecast" lookup, keyed off the day's end anchor as a stand-in for
/// "the area this day is in".
class DayForecastResolver {
  DayForecastResolver({WeatherService? weatherService})
    : _weatherService = weatherService ?? WeatherService();

  final WeatherService _weatherService;

  /// MET Malaysia's forecast only reaches a handful of days out — a day
  /// further ahead than this has no forecast to adjust against at all,
  /// so its base timeline is left untouched by whichever stage asked.
  static const maxForecastDaysAhead = 7;

  /// Per-day-number cache within one resolver instance — every stage
  /// that needs a day's forecast more than once (weather adjustment
  /// resolves it once per day; gap filling asks again for the same
  /// days) shouldn't refetch the whole rolling window each time.
  final Map<int, WeatherForecast?> _cache = {};

  Future<WeatherForecast?> resolve(TripDay day) async {
    final cached = _cache[day.dayNumber];
    if (cached != null) return cached;
    if (_cache.containsKey(day.dayNumber)) return null;

    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final daysAhead = day.date.difference(todayDateOnly).inDays;
    if (daysAhead < 0 || daysAhead > maxForecastDaysAhead) {
      _cache[day.dayNumber] = null;
      return null;
    }

    WeatherForecast? forecast;
    try {
      final window = await _weatherService.getForecastsForPosition(
        LatLng(day.endAnchor.latitude, day.endAnchor.longitude),
      );
      forecast = _forecastForDate(window.forecasts, day.date);
    } catch (_) {
      forecast = null;
    }
    _cache[day.dayNumber] = forecast;
    return forecast;
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
}
