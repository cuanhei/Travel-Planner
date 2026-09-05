import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';

const _searchEndpoint = 'https://photon.komoot.io/api/';
const _reverseEndpoint = 'https://photon.komoot.io/reverse';

/// Photon's server rejects requests with Dart's default `Dart/x.x (dart:io)`
/// User-Agent with a 403 — every request needs a browser-like one instead.
const _headers = {
  'User-Agent':
      'Mozilla/5.0 (compatible; travelplanner-app) TravelPlanner/1.0',
};

/// west,south,east,north — a loose box around all of Malaysia (Peninsular
/// + Sabah/Sarawak). Narrows Photon's search to the region, but since the
/// box's corners spill into Indonesia/Singapore/Brunei/Thailand, it's not
/// a country filter by itself — see the `countrycode` check in [_toStop].
const _malaysiaBbox = '99.5,0.5,119.5,7.5';

/// Free place search/autocomplete and reverse geocoding via Photon
/// (komoot's OpenStreetMap-based geocoder) — no API key required. Every
/// result is restricted to Malaysia.
class PhotonService {
  /// Autocomplete search for the Stop Selection search bar. [near] biases
  /// results toward that point (e.g. the map's current center) without
  /// restricting to it; results outside Malaysia are dropped regardless.
  Future<List<TripStopLocation>> search(String query, {LatLng? near}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'q': trimmed,
        'limit': '8',
        'lang': 'en',
        'bbox': _malaysiaBbox,
        if (near != null) 'lat': near.latitude.toString(),
        if (near != null) 'lon': near.longitude.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Place search failed (${response.statusCode})');
    }
    return _parseFeatures(response.body);
  }

  /// Reverse-geocodes [point] to its containing administrative area
  /// names, unlike [reverse] which returns the nearest named PLACE (a
  /// shop, landmark, etc.) collapsed into one address string. Used by
  /// the Weather module to match a GPS position to a MET Malaysia "Town"
  /// forecast area — returns whichever fields Photon's OSM data has for
  /// that point (a sparsely-mapped rural point may have `city` empty),
  /// plus [countryCode] so a caller can distinguish "outside Malaysia"
  /// (a real, expected result) from "no data at all". Returns null only
  /// when there's no reverse-geocode result whatsoever.
  Future<({String? city, String? district, String? state, String? countryCode})?>
  reverseAdministrative(LatLng point) async {
    final uri = Uri.parse(_reverseEndpoint).replace(
      queryParameters: {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Reverse lookup failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (decoded['features'] as List?) ?? const [];
    if (features.isEmpty) return null;
    final props =
        (features.first as Map<String, dynamic>)['properties']
            as Map<String, dynamic>? ??
        const {};
    return (
      city: props['city'] as String?,
      district: props['district'] as String?,
      state: props['state'] as String?,
      countryCode: props['countrycode'] as String?,
    );
  }

  List<TripStopLocation> _parseFeatures(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final features = (decoded['features'] as List?) ?? const [];
    final stops = <TripStopLocation>[];
    for (final feature in features) {
      final stop = _toStop(feature as Map<String, dynamic>);
      if (stop != null) stops.add(stop);
    }
    return stops;
  }

  TripStopLocation? _toStop(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;

    final props = (feature['properties'] as Map<String, dynamic>?) ?? const {};
    final name = (props['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    if (props['countrycode'] != 'MY') return null;

    final street = props['housenumber'] != null && props['street'] != null
        ? '${props['housenumber']} ${props['street']}'
        : props['street'] as String?;
    final addressParts = [
      street,
      props['city'] as String?,
      props['state'] as String?,
      props['country'] as String?,
    ].whereType<String>().toList();

    final osmType = props['osm_type'] as String?;
    final osmIdValue = props['osm_id'];
    final osmId = osmType != null && osmIdValue != null
        ? '$osmType$osmIdValue'
        : osmIdValue?.toString();

    return TripStopLocation(
      name: name,
      address: addressParts.isEmpty ? 'Unknown address' : addressParts.join(', '),
      longitude: (coords[0] as num).toDouble(),
      latitude: (coords[1] as num).toDouble(),
      osmId: osmId,
      category: _categoryOf(
        props['osm_key'] as String?,
        props['osm_value'] as String?,
      ),
    );
  }

  /// Maps Photon/OSM's `osm_key`/`osm_value` tag pair to one of
  /// [TripStopLocation]'s coarse category labels.
  String _categoryOf(String? key, String? value) {
    switch (key) {
      case 'shop':
        return 'Shopping';
      case 'amenity':
        switch (value) {
          case 'restaurant':
          case 'cafe':
          case 'fast_food':
          case 'bar':
          case 'pub':
          case 'food_court':
          case 'ice_cream':
            return 'Food';
          case 'place_of_worship':
            return 'Culture';
          case 'hospital':
          case 'clinic':
          case 'pharmacy':
            return 'Health';
          case 'bank':
          case 'atm':
            return 'Finance';
          default:
            return 'Other';
        }
      case 'tourism':
        switch (value) {
          case 'hotel':
          case 'guest_house':
          case 'hostel':
          case 'motel':
          case 'apartment':
            return 'Hotel';
          default:
            return 'Attraction';
        }
      case 'leisure':
        return 'Nature';
      case 'natural':
        return value == 'beach' ? 'Beach' : 'Nature';
      case 'railway':
      case 'highway':
        return value == 'bus_stop' ||
                value == 'station' ||
                value == 'stop' ||
                value == 'platform'
            ? 'Transport'
            : 'Other';
      case 'aeroway':
        return 'Transport';
      case 'historic':
      case 'museum':
        return 'Culture';
      default:
        return 'Other';
    }
  }
}
