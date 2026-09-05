import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/nearby_place.dart';
import '../utils/geo.dart';

const _nearbySearchEndpoint =
    'https://places.googleapis.com/v1/places:searchNearby';
const _textSearchEndpoint =
    'https://places.googleapis.com/v1/places:searchText';

const _fieldMask =
    'places.id,places.displayName,places.formattedAddress,'
    'places.location,places.primaryType,places.types,places.photos,'
    'places.businessStatus,places.editorialSummary,places.priceLevel,'
    'places.priceRange,places.regularOpeningHours,places.currentOpeningHours';

const _placeDetailsEndpoint = 'https://places.googleapis.com/v1/places';

const _placeDetailsFieldMask =
    'id,displayName,formattedAddress,location,primaryType,types,'
    'businessStatus,regularOpeningHours,currentOpeningHours';

const _defaultRadiusMeters = 3000.0;
const _maxResultCount = 20;
const _textSearchResultCount = 10;
const _photoMaxWidthPx = 400;

class GooglePlacesRequestException implements Exception {
  GooglePlacesRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GooglePlacesService {
  String get _apiKey => dotenv.maybeGet('GOOGLE_ROUTES_API_KEY') ?? '';

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

  Future<List<NearbyPlace>> textSearch(
    String query, {
    int maxResultCount = _textSearchResultCount,
  }) async {
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
        'maxResultCount': maxResultCount,
      }),
    );
    if (response.statusCode != 200) {
      throw GooglePlacesRequestException(
        'Destination search failed (${response.statusCode})',
      );
    }
    return _parsePlaces(response.body, apiKey);
  }

  Future<NearbyPlace> getPlaceDetails(String placeId) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw GooglePlacesRequestException(
        'Google Places API key is not configured.',
      );
    }
    final response = await http.get(
      Uri.parse('$_placeDetailsEndpoint/$placeId'),
      headers: {
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _placeDetailsFieldMask,
      },
    );
    if (response.statusCode != 200) {
      throw GooglePlacesRequestException(
        'Place details request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return NearbyPlace.fromJson(
      decoded,
      apiKey: apiKey,
      photoMaxWidthPx: _photoMaxWidthPx,
    );
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
