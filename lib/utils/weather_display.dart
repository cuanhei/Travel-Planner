import 'package:flutter/material.dart';

/// Official MET Malaysia forecast phrases (Bahasa Melayu), mapped to the
/// English text shown in the UI — see
/// https://developer.data.gov.my/realtime-api/weather for the source
/// vocabulary. Centralized here so every place that renders forecast
/// text (`morning_forecast`/`afternoon_forecast`/`night_forecast`/
/// `summary_forecast`, currently just the Home dashboard's Weather Card)
/// shows the same wording, instead of translating inline.
const Map<String, String> weatherMalayToEnglish = {
  'Tiada Hujan': 'No Rain',
  'Hujan': 'Rain',
  'Jerebu': 'Haze',
  'Mendung': 'Cloudy',
  'Ribut petir': 'Thunderstorms',
  'Hujan di beberapa tempat': 'Rain in Some Areas',
  'Hujan di kebanyakan tempat': 'Rain in Most Areas',
  'Hujan di beberapa tempat di kawasan pantai': 'Rain in Some Coastal Areas',
  'Ribut petir di beberapa tempat': 'Thunderstorms in Some Areas',
  'Ribut petir di kebanyakan tempat': 'Thunderstorms in Most Areas',
  'Ribut petir di beberapa tempat di kawasan pantai':
      'Thunderstorms in Some Coastal Areas',
};

/// Translates one MET Malaysia forecast phrase to English via
/// [weatherMalayToEnglish]. A phrase MET Malaysia hasn't published yet
/// (not in the map) is shown as-is rather than crashing or disappearing;
/// null/blank input reads as "Unknown" instead of an empty label.
String translateWeather(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Unknown';
  }
  final weather = value.trim();
  return weatherMalayToEnglish[weather] ?? weather;
}

/// Icon for one MET Malaysia forecast phrase — matched against the
/// *original* Malay text (normalized to lowercase), not the translated
/// English label, so a future wording tweak to [weatherMalayToEnglish]
/// can't silently break icon selection. Covers every phrase in the map,
/// including the "in some/most/coastal areas" variants (rain-family
/// phrases all get the rain icon, storm-family phrases all get the
/// thunderstorm icon).
IconData weatherIconFor(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.contains('ribut') || normalized.contains('petir')) {
    return Icons.thunderstorm_rounded;
  }
  if (normalized.contains('jerebu')) {
    return Icons.blur_on_rounded;
  }
  if (normalized.contains('mendung')) {
    return Icons.cloud_rounded;
  }
  if (normalized.contains('hujan') && !normalized.contains('tiada')) {
    return Icons.water_drop_rounded;
  }
  return Icons.wb_sunny_rounded;
}
