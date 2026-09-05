import 'package:latlong2/latlong.dart';

import '../models/weather_condition.dart';
import '../models/weather_forecast.dart';
import 'weather_service.dart';

/// Result of checking one trip stop's planned visit window against MET
/// Malaysia's forecast at its own coordinates. [forecast] is null when
/// nothing could be resolved — either the day is outside the forecast
/// window, or the lookup itself failed (network error, point outside
/// Malaysia, no matching forecast area).
class StopWeatherCheck {
  const StopWeatherCheck({
    this.forecast,
    this.areaLabel,
    this.periodsSpanned = const [],
    this.badPeriods = const [],
  });

  final WeatherForecast? forecast;
  final String? areaLabel;

  /// Every [DayPeriod] the stop's arrival→end window touches — a long
  /// visit can span more than one (e.g. 11:00–13:30 covers morning and
  /// afternoon).
  final List<DayPeriod> periodsSpanned;

  /// The subset of [periodsSpanned] MET Malaysia forecasts as rain or a
  /// thunderstorm.
  final List<DayPeriod> badPeriods;

  bool get isResolved => forecast != null;
  bool get isBad => badPeriods.isNotEmpty;
}

/// Checks whether an outdoor/mixed stop's planned visit window falls
/// during forecast rain — built on the same [WeatherService] (MET
/// Malaysia via `api.data.gov.my`, reverse-geocoded per point) and
/// [DayPeriod]/[isBadWeatherPhrase] logic the rest of the app already
/// uses, just resolved at a *stop's own coordinates* rather than a
/// whole-day anchor point, and against whichever forecast periods its
/// visit actually spans rather than the whole day at once.
class StopWeatherService {
  StopWeatherService({WeatherService? weatherService})
    : _weatherService = weatherService ?? WeatherService();

  final WeatherService _weatherService;

  /// MET Malaysia's forecast only reaches this many days out — a stop
  /// further ahead than this has no forecast to check at all.
  static const maxForecastDaysAhead = 7;

  /// True if [date] falls within MET Malaysia's forecast window (today
  /// through [maxForecastDaysAhead] days ahead) — checked before ever
  /// calling [check], since there's nothing to look up otherwise.
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

  /// Resolves the forecast at [position] for [date] and flags whether any
  /// period between [arrivalMinutes] and [endMinutes] (minutes since that
  /// day's midnight — may exceed 1440 for a plan that runs past it) is
  /// forecast as rain/thunderstorm. Returns an unresolved
  /// [StopWeatherCheck] (both lists empty, `forecast: null`) if [date] is
  /// outside the forecast window or nothing could be resolved — never
  /// throws.
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

  /// Every [DayPeriod] touched between [startMinutes] and [endMinutes]
  /// (sampled at a coarser-than-a-period granularity — sufficient since
  /// periods span hours, not minutes). Falls back to whichever single
  /// period [startMinutes] itself falls in in the (impossible in
  /// practice) case of a zero-or-negative-length window.
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
