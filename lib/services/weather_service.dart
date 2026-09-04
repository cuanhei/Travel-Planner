import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/weather_forecast.dart';
import 'photon_service.dart';

const _baseUrl = 'https://api.data.gov.my';

/// Thrown when [WeatherService] can't resolve a forecast — a network
/// failure, or a GPS position that couldn't be matched to any known
/// MET Malaysia town.
class WeatherServiceException implements Exception {
  WeatherServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown specifically when the resolved position is confirmed to be
/// outside Malaysia — a distinct, *expected* outcome (this API only
/// covers Malaysia), not a retry-able error. Kept separate from
/// [WeatherServiceException] so the UI can hide the weather card
/// entirely and show a plain explanatory message instead of an
/// error-with-retry state.
class LocationNotInMalaysiaException implements Exception {
  const LocationNotInMalaysiaException();

  @override
  String toString() =>
      'Weather forecast is only available for your current location if you are in Malaysia.';
}

/// A resolved forecast plus the name it was actually matched under —
/// shown to the traveler so it's clear which area the numbers are for
/// (GPS reverse-geocoding and MET Malaysia's own naming don't always
/// agree, e.g. "George Town" vs "Georgetown").
class ResolvedWeather {
  const ResolvedWeather({required this.forecast, required this.areaLabel});

  final WeatherForecast forecast;
  final String areaLabel;
}

/// The full multi-day forecast window for a resolved area, plus the name
/// it was matched under — see [ResolvedWeather] and
/// [WeatherService.getForecastWindowForPosition]. Sorted ascending by
/// date; how many days out this actually reaches depends entirely on
/// what `api.data.gov.my` currently publishes for that town (typically
/// under two weeks, but not a guaranteed fixed number) — a caller
/// planning a trip day beyond the last entry here has no forecast for
/// that date, full stop, rather than an assumed/extrapolated one.
class ResolvedWeatherWindow {
  const ResolvedWeatherWindow({
    required this.forecasts,
    required this.areaLabel,
  });

  final List<WeatherForecast> forecasts;
  final String areaLabel;

  /// The forecast for [date] (matched by calendar day), or null if that
  /// date falls outside this window — the per-trip-day
  /// "weatherAvailable" check the scheduling engine needs.
  WeatherForecast? forecastForDate(DateTime date) {
    for (final forecast in forecasts) {
      if (forecast.date.year == date.year &&
          forecast.date.month == date.month &&
          forecast.date.day == date.day) {
        return forecast;
      }
    }
    return null;
  }
}

/// Forecast data for Malaysia via the government's open API
/// (`api.data.gov.my`, sourced from MET Malaysia) — no API key needed.
/// Town-level ("Tn") is the finest granularity the API offers; there's
/// no coordinate lookup built into it, so matching a GPS position to a
/// town goes through Photon reverse-geocoding (city/district/state name)
/// plus a fuzzy match against the cached town list.
class WeatherService {
  WeatherService({http.Client? client, PhotonService? photonService})
    : _client = client ?? http.Client(),
      _photon = photonService ?? PhotonService();

  final http.Client _client;
  final PhotonService _photon;

  /// Town list barely ever changes, so it's cached for the app's
  /// lifetime once fetched — shared across every [WeatherService]
  /// instance, mirroring `TripService`'s demo-trip-id cache.
  static List<({String locationId, String name})>? _cachedTowns;

  /// Resolves [point] to the nearest MET Malaysia town and returns its
  /// current forecast.
  ///
  /// Throws [LocationNotInMalaysiaException] when Photon confirms the
  /// point is outside Malaysia (a real, non-retryable outcome), or
  /// [WeatherServiceException] with a traveler-facing message for any
  /// other failure — a network error, no reverse-geocode result at all,
  /// or no confident town match.
  Future<ResolvedWeather> getForecastForPosition(LatLng point) async {
    final match = await _resolveTown(point);
    final forecast = await getForecastForLocationId(match.locationId);
    if (forecast == null) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeather(forecast: forecast, areaLabel: match.name);
  }

  /// Same GPS→town resolution as [getForecastForPosition], but returns
  /// the *entire* published forecast window instead of collapsing it to
  /// a single day — for the trip-scheduling engine, which needs to check
  /// weather availability independently for every date in a trip, not
  /// just today. Throws the same [LocationNotInMalaysiaException]/
  /// [WeatherServiceException] cases.
  Future<ResolvedWeatherWindow> getForecastWindowForPosition(
    LatLng point,
  ) async {
    final match = await _resolveTown(point);
    final forecasts = await getForecastWindowForLocationId(match.locationId);
    if (forecasts.isEmpty) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeatherWindow(forecasts: forecasts, areaLabel: match.name);
  }

  /// Resolves [point] to the nearest MET Malaysia town — the shared
  /// GPS→town step behind both [getForecastForPosition] and
  /// [getForecastWindowForPosition].
  Future<({String locationId, String name})> _resolveTown(LatLng point) async {
    final ({String? city, String? district, String? state, String? countryCode})?
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

    final towns = await _towns();
    ({String locationId, String name})? match;
    for (final candidate in [area.city, area.district, area.state]) {
      if (candidate == null) continue;
      match = _bestMatch(candidate, towns);
      if (match != null) break;
    }
    if (match == null) {
      throw WeatherServiceException(
        'Could not match your location to a forecast area.',
      );
    }
    return match;
  }

  /// Today's forecast for a specific `location_id` (e.g. `"Tn013"`), or
  /// null if the API has nothing for it.
  ///
  /// The API returns a rolling window of several days per location, but
  /// *not* in a reliable chronological order (today's row can land
  /// first, last, or anywhere in between depending on the location) —
  /// so this fetches the whole window and explicitly picks the entry
  /// whose `date` matches today, rather than assuming a fixed position.
  Future<WeatherForecast?> getForecastForLocationId(String locationId) async {
    final forecasts = await _fetchWindow(locationId);
    return _pickTodayOrNearest(forecasts);
  }

  /// The *entire* published forecast window for a `location_id`, sorted
  /// ascending by date, instead of [getForecastForLocationId]'s
  /// single-day pick — for the trip-scheduling engine, which needs to
  /// check every trip date independently against whatever window MET
  /// Malaysia currently publishes (see [ResolvedWeatherWindow]).
  Future<List<WeatherForecast>> getForecastWindowForLocationId(
    String locationId,
  ) async {
    final forecasts = await _fetchWindow(locationId);
    return [...forecasts]..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<WeatherForecast>> _fetchWindow(String locationId) async {
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
    return [
      for (final row in decoded)
        WeatherForecast.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// The entry dated today, or — if the API hasn't published today's row
  /// yet (e.g. a brief gap right after midnight) — whichever entry's
  /// date is closest to today.
  WeatherForecast? _pickTodayOrNearest(List<WeatherForecast> forecasts) {
    if (forecasts.isEmpty) return null;
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    for (final forecast in forecasts) {
      if (isToday(forecast.date)) return forecast;
    }
    final sorted = [...forecasts]..sort(
      (a, b) => a.date
          .difference(today)
          .abs()
          .compareTo(b.date.difference(today).abs()),
    );
    return sorted.first;
  }

  Future<List<({String locationId, String name})>> _towns() async {
    final cached = _cachedTowns;
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/weather/forecast').replace(
      queryParameters: {'contains': 'Tn@location__location_id', 'limit': '1000'},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw WeatherServiceException(
        'Could not load the list of forecast areas (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as List;
    final seen = <String>{};
    final towns = <({String locationId, String name})>[];
    for (final row in decoded) {
      final location = (row as Map<String, dynamic>)['location'] as Map<String, dynamic>?;
      final id = location?['location_id'] as String?;
      final name = location?['location_name'] as String?;
      if (id == null || name == null || !seen.add(id)) continue;
      towns.add((locationId: id, name: name));
    }
    _cachedTowns = towns;
    return towns;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Exact match (normalized) first, then substring containment either
  /// direction — good enough to bridge "George Town" (OSM) vs
  /// "Georgetown" (MET Malaysia) without over-matching unrelated names.
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
