import '../../models/trip_stop_location.dart';
import '../../models/weather_forecast.dart';

/// A forecast period's condition, coarsened from MET Malaysia's raw
/// Malay text into the 3 buckets spec §14 scores against. Matched
/// against the *original* Malay text (not the translated English
/// label), same approach as `lib/utils/weather_display.dart`'s icon
/// selection, so a future wording tweak to that file's translation map
/// can't silently break this.
enum WeatherCondition { good, bad, severe }

/// spec §14: "No Rain -> GOOD, Cloudy -> GOOD, Rain -> BAD, Haze -> BAD,
/// Thunderstorm -> SEVERE".
WeatherCondition weatherConditionFor(String? forecastText) {
  final normalized = (forecastText ?? '').trim().toLowerCase();
  if (normalized.contains('ribut') || normalized.contains('petir')) {
    return WeatherCondition.severe;
  }
  if (normalized.contains('hujan') && !normalized.contains('tiada')) {
    return WeatherCondition.bad;
  }
  if (normalized.contains('jerebu')) {
    return WeatherCondition.bad;
  }
  return WeatherCondition.good;
}

/// How suitable a stop is to schedule given a forecast condition — spec
/// §14's table. Only ever consulted when a trip day actually has
/// weather data (see `TripDay.weatherAvailable`); [PlaceWeatherSuitability.normal]
/// is the neutral, no-opinion result.
enum PlaceWeatherSuitability { preferred, normal, poor, avoid }

/// spec §14:
/// ```
/// OUTDOOR + GOOD    -> Preferred
/// OUTDOOR + BAD     -> Poor
/// OUTDOOR + SEVERE  -> Avoid if possible
/// INDOOR  + GOOD    -> Normal
/// INDOOR  + BAD     -> Preferred
/// INDOOR  + SEVERE  -> Preferred if transportation remains safe
/// ```
/// [EnvironmentType.mixed] (not in the spec's table) is treated as
/// [PlaceWeatherSuitability.normal] at every condition — genuinely
/// weather-agnostic, so no forecast condition should move it up or
/// down. [EnvironmentType.indoor] + [WeatherCondition.severe] is
/// treated as [PlaceWeatherSuitability.preferred] outright (the
/// spec's "if transportation remains safe" qualifier has no signal
/// this app can check, so it's not modeled as a separate case).
PlaceWeatherSuitability placeWeatherSuitability(
  EnvironmentType environment,
  WeatherCondition condition,
) {
  return switch ((environment, condition)) {
    (EnvironmentType.outdoor, WeatherCondition.good) =>
      PlaceWeatherSuitability.preferred,
    (EnvironmentType.outdoor, WeatherCondition.bad) =>
      PlaceWeatherSuitability.poor,
    (EnvironmentType.outdoor, WeatherCondition.severe) =>
      PlaceWeatherSuitability.avoid,
    (EnvironmentType.indoor, WeatherCondition.good) =>
      PlaceWeatherSuitability.normal,
    (EnvironmentType.indoor, WeatherCondition.bad) =>
      PlaceWeatherSuitability.preferred,
    (EnvironmentType.indoor, WeatherCondition.severe) =>
      PlaceWeatherSuitability.preferred,
    (EnvironmentType.mixed, _) => PlaceWeatherSuitability.normal,
  };
}

/// Which of [forecast]'s 3 published periods [time] falls into — spec
/// §32's time-of-day weather planning needs the period-specific
/// forecast text (e.g. a stop scheduled at 2pm should be scored against
/// [WeatherForecast.afternoonForecast], not the whole day's
/// [WeatherForecast.summaryForecast], which is what spec §24's day-
/// assignment scoring uses instead — see `day_assignment.dart`).
///
/// Boundaries: before 12:00 -> morning, 12:00-18:00 -> afternoon, at or
/// after 18:00 -> night. MET Malaysia doesn't publish exact period
/// boundaries alongside the forecast text itself, so these are a
/// reasonable stand-in (late morning through midday counts as
/// "morning", the typical dinner window starts the "night" period).
String forecastForTime(WeatherForecast forecast, DateTime time) {
  final minutesOfDay = time.hour * 60 + time.minute;
  if (minutesOfDay < 12 * 60) return forecast.morningForecast;
  if (minutesOfDay < 18 * 60) return forecast.afternoonForecast;
  return forecast.nightForecast;
}
