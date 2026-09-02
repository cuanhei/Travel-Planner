import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/current_location_marker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/map_label_pill.dart';
import '../../widgets/street_map_painter.dart';

/// UI-only stylized map — no map SDK/API. By default (e.g. from the
/// home dashboard) it shows just the traveler's current location. From
/// Trip Details, [showStops] plots the trip's stops and the route
/// between them on top of that.
class MapViewScreen extends StatelessWidget {
  const MapViewScreen({super.key, this.showStops = false});

  /// When true, plots the trip's stops and the dashed route between
  /// them in addition to the current-location marker.
  final bool showStops;

  static const _currentLocationName = 'Komtar, George Town';
  static const _currentLocation = Alignment(0, -0.1);

  static List<({String name, double top, double left, Color color})> _pins(
    BuildContext context,
  ) => [
    (name: 'Komtar', top: 0.28, left: 0.30, color: context.colors.ink),
    (name: 'Gurney', top: 0.52, left: 0.68, color: Color(0xFF5C6BC0)),
    (name: 'Queensbay', top: 0.78, left: 0.40, color: Color(0xFFFF7A59)),
  ];

  @override
  Widget build(BuildContext context) {
    final pins = showStops ? _pins(context) : const <({String name, double top, double left, Color color})>[];
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('trip_map_view_title'),
              subtitle: showStops
                  ? tr('trip_map_view_subtitle_route')
                  : tr('trip_map_view_subtitle_current'),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(color: Color(0xFFEFEDE6)),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: StreetMapPainter()),
                        ),
                        if (showStops) ...[
                          CustomPaint(
                            size: Size.infinite,
                            painter: _RoutePainter(
                              points: pins.map((p) => Offset(p.left, p.top)).toList(),
                              color: context.colors.ink,
                            ),
                          ),
                          ...pins.map((pin) {
                            return Align(
                              alignment: Alignment(
                                pin.left * 2 - 1,
                                pin.top * 2 - 1,
                              ),
                              child: _MapPin(label: pin.name, color: pin.color),
                            );
                          }),
                        ],
                        Align(
                          alignment: _currentLocation,
                          child: const CurrentLocationMarker(),
                        ),
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: MapLabelPill(
                            text: '${tr('trip_map_you_are_here')} · $_currentLocationName',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: 2),
        Icon(Icons.location_on_rounded, color: color, size: 30),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(dashPath(path, dashLength: 6, gapLength: 5), paint);
  }

  Path dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        final next = (distance + len).clamp(0, metric.length).toDouble();
        if (draw) {
          dest.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        distance = next;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      color != oldDelegate.color || points != oldDelegate.points;
}
