import 'package:flutter/material.dart';

import '../services/locale_service.dart';

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

String translateWeather(String? value) {
  if (value == null || value.trim().isEmpty) {
    return tr('weather_condition_unknown');
  }
  final weather = value.trim();
  final key = weatherMalayToKey[weather];
  return key == null ? weather : tr(key);
}

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

List<Color> weatherGradientFor(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.contains('ribut') || normalized.contains('petir')) {
    return const [Color(0xFF3B3B58), Color(0xFF6B5B8E)];
  }
  if (normalized.contains('jerebu')) {
    return const [Color(0xFF8B8272), Color(0xFFB9AF95)];
  }
  if (normalized.contains('mendung')) {
    return const [Color(0xFF63707D), Color(0xFF93A2B0)];
  }
  if (normalized.contains('hujan') && !normalized.contains('tiada')) {
    return const [Color(0xFF34547A), Color(0xFF4E7DA8)];
  }

  return const [Color(0xFF2E9CCA), Color(0xFF6DD5FA)];
}
