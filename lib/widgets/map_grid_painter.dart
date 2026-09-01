import 'package:flutter/material.dart';

/// Faint grid backdrop used by the app's stylized (non-SDK) map
/// surfaces — no real map/geo API involved, purely decorative.
class MapGridPainter extends CustomPainter {
  const MapGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
