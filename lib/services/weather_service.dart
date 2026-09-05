import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/weather_forecast.dart';
import 'photon_service.dart';

const _baseUrl = 'https://api.data.gov.my';

class WeatherServiceException implements Exception {
  WeatherServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationNotInMalaysiaException implements Exception {
  const LocationNotInMalaysiaException();

  @override
  String toString() =>
      'Weather forecast is only available for your current location if you are in Malaysia.';
}

class ResolvedWeather {
  const ResolvedWeather({required this.forecast, required this.areaLabel});

  final WeatherForecast forecast;
  final String areaLabel;
}

class ResolvedWeatherWindow {
  const ResolvedWeatherWindow({
    required this.forecasts,
    required this.areaLabel,
  });

  final List<WeatherForecast> forecasts;
  final String areaLabel;
}

class WeatherService {
  WeatherService({http.Client? client, PhotonService? photonService})
    : _client = client ?? http.Client(),
      _photon = photonService ?? PhotonService();

  final http.Client _client;
  final PhotonService _photon;

  static final Map<String, List<({String locationId, String name})>>
  _cachedLocations = {};

  Future<ResolvedWeather> getForecastForPosition(LatLng point) async {
    final match = await _resolveArea(point);
    final forecast = await getForecastForLocationId(match.locationId);
    if (forecast == null) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeather(forecast: forecast, areaLabel: match.name);
  }

  Future<ResolvedWeatherWindow> getForecastsForPosition(LatLng point) async {
    final match = await _resolveArea(point);
    final forecasts = await getForecastsForLocationId(match.locationId);
    if (forecasts.isEmpty) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeatherWindow(forecasts: forecasts, areaLabel: match.name);
  }

  Future<({String locationId, String name})> _resolveArea(LatLng point) async {
    final ({
      String? city,
      String? district,
      String? state,
      String? countryCode,
    })?
    area;
    try {
      area = await _photon.reverseAdministrative(point);
    } catch (_) {
      throw WeatherServiceException('Could not determine your location.');
    }
    if (area == null) {
      throw WeatherServiceException(
        'Could not determine your location. Try again in a moment.',
      );
    }
    if (area.countryCode != null && area.countryCode != 'MY') {
      throw const LocationNotInMalaysiaException();
    }

    ({String locationId, String name})? match;
    if (area.city != null) {
      match = _bestMatch(area.city!, await _locations('Tn'));
    }
    if (match == null && area.district != null) {
      match = _bestMatch(area.district!, await _locations('Ds'));
    }
    if (match == null && area.state != null) {
      match = _bestMatch(area.state!, await _locations('St'));
    }
    if (match == null) {
      throw WeatherServiceException(
        'Could not match your location to a forecast area.',
      );
    }
    return match;
  }

  Future<WeatherForecast?> getForecastForLocationId(String locationId) async {
    final forecasts = await getForecastsForLocationId(locationId);
    return forecasts.isEmpty ? null : _pickTodayOrNearest(forecasts);
  }

  Future<List<WeatherForecast>> getForecastsForLocationId(
    String locationId,
  ) async {
    final uri = Uri.parse('$_baseUrl/weather/forecast').replace(
      queryParameters: {
        'contains': '$locationId@location__location_id',
        'limit': '10',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw WeatherServiceException(
        'Weather request failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as List;
    final forecasts = [
      for (final row in decoded)
        WeatherForecast.fromJson(row as Map<String, dynamic>),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return forecasts;
  }

  WeatherForecast _pickTodayOrNearest(List<WeatherForecast> forecasts) {
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    for (final forecast in forecasts) {
      if (isToday(forecast.date)) return forecast;
    }
    final sorted = [...forecasts]
      ..sort(
        (a, b) => a.date
            .difference(today)
            .abs()
            .compareTo(b.date.difference(today).abs()),
      );
    return sorted.first;
  }

  Future<List<({String locationId, String name})>> _locations(
    String prefix,
  ) async {
    final cached = _cachedLocations[prefix];
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/weather/forecast').replace(
      queryParameters: {
        'contains': '$prefix@location__location_id',
        'limit': '1000',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw WeatherServiceException(
        'Could not load the list of forecast areas (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as List;
    final seen = <String>{};
    final locations = <({String locationId, String name})>[];
    for (final row in decoded) {
      final location =
          (row as Map<String, dynamic>)['location'] as Map<String, dynamic>?;
      final id = location?['location_id'] as String?;
      final name = location?['location_name'] as String?;
      if (id == null || name == null || !seen.add(id)) continue;
      locations.add((locationId: id, name: name));
    }
    _cachedLocations[prefix] = locations;
    return locations;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  ({String locationId, String name})? _bestMatch(
    String candidate,
    List<({String locationId, String name})> towns,
  ) {
    final normalizedCandidate = _normalize(candidate);
    if (normalizedCandidate.isEmpty) return null;

    for (final town in towns) {
      if (_normalize(town.name) == normalizedCandidate) return town;
    }
    for (final town in towns) {
      final normalizedTown = _normalize(town.name);
      if (normalizedTown.contains(normalizedCandidate) ||
          normalizedCandidate.contains(normalizedTown)) {
        return town;
      }
    }
    return null;
  }
}
