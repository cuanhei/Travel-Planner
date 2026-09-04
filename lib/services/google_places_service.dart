import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/nearby_place.dart';
import '../utils/geo.dart';

const _nearbySearchEndpoint =
    'https://places.googleapis.com/v1/places:searchNearby';
const _textSearchEndpoint = 'https://places.googleapis.com/v1/places:searchText';

const _fieldMask =
    'places.id,places.displayName,places.formattedAddress,'
    'places.location,places.primaryType,places.types,places.photos,'
    'places.businessStatus,places.editorialSummary,places.priceLevel,'
    'places.priceRange,places.regularOpeningHours,places.currentOpeningHours';

const _defaultRadiusMeters = 3000.0;
const _maxResultCount = 20;
const _textSearchResultCount = 10;
const _photoMaxWidthPx = 400;

/// Thrown when [GooglePlacesService] can't complete a request — a
/// missing API key, a network failure, or a non-200 response.
class GooglePlacesRequestException implements Exception {
  GooglePlacesRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Google Places API (New) — Nearby Search, for the Explore tab's
/// "Nearby Places" section. Shares the same Google Cloud API key as
/// [RouteService] (Routes API) — both APIs need to be enabled on that
/// project, but there's only the one key to configure.
///
/// Deliberately separate from [PhotonService], which stays the only
/// search backend for the Trip/Transport location pickers — this
/// service is Nearby-Search-specific, not a general place search.
class GooglePlacesService {
  String get _apiKey => dotenv.maybeGet('GOOGLE_ROUTES_API_KEY') ?? '';

  /// Real places within [radiusMeters] of [center], each with
  /// [NearbyPlace.distanceKm] already computed from [center].
  ///
  /// [includedTypes], when given, restricts the search server-side to
  /// those Google Places types (e.g. a category filter) — this matters:
  /// a plain nearby search only returns Google's top [_maxResultCount]
  /// results by relevance, so filtering *client-side* by type afterward
  /// can show zero results for a real category just because none of
  /// those places happened to rank into that capped top-20 generic
  /// list. Asking Google to search for the type directly avoids that.
  Future<List<NearbyPlace>> nearbySearch({
    required LatLng center,
    double radiusMeters = _defaultRadiusMeters,
    Set<String>? includedTypes,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw GooglePlacesRequestException(
        'Google Places API key is not configured.',
      );
    }
    final response = await http.post(
      Uri.parse(_nearbySearchEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _fieldMask,
      },
      body: jsonEncode({
        'maxResultCount': _maxResultCount,
        if (includedTypes != null && includedTypes.isNotEmpty)
          'includedTypes': includedTypes.toList(),
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': center.latitude,
              'longitude': center.longitude,
            },
            'radius': radiusMeters,
          },
        },
      }),
    );
    if (response.statusCode != 200) {
      throw GooglePlacesRequestException(
        'Nearby places request failed (${response.statusCode})',
      );
    }
    final places = _parsePlaces(response.body, apiKey);
    return [
      for (final p in places)
        p.withDistanceKm(
          haversineMeters(center, LatLng(p.latitude, p.longitude)) / 1000,
        ),
    ];
  }

  /// Free-text destination search (Text Search (New)) — for the Home/
  /// Explore "Search destinations" screen, where the traveler is naming
  /// a place rather than browsing what's around a fixed point, so there
  /// is no [NearbyPlace.distanceKm] to compute here (stays null).
  /// Biased to Malaysia via `regionCode`, matching every other search
  /// backend in this app (Photon's Malaysia bbox).
  Future<List<NearbyPlace>> textSearch(String query) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw GooglePlacesRequestException(
        'Google Places API key is not configured.',
      );
    }
    final response = await http.post(
      Uri.parse(_textSearchEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _fieldMask,
      },
      body: jsonEncode({
        'textQuery': query,
        'regionCode': 'MY',
        'maxResultCount': _textSearchResultCount,
      }),
    );
    if (response.statusCode != 200) {
      throw GooglePlacesRequestException(
        'Destination search failed (${response.statusCode})',
      );
    }
    return _parsePlaces(response.body, apiKey);
  }

  List<NearbyPlace> _parsePlaces(String responseBody, String apiKey) {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final results = (decoded['places'] as List?) ?? const [];
    return [
      for (final r in results)
        NearbyPlace.fromJson(
          r as Map<String, dynamic>,
          apiKey: apiKey,
          photoMaxWidthPx: _photoMaxWidthPx,
        ),
    ];
  }
}
