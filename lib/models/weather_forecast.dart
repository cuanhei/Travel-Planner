/// One day's forecast for a MET Malaysia "Town" area, from the
/// government's open API (`https://api.data.gov.my/weather/forecast`).
class WeatherForecast {
  const WeatherForecast({
    required this.locationId,
    required this.locationName,
    required this.date,
    required this.morningForecast,
    required this.afternoonForecast,
    required this.nightForecast,
    required this.summaryForecast,
    required this.minTemp,
    required this.maxTemp,
  });

  final String locationId;
  final String locationName;
  final DateTime date;

  /// Raw Bahasa Melayu forecast text per period, exactly as MET Malaysia
  /// publishes it (e.g. "Hujan", "Ribut petir", "Tiada Hujan") — kept
  /// untranslated here; see `translateWeather`/`weatherIconFor` in
  /// `lib/utils/weather_display.dart` for the English label/icon shown
  /// in the UI.
  final String morningForecast;
  final String afternoonForecast;
  final String nightForecast;
  final String summaryForecast;

  final int minTemp;
  final int maxTemp;

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>? ?? const {};
    return WeatherForecast(
      locationId: location['location_id'] as String? ?? '',
      locationName: location['location_name'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      morningForecast: json['morning_forecast'] as String? ?? '',
      afternoonForecast: json['afternoon_forecast'] as String? ?? '',
      nightForecast: json['night_forecast'] as String? ?? '',
      summaryForecast: json['summary_forecast'] as String? ?? '',
      minTemp: (json['min_temp'] as num?)?.toInt() ?? 0,
      maxTemp: (json['max_temp'] as num?)?.toInt() ?? 0,
    );
  }
}
