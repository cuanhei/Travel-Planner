import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// west,south,east,north — a loose box around all of Malaysia (Peninsular
/// + Sabah/Sarawak), used to keep an OSM map from being panned/zoomed
/// out far enough to see other countries.
final malaysiaBounds = LatLngBounds(
  const LatLng(0.5, 99.5),
  const LatLng(7.5, 119.5),
);

/// Kuala Lumpur — a sensible default center for a Malaysia-scoped map
/// before any real data (GPS position, search result, stops) is known.
const malaysiaFallbackCenter = LatLng(3.1390, 101.6869);
