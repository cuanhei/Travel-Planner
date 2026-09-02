import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/drive_route.dart';
import '../models/transit_route.dart';
import '../models/walking_route.dart';

const _computeRoutesEndpoint =
    'https://routes.googleapis.com/directions/v2:computeRoutes';

const _transitFieldMask =
    'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,'
    'routes.legs.steps.travelMode,routes.legs.steps.staticDuration,'
    'routes.legs.steps.navigationInstruction,routes.legs.steps.transitDetails,'
    'routes.legs.steps.polyline.encodedPolyline,'
    'routes.legs.steps.startLocation,routes.legs.steps.endLocation';

const _driveFieldMask =
    'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline';

const _walkFieldMask =
    'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline';

/// Thrown when [RouteService] can't complete a request — a missing API
/// key, a network failure, or a non-200 response from Google Routes API.
class RouteRequestException implements Exception {
  RouteRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Directions via the Google Routes API `computeRoutes` endpoint —
/// public transport (the Transport module's primary mode) and driving
/// (an optional, separately-requested comparison). Map *rendering*
/// stays OpenStreetMap/flutter_map; this only supplies the route data
/// (duration, distance, polyline, transit leg detail) to plot.
class RouteService {
  String get _apiKey => dotenv.maybeGet('GOOGLE_ROUTES_API_KEY') ?? '';

  /// Public-transport route candidates (bus/rail/etc.), most relevant
  /// first — the primary result for the Transport screen.
  Future<List<TransitRoute>> getTransitRoutes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final routes = await _computeRoutes(
      origin: origin,
      destination: destination,
      fieldMask: _transitFieldMask,
      body: {'travelMode': 'TRANSIT', 'computeAlternativeRoutes': true},
    );
    return [for (final r in routes) TransitRoute.fromJson(r)];
  }

  /// A single driving route, for the "Alternative" comparison card. Kept
  /// as a separate request from transit so a driving failure never
  /// affects transit results.
  Future<DriveRoute?> getDriveRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final routes = await _computeRoutes(
      origin: origin,
      destination: destination,
      fieldMask: _driveFieldMask,
      body: {'travelMode': 'DRIVE', 'routingPreference': 'TRAFFIC_AWARE'},
    );
    return routes.isEmpty ? null : DriveRoute.fromJson(routes.first);
  }

  /// A single walking route between two points — used by
  /// [TransitNavigationController] to reroute the current WALK segment
  /// when the traveler strays from it, and never for full trip search.
  Future<WalkingRoute?> getWalkingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final routes = await _computeRoutes(
      origin: origin,
      destination: destination,
      fieldMask: _walkFieldMask,
      body: {'travelMode': 'WALK'},
    );
    return routes.isEmpty ? null : WalkingRoute.fromJson(routes.first);
  }

  Future<List<Map<String, dynamic>>> _computeRoutes({
    required LatLng origin,
    required LatLng destination,
    required String fieldMask,
    required Map<String, dynamic> body,
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      throw RouteRequestException('Google Routes API key is not configured.');
    }
    final response = await http.post(
      Uri.parse(_computeRoutesEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': fieldMask,
      },
      body: jsonEncode({
        'origin': _location(origin),
        'destination': _location(destination),
        'languageCode': 'en-US',
        'units': 'METRIC',
        ...body,
      }),
    );
    if (response.statusCode != 200) {
      throw RouteRequestException(
        'Route request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = (decoded['routes'] as List?) ?? const [];
    return [for (final r in routes) r as Map<String, dynamic>];
  }

  Map<String, dynamic> _location(LatLng point) => {
    'location': {
      'latLng': {'latitude': point.latitude, 'longitude': point.longitude},
    },
  };
}
