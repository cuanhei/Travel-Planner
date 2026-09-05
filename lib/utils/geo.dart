import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _earthRadiusMeters = 6371000.0;

double _degToRad(double deg) => deg * math.pi / 180;

bool isValidLatLng(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude >= -90 &&
    point.latitude <= 90 &&
    point.longitude >= -180 &&
    point.longitude <= 180;

double haversineMeters(LatLng a, LatLng b) {
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLng = _degToRad(b.longitude - a.longitude);
  final lat1 = _degToRad(a.latitude);
  final lat2 = _degToRad(b.latitude);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);
  final c = 2 * math.asin(math.sqrt(h.clamp(0, 1)));
  return _earthRadiusMeters * c;
}

({double x, double y}) _toLocalMeters(LatLng origin, LatLng point) {
  final dLat = _degToRad(point.latitude - origin.latitude);
  final dLng = _degToRad(point.longitude - origin.longitude);
  final y = dLat * _earthRadiusMeters;
  final x = dLng * _earthRadiusMeters * math.cos(_degToRad(origin.latitude));
  return (x: x, y: y);
}

class PolylineProjection {
  const PolylineProjection({
    required this.distanceToLineMeters,
    required this.distanceAlongMeters,
    required this.totalLengthMeters,
  });

  final double distanceToLineMeters;
  final double distanceAlongMeters;
  final double totalLengthMeters;

  double get fraction => totalLengthMeters <= 0
      ? 0
      : (distanceAlongMeters / totalLengthMeters).clamp(0, 1);
}

PolylineProjection? projectOntoPolyline(LatLng point, List<LatLng> polyline) {
  if (polyline.isEmpty) return null;
  if (polyline.length == 1) {
    return PolylineProjection(
      distanceToLineMeters: haversineMeters(point, polyline.first),
      distanceAlongMeters: 0,
      totalLengthMeters: 0,
    );
  }

  final origin = polyline.first;
  final local = [for (final p in polyline) _toLocalMeters(origin, p)];
  final target = _toLocalMeters(origin, point);

  var totalLength = 0.0;
  final cumulative = <double>[0];
  for (var i = 0; i < local.length - 1; i++) {
    final dx = local[i + 1].x - local[i].x;
    final dy = local[i + 1].y - local[i].y;
    totalLength += math.sqrt(dx * dx + dy * dy);
    cumulative.add(totalLength);
  }

  var bestDistance = double.infinity;
  var bestAlong = 0.0;
  for (var i = 0; i < local.length - 1; i++) {
    final a = local[i];
    final b = local[i + 1];
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final segLenSq = abx * abx + aby * aby;
    final t = segLenSq == 0
        ? 0.0
        : (((target.x - a.x) * abx + (target.y - a.y) * aby) / segLenSq).clamp(
            0.0,
            1.0,
          );
    final projX = a.x + abx * t;
    final projY = a.y + aby * t;
    final dx = target.x - projX;
    final dy = target.y - projY;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < bestDistance) {
      bestDistance = distance;
      final segLen = math.sqrt(segLenSq);
      bestAlong = cumulative[i] + segLen * t;
    }
  }

  return PolylineProjection(
    distanceToLineMeters: bestDistance,
    distanceAlongMeters: bestAlong,
    totalLengthMeters: totalLength,
  );
}
