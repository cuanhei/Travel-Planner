import 'package:latlong2/latlong.dart';

import '../utils/google_routes_parsing.dart';
import '../utils/polyline_codec.dart';

enum TransitVehicleType { bus, rail, subway, lightRail, tram, ferry, other }

TransitVehicleType _vehicleTypeFrom(String? raw) {
  switch (raw) {
    case 'BUS':
    case 'INTERCITY_BUS':
    case 'TROLLEYBUS':
      return TransitVehicleType.bus;
    case 'SUBWAY':
      return TransitVehicleType.subway;
    case 'LIGHT_RAIL':
      return TransitVehicleType.lightRail;
    case 'RAIL':
    case 'HEAVY_RAIL':
    case 'COMMUTER_TRAIN':
    case 'HIGH_SPEED_TRAIN':
    case 'LONG_DISTANCE_TRAIN':
      return TransitVehicleType.rail;
    case 'TRAM':
    case 'MONORAIL':
    case 'CABLE_CAR':
    case 'GONDOLA_LIFT':
    case 'FUNICULAR':
      return TransitVehicleType.tram;
    case 'FERRY':
      return TransitVehicleType.ferry;
    default:
      return TransitVehicleType.other;
  }
}

class TransitLegDetails {
  const TransitLegDetails({
    required this.lineName,
    required this.lineShortName,
    required this.vehicleType,
    required this.departureStop,
    required this.arrivalStop,
    required this.departureTime,
    required this.arrivalTime,
    required this.stopCount,
    required this.headsign,
    this.departureStopLocation,
    this.arrivalStopLocation,
  });

  final String lineName;
  final String? lineShortName;
  final TransitVehicleType vehicleType;
  final String departureStop;
  final String arrivalStop;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final int? stopCount;
  final String? headsign;

  final LatLng? departureStopLocation;
  final LatLng? arrivalStopLocation;

  factory TransitLegDetails.fromJson(Map<String, dynamic> json) {
    final line = (json['transitLine'] as Map<String, dynamic>?) ?? const {};
    final vehicle = (line['vehicle'] as Map<String, dynamic>?) ?? const {};
    final stopDetails =
        (json['stopDetails'] as Map<String, dynamic>?) ?? const {};
    final departureStop =
        (stopDetails['departureStop'] as Map<String, dynamic>?) ?? const {};
    final arrivalStop =
        (stopDetails['arrivalStop'] as Map<String, dynamic>?) ?? const {};
    return TransitLegDetails(
      lineName:
          (line['name'] as String?) ??
          (line['nameShort'] as String?) ??
          'Transit',
      lineShortName: line['nameShort'] as String?,
      vehicleType: _vehicleTypeFrom(vehicle['type'] as String?),
      departureStop: (departureStop['name'] as String?) ?? 'Departure stop',
      arrivalStop: (arrivalStop['name'] as String?) ?? 'Arrival stop',
      departureTime: DateTime.tryParse(
        (stopDetails['departureTime'] as String?) ?? '',
      ),
      arrivalTime: DateTime.tryParse(
        (stopDetails['arrivalTime'] as String?) ?? '',
      ),
      stopCount: (json['stopCount'] as num?)?.toInt(),
      headsign: json['headsign'] as String?,
      departureStopLocation: _latLngFromLocation(departureStop['location']),
      arrivalStopLocation: _latLngFromLocation(arrivalStop['location']),
    );
  }
}

LatLng? _latLngFromLocation(dynamic location) {
  if (location is! Map<String, dynamic>) return null;
  final latLng = location['latLng'] as Map<String, dynamic>?;
  final lat = (latLng?['latitude'] as num?)?.toDouble();
  final lng = (latLng?['longitude'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

enum TransitStepType { walk, transit }

class TransitStep {
  const TransitStep({
    required this.type,
    required this.duration,
    required this.polylinePoints,
    this.startLocation,
    this.endLocation,
    this.instructions,
    this.details,
  });

  final TransitStepType type;
  final Duration duration;

  final List<LatLng> polylinePoints;
  final LatLng? startLocation;
  final LatLng? endLocation;

  final String? instructions;

  final TransitLegDetails? details;

  factory TransitStep.fromJson(Map<String, dynamic> json) {
    final isTransit = json['travelMode'] == 'TRANSIT';
    final nav =
        (json['navigationInstruction'] as Map<String, dynamic>?) ?? const {};
    final transitDetails = json['transitDetails'] as Map<String, dynamic>?;
    final polyline =
        (json['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    return TransitStep(
      type: isTransit ? TransitStepType.transit : TransitStepType.walk,
      duration: parseGoogleDuration(json['staticDuration'] as String?),
      polylinePoints: decodePolyline(polyline ?? ''),
      startLocation: _latLngFromLocation(json['startLocation']),
      endLocation: _latLngFromLocation(json['endLocation']),
      instructions: nav['instructions'] as String?,
      details: isTransit && transitDetails != null
          ? TransitLegDetails.fromJson(transitDetails)
          : null,
    );
  }
}

class TransitRoute {
  const TransitRoute({
    required this.duration,
    required this.distanceMeters,
    required this.polylinePoints,
    required this.steps,
  });

  final Duration duration;
  final int distanceMeters;
  final List<LatLng> polylinePoints;
  final List<TransitStep> steps;

  List<TransitStep> get transitLegs =>
      steps.where((s) => s.type == TransitStepType.transit).toList();

  int get transferCount => transitLegs.isEmpty ? 0 : transitLegs.length - 1;

  List<TransitVehicleType> get vehicleSequence {
    final seen = <TransitVehicleType>{};
    final ordered = <TransitVehicleType>[];
    for (final leg in transitLegs) {
      final type = leg.details?.vehicleType ?? TransitVehicleType.other;
      if (seen.add(type)) ordered.add(type);
    }
    return ordered;
  }

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    final legs = (json['legs'] as List?) ?? const [];
    final steps = <TransitStep>[
      for (final leg in legs)
        for (final step
            in ((leg as Map<String, dynamic>)['steps'] as List? ?? const []))
          TransitStep.fromJson(step as Map<String, dynamic>),
    ];
    final polyline =
        (json['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    return TransitRoute(
      duration: parseGoogleDuration(json['duration'] as String?),
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      polylinePoints: decodePolyline(polyline ?? ''),
      steps: steps,
    );
  }
}
