import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/nearby_place.dart';
import '../utils/geo.dart';

const _nearbySearchEndpoint =
    'https://places.googleapis.com/v1/places:searchNearby';

const _fieldMask =
    'places.id,places.displayName,places.formattedAddress,'
    'places.location,places.primaryType,places.photos,places.businessStatus';

const _defaultRadiusMeters = 3000.0;
const _maxResultCount = 20;
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
  Future<List<NearbyPlace>> nearbySearch({
    required LatLng center,
    double radiusMeters = _defaultRadiusMeters,
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
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (decoded['places'] as List?) ?? const [];
    final places = [
      for (final r in results)
        NearbyPlace.fromJson(
          r as Map<String, dynamic>,
          apiKey: apiKey,
          photoMaxWidthPx: _photoMaxWidthPx,
        ),
    ];
    return [
      for (final p in places)
        p.withDistanceKm(
          haversineMeters(center, LatLng(p.latitude, p.longitude)) / 1000,
        ),
    ];
  }
}
