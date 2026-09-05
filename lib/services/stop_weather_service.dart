import 'package:latlong2/latlong.dart';

import '../models/weather_condition.dart';
import '../models/weather_forecast.dart';
import 'weather_service.dart';

class StopWeatherCheck {
  const StopWeatherCheck({
    this.forecast,
    this.areaLabel,
    this.periodsSpanned = const [],
    this.badPeriods = const [],
  });

  final WeatherForecast? forecast;
  final String? areaLabel;

  final List<DayPeriod> periodsSpanned;

  final List<DayPeriod> badPeriods;

  bool get isResolved => forecast != null;
  bool get isBad => badPeriods.isNotEmpty;
}

class StopWeatherService {
  StopWeatherService({WeatherService? weatherService})
    : _weatherService = weatherService ?? WeatherService();

  final WeatherService _weatherService;

  static const maxForecastDaysAhead = 7;

  static bool isWithinForecastWindow(DateTime date) {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final daysAhead = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(todayDateOnly).inDays;
    return daysAhead >= 0 && daysAhead <= maxForecastDaysAhead;
  }

  Future<StopWeatherCheck> check({
    required LatLng position,
    required DateTime date,
    required int arrivalMinutes,
    required int endMinutes,
  }) async {
    if (!isWithinForecastWindow(date)) return const StopWeatherCheck();

    WeatherForecast? forecast;
    String? areaLabel;
    try {
      final window = await _weatherService.getForecastsForPosition(position);
      forecast = _forecastForDate(window.forecasts, date);
      areaLabel = window.areaLabel;
    } catch (_) {
      forecast = null;
    }
    if (forecast == null) return const StopWeatherCheck();

    final periods = _periodsSpanned(arrivalMinutes, endMinutes);
    final badPeriods = [
      for (final period in periods)
        if (forecast.isBadFor(period)) period,
    ];
    return StopWeatherCheck(
      forecast: forecast,
      areaLabel: areaLabel,
      periodsSpanned: periods,
      badPeriods: badPeriods,
    );
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

  List<DayPeriod> _periodsSpanned(int startMinutes, int endMinutes) {
    final periods = <DayPeriod>{};
    var minute = startMinutes;
    while (minute < endMinutes) {
      periods.add(_periodForMinute(minute));
      minute += 30;
    }
    if (periods.isEmpty) periods.add(_periodForMinute(startMinutes));
    return periods.toList();
  }

  DayPeriod _periodForMinute(int minutesSinceMidnight) {
    final wrapped = minutesSinceMidnight % (24 * 60);
    final hour = (wrapped < 0 ? wrapped + 24 * 60 : wrapped) ~/ 60;
    if (hour < 12) return DayPeriod.morning;
    if (hour < 18) return DayPeriod.afternoon;
    return DayPeriod.night;
  }
}
