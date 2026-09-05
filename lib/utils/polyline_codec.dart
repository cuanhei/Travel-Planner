import 'package:latlong2/latlong.dart';

List<LatLng> decodePolyline(String encoded) {
  if (encoded.isEmpty) return const [];
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < encoded.length) {
    var result = 0;
    var shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    result = 0;
    shift = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
