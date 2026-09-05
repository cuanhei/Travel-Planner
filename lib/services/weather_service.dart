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

/// The full rolling forecast window (today onward) for a resolved area —
/// used by the Weather Forecast screen's multi-day outlook, unlike
/// [ResolvedWeather] which only carries today's entry for the Home
/// dashboard's card.
class ResolvedWeatherWindow {
  const ResolvedWeatherWindow({
    required this.forecasts,
    required this.areaLabel,
  });

  /// Sorted chronologically, starting from today (or the nearest available
  /// day if today's row hasn't been published yet).
  final List<WeatherForecast> forecasts;
  final String areaLabel;
}

/// Forecast data for Malaysia via the government's open API
/// (`api.data.gov.my`, sourced from MET Malaysia) — no API key needed.
/// There's no coordinate lookup built into it, so matching a GPS position
/// goes through Photon reverse-geocoding (city/district/state name) plus a
/// fuzzy match against MET Malaysia's own location lists — town ("Tn") for
/// the city name, falling back to district ("Ds") and then state ("St")
/// when a spot is too small to have its own town-level forecast.
class WeatherService {
  WeatherService({http.Client? client, PhotonService? photonService})
    : _client = client ?? http.Client(),
      _photon = photonService ?? PhotonService();

  final http.Client _client;
  final PhotonService _photon;

  /// Location lists barely ever change, so each is cached for the app's
  /// lifetime once fetched — shared across every [WeatherService]
  /// instance, mirroring `TripService`'s demo-trip-id cache. Keyed by
  /// MET Malaysia's own prefix: "Tn" (town), "Ds" (district), "St" (state)
  /// — three different granularities, not one list to fuzzy-match
  /// everything against.
  static final Map<String, List<({String locationId, String name})>>
  _cachedLocations = {};

  /// Resolves [point] to the nearest MET Malaysia town and returns its
  /// current forecast.
  ///
  /// Throws [LocationNotInMalaysiaException] when Photon confirms the
  /// point is outside Malaysia (a real, non-retryable outcome), or
  /// [WeatherServiceException] with a traveler-facing message for any
  /// other failure — a network error, no reverse-geocode result at all,
  /// or no confident town match.
  Future<ResolvedWeather> getForecastForPosition(LatLng point) async {
    final match = await _resolveArea(point);
    final forecast = await getForecastForLocationId(match.locationId);
    if (forecast == null) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeather(forecast: forecast, areaLabel: match.name);
  }

  /// Resolves [point] the same way as [getForecastForPosition], but
  /// returns the whole rolling forecast window instead of just today —
  /// for the Weather Forecast screen's multi-day outlook.
  Future<ResolvedWeatherWindow> getForecastsForPosition(LatLng point) async {
    final match = await _resolveArea(point);
    final forecasts = await getForecastsForLocationId(match.locationId);
    if (forecasts.isEmpty) {
      throw WeatherServiceException('No forecast available for ${match.name}.');
    }
    return ResolvedWeatherWindow(forecasts: forecasts, areaLabel: match.name);
  }

  /// Reverse-geocodes [point] and matches it to a MET Malaysia location —
  /// town first (finest, so the forecast is as local as possible), then
  /// district, then state — rather than fuzzy-matching all three against
  /// the town list alone, which can never succeed for a district/state
  /// name (they simply aren't in that list).
  Future<({String locationId, String name})> _resolveArea(LatLng point) async {
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

  /// Today's forecast for a specific `location_id` (e.g. `"Tn013"`), or
  /// null if the API has nothing for it.
  ///
  /// The API returns a rolling window of several days per location, but
  /// *not* in a reliable chronological order (today's row can land
  /// first, last, or anywhere in between depending on the location) —
  /// so this fetches the whole window and explicitly picks the entry
  /// whose `date` matches today, rather than assuming a fixed position.
  Future<WeatherForecast?> getForecastForLocationId(String locationId) async {
    final forecasts = await getForecastsForLocationId(locationId);
    return forecasts.isEmpty ? null : _pickTodayOrNearest(forecasts);
  }

  /// The whole rolling forecast window for a specific `location_id` (e.g.
  /// `"Tn013"`), sorted chronologically from oldest to newest — an empty
  /// list if the API has nothing for it.
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

  /// The entry dated today, or — if the API hasn't published today's row
  /// yet (e.g. a brief gap right after midnight) — whichever entry's
  /// date is closest to today. [forecasts] need not be pre-sorted.
  WeatherForecast _pickTodayOrNearest(List<WeatherForecast> forecasts) {
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

  /// Every location MET Malaysia has at granularity [prefix] — `"Tn"`
  /// (town), `"Ds"` (district), or `"St"` (state).
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
      final location = (row as Map<String, dynamic>)['location'] as Map<String, dynamic>?;
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
