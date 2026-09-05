import 'package:flutter/material.dart';

class StreetMapPainter extends CustomPainter {
  const StreetMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEFEDE6),
    );

    final water = Path()
      ..moveTo(size.width * 0.84, 0)
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.5,
        size.width * 0.9,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFFC3E3F2));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.08,
          size.height * 0.64,
          size.width * 0.22,
          size.height * 0.26,
        ),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFFD9E8CE),
    );

    final blockPaint = Paint()..color = Colors.white.withValues(alpha: 0.65);
    for (final r in const [
      Rect.fromLTWH(0.10, 0.10, 0.20, 0.16),
      Rect.fromLTWH(0.38, 0.08, 0.16, 0.14),
      Rect.fromLTWH(0.10, 0.33, 0.16, 0.14),
      Rect.fromLTWH(0.58, 0.28, 0.14, 0.18),
      Rect.fromLTWH(0.36, 0.52, 0.14, 0.10),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            r.left * size.width,
            r.top * size.height,
            r.width * size.width,
            r.height * size.height,
          ),
          const Radius.circular(6),
        ),
        blockPaint,
      );
    }

    final minorRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    for (var i = 1; i < 6; i++) {
      final x = size.width / 6 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorRoad);
    }
    for (var i = 1; i < 5; i++) {
      final y = size.height / 5 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorRoad);
    }

    final majorRoad = Paint()
      ..color = const Color(0xFFF7D774)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height * 0.42),
      Offset(size.width, size.height * 0.38),
      majorRoad,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, 0),
      Offset(size.width * 0.5, size.height),
      majorRoad,
    );
  }

  @override
  bool shouldRepaint(covariant StreetMapPainter oldDelegate) => false;
}
