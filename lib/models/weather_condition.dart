import 'weather_forecast.dart';

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

enum DayPeriod { morning, afternoon, night }

DayPeriod periodForTime(DateTime time) {
  if (time.hour < 12) return DayPeriod.morning;
  if (time.hour < 18) return DayPeriod.afternoon;
  return DayPeriod.night;
}

extension WeatherForecastPeriod on WeatherForecast {
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

  bool isBadFor(DayPeriod period) => isBadWeatherPhrase(phraseFor(period));
}
