import 'weather_forecast.dart';

/// Whether a MET Malaysia forecast phrase (Bahasa Melayu, as published —
/// see [WeatherForecast]) describes rain or a thunderstorm, in any of
/// its "some areas"/"most areas"/"coastal" variants — used to flag a
/// period as bad weather for trip-schedule adjustment. Mirrors
/// `weatherIconFor` in `lib/utils/weather_display.dart`'s rain/storm
/// matching, kept as a separate, UI-free function since that file pulls
/// in Material for its icon/translation helpers and this needs to be
/// callable from plain scheduling logic.
bool isBadWeatherPhrase(String? phrase) {
  final normalized = (phrase ?? '').trim().toLowerCase();
  if (normalized.contains('ribut') || normalized.contains('petir')) {
    return true;
  }
  if (normalized.contains('hujan') && !normalized.contains('tiada')) {
    return true;
  }
  return false;
}

/// Coarse time-of-day bucket matching [WeatherForecast]'s three forecast
/// periods.
enum DayPeriod { morning, afternoon, night }

/// Which [DayPeriod] a clock time falls into — noon and 6pm are the
/// morning/afternoon and afternoon/night boundaries respectively,
/// matching how MET Malaysia's own three-period forecast is generally
/// understood (there's no official cutoff published alongside the
/// phrases themselves).
DayPeriod periodForTime(DateTime time) {
  if (time.hour < 12) return DayPeriod.morning;
  if (time.hour < 18) return DayPeriod.afternoon;
  return DayPeriod.night;
}

extension WeatherForecastPeriod on WeatherForecast {
  /// The raw forecast phrase for [period] — [morningForecast],
  /// [afternoonForecast], or [nightForecast].
  String phraseFor(DayPeriod period) {
    switch (period) {
      case DayPeriod.morning:
        return morningForecast;
      case DayPeriod.afternoon:
        return afternoonForecast;
      case DayPeriod.night:
        return nightForecast;
    }
  }

  /// Whether [period] is forecast as rain/thunderstorm — see
  /// [isBadWeatherPhrase].
  bool isBadFor(DayPeriod period) => isBadWeatherPhrase(phraseFor(period));
}
