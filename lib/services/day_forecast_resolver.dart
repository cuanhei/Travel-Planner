import 'package:latlong2/latlong.dart';

import '../models/trip_day.dart';
import '../models/weather_forecast.dart';
import 'weather_service.dart';

class DayForecastResolver {
  DayForecastResolver({WeatherService? weatherService})
    : _weatherService = weatherService ?? WeatherService();

  final WeatherService _weatherService;

  static const maxForecastDaysAhead = 7;

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
