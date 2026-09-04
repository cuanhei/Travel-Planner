import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Official MET Malaysia forecast phrases (Bahasa Melayu), mapped to the
/// `weather_condition_*` translation key shown in the UI — see
/// https://developer.data.gov.my/realtime-api/weather for the source
/// vocabulary. Centralized here so every place that renders forecast
/// text (`morning_forecast`/`afternoon_forecast`/`night_forecast`/
/// `summary_forecast`, currently just the Home dashboard's Weather Card)
/// shows the same wording — in the app's currently-selected language,
/// not always English — instead of translating inline.
const Map<String, String> weatherMalayToKey = {
  'Tiada Hujan': 'weather_condition_no_rain',
  'Hujan': 'weather_condition_rain',
  'Jerebu': 'weather_condition_haze',
  'Mendung': 'weather_condition_cloudy',
  'Ribut petir': 'weather_condition_thunderstorms',
  'Hujan di beberapa tempat': 'weather_condition_rain_some_areas',
  'Hujan di kebanyakan tempat': 'weather_condition_rain_most_areas',
  'Hujan di beberapa tempat di kawasan pantai':
      'weather_condition_rain_some_coastal',
  'Ribut petir di beberapa tempat':
      'weather_condition_thunderstorms_some_areas',
  'Ribut petir di kebanyakan tempat':
      'weather_condition_thunderstorms_most_areas',
  'Ribut petir di beberapa tempat di kawasan pantai':
      'weather_condition_thunderstorms_some_coastal',
};

/// Translates one MET Malaysia forecast phrase into the app's current
/// language via [weatherMalayToKey]. A phrase MET Malaysia hasn't
/// published yet (not in the map) is shown as-is (still Malay) rather
/// than crashing or disappearing; null/blank input reads as "Unknown"
/// (translated) instead of an empty label.
String translateWeather(String? value) {
  if (value == null || value.trim().isEmpty) {
    return tr('weather_condition_unknown');
  }
  final weather = value.trim();
  final key = weatherMalayToKey[weather];
  return key == null ? weather : tr(key);
}

/// Icon for one MET Malaysia forecast phrase — matched against the
/// *original* Malay text (normalized to lowercase), not the translated
/// display label, so a wording tweak in any language can't silently
/// break icon selection. Covers every phrase in the map,
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
