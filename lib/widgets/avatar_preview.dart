import 'package:flutter/material.dart';

import '../models/avatar_config.dart';

class AvatarPreview extends StatelessWidget {
  const AvatarPreview({
    super.key,
    required this.config,
    this.width = 190,
    this.height = 240,
  });

  final AvatarConfig config;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: AvatarPainter(config),
    );
  }
}

class _M {
  _M(Size size, AvatarGender gender) {
    s = size.width;
    cx = s / 2;
    headCy = 0.185 * s;
    headR = 0.115 * s;
    headBottomY = headCy + headR * 0.85;
    shoulderY = 0.305 * s;
    waistY = 0.605 * s;
    kneeY = 0.72 * s;
    ankleY = 0.85 * s;
    footY = 0.965 * s;
    shoulderHW = gender == AvatarGender.female ? 0.17 * s : 0.20 * s;
    neckW = 0.06 * s;
    armWidth = 0.07 * s;
    armEndY = waistY - 0.03 * s;
    handR = 0.045 * s;
    legHW = 0.075 * s;
    legGap = 0.02 * s;
  }

  late double s,
      cx,
      headCy,
      headR,
      headBottomY,
      shoulderY,
      waistY,
      kneeY,
      ankleY,
      footY,
      shoulderHW,
      neckW,
      armWidth,
      armEndY,
      handR,
      legHW,
      legGap;

  double get leftLegCx => cx - (legGap + legHW);
  double get rightLegCx => cx + (legGap + legHW);
  double get leftArmCx => cx - shoulderHW - armWidth * 0.5;
  double get rightArmCx => cx + shoulderHW + armWidth * 0.5;
}

class AvatarPainter extends CustomPainter {
  AvatarPainter(this.config);

  final AvatarConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final m = _M(size, config.gender);
    final skin = config.skinTone == 0
        ? const Color(0xFFF1C27D)
        : Color(config.skinTone);
    final headC = Offset(m.cx, m.headCy);
    final acc = config.accessories;

    if (acc.contains('backpack')) _paintBackpackBody(canvas, m);

    _legPair(canvas, m, Paint()..color = skin, m.waistY, m.ankleY);
    for (final acx in [m.leftArmCx, m.rightArmCx]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            acx - m.armWidth / 2,
            m.shoulderY,
            acx + m.armWidth / 2,
            m.armEndY,
          ),
          Radius.circular(m.armWidth * 0.5),
        ),
        Paint()..color = skin,
      );
      canvas.drawCircle(Offset(acx, m.armEndY), m.handR, Paint()..color = skin);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          m.cx - m.shoulderHW,
          m.shoulderY,
          m.cx + m.shoulderHW,
          m.waistY,
        ),
        Radius.circular(m.shoulderHW * 0.3),
      ),
      Paint()..color = skin,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        m.cx - m.neckW / 2,
        m.headBottomY,
        m.cx + m.neckW / 2,
        m.shoulderY + 2,
      ),
      Paint()..color = skin,
    );

    if (config.top != 'dress') _paintBottom(canvas, m, config);
    _paintSocks(canvas, m, config);
    _paintShoes(canvas, m, config);
    _paintTop(canvas, m, config);
    if (acc.contains('backpack')) _paintBackpackStraps(canvas, m);
    if (acc.contains('scarf')) _paintScarf(canvas, m, const Color(0xFFD32F2F));
    if (acc.contains('watch')) _paintWatch(canvas, m);

    canvas.drawCircle(headC, m.headR, Paint()..color = skin);
    _paintHair(
      canvas,
      headC,
      m.headR,
      config.hairStyle,
      Color(config.hairColor),
    );
    if (acc.contains('earrings')) _paintEarrings(canvas, headC, m.headR);
    _paintFace(canvas, headC, m.headR, config.expression);
    if (acc.contains('glasses')) _paintGlasses(canvas, headC, m.headR, false);
    if (acc.contains('sunglasses')) _paintGlasses(canvas, headC, m.headR, true);
    _paintHat(canvas, headC, m.headR, config.hat, Color(config.hatColor));
  }

  @override
  bool shouldRepaint(covariant AvatarPainter oldDelegate) => true;

  double _bottomHemY(_M m, AvatarConfig c) {
    switch (c.bottom) {
      case 'shorts':
        return m.waistY + (m.kneeY - m.waistY) * 0.55;
      case 'skirt':
        return m.waistY + (m.kneeY - m.waistY) * 0.7;
      default:
        return m.ankleY - 4;
    }
  }

  void _legPair(
    Canvas canvas,
    _M m,
    Paint paint,
    double top,
    double bottom, {
    double widen = 1.0,
  }) {
    final lw = m.legHW * widen;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(m.leftLegCx - lw, top, m.leftLegCx + lw, bottom),
        Radius.circular(lw * 0.5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(m.rightLegCx - lw, top, m.rightLegCx + lw, bottom),
        Radius.circular(lw * 0.5),
      ),
      paint,
    );
  }

  void _paintBottom(Canvas canvas, _M m, AvatarConfig c) {
    final paint = Paint()..color = Color(c.bottomColor);
    switch (c.bottom) {
      case 'shorts':
        _legPair(canvas, m, paint, m.waistY, _bottomHemY(m, c), widen: 1.05);
        break;
      case 'skirt':
        final endY = _bottomHemY(m, c);
        final rect = Rect.fromLTRB(
          m.cx - m.shoulderHW * 1.15,
          m.waistY,
          m.cx + m.shoulderHW * 1.15,
          endY,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            bottomLeft: const Radius.circular(10),
            bottomRight: const Radius.circular(10),
          ),
          paint,
        );
        break;
      case 'cargo':
        _legPair(canvas, m, paint, m.waistY, m.ankleY - 4, widen: 1.15);
        final pocket = Paint()..color = paint.color.withValues(alpha: 0.75);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              m.leftLegCx - m.legHW * 1.1,
              m.kneeY,
              m.leftLegCx + m.legHW * 0.2,
              m.kneeY + m.legHW * 0.9,
            ),
            const Radius.circular(4),
          ),
          pocket,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              m.rightLegCx - m.legHW * 0.2,
              m.kneeY,
              m.rightLegCx + m.legHW * 1.1,
              m.kneeY + m.legHW * 0.9,
            ),
            const Radius.circular(4),
          ),
          pocket,
        );
        break;
      case 'jeans':
      default:
        _legPair(canvas, m, paint, m.waistY, m.ankleY - 4, widen: 1.1);
    }
  }

  void _paintSocks(Canvas canvas, _M m, AvatarConfig c) {
    if (c.socks == 'none') return;
    final hem = c.top == 'dress' ? _bottomHemY(m, c) : _bottomHemY(m, c);
    final tall = c.socks == 'high' || c.socks == 'striped';
    var top = tall ? m.kneeY : m.ankleY - m.s * 0.05;
    if (top < hem) top = hem;
    final bottom = m.ankleY + m.s * 0.03;
    if (top >= bottom) return;
    final paint = Paint()..color = Color(c.socksColor);
    _legPair(canvas, m, paint, top, bottom, widen: 1.08);
    if (c.socks == 'striped') {
      final stripe = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = m.s * 0.012;
      for (final lcx in [m.leftLegCx, m.rightLegCx]) {
        for (
          var y = top + (bottom - top) * 0.3;
          y < bottom;
          y += (bottom - top) * 0.35
        ) {
          canvas.drawLine(
            Offset(lcx - m.legHW * 1.08, y),
            Offset(lcx + m.legHW * 1.08, y),
            stripe,
          );
        }
      }
    }
  }

  void _paintShoes(Canvas canvas, _M m, AvatarConfig c) {
    final paint = Paint()..color = Color(c.shoesColor);
    double top;
    switch (c.shoes) {
      case 'boots':
        top = m.kneeY + (m.ankleY - m.kneeY) * 0.4;
        break;
      case 'sandals':
        top = m.ankleY + m.s * 0.05;
        break;
      case 'flats':
        top = m.ankleY + m.s * 0.02;
        break;
      case 'sneakers':
      default:
        top = m.ankleY - m.s * 0.01;
    }
    final bottom = m.footY;
    for (final lcx in [m.leftLegCx, m.rightLegCx]) {
      final rect = Rect.fromLTRB(
        lcx - m.legHW * 1.15,
        top,
        lcx + m.legHW * 1.15,
        bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(m.legHW * 0.55)),
        paint,
      );
      if (c.shoes == 'sneakers') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              lcx - m.legHW * 1.15,
              bottom - m.s * 0.02,
              lcx + m.legHW * 1.15,
              bottom,
            ),
            Radius.circular(m.s * 0.01),
          ),
          Paint()..color = Colors.white,
        );
      }
      if (c.shoes == 'sandals') {
        canvas.drawLine(
          Offset(lcx - m.legHW, top + m.s * 0.015),
          Offset(lcx + m.legHW, top + m.s * 0.015),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = m.s * 0.012,
        );
      }
    }
  }

  void _paintTop(Canvas canvas, _M m, AvatarConfig c) {
    final paint = Paint()..color = Color(c.topColor);
    final sleeveEnd = switch (c.top) {
      'tank' => m.shoulderY + (m.armEndY - m.shoulderY) * 0.15,
      'tshirt' => m.shoulderY + (m.armEndY - m.shoulderY) * 0.5,
      'dress' => m.shoulderY + (m.armEndY - m.shoulderY) * 0.55,
      _ => m.armEndY,
    };
    for (final acx in [m.leftArmCx, m.rightArmCx]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            acx - m.armWidth * 0.65,
            m.shoulderY,
            acx + m.armWidth * 0.65,
            sleeveEnd,
          ),
          Radius.circular(m.armWidth * 0.4),
        ),
        paint,
      );
    }

    final torsoBottom = c.top == 'dress'
        ? _bottomHemY(m, c)
        : m.waistY + m.s * 0.01;
    final bottomHW = c.top == 'dress'
        ? m.shoulderHW * 1.25
        : m.shoulderHW * 1.05;
    if (c.top == 'dress') {
      final path = Path()
        ..moveTo(m.cx - m.shoulderHW * 1.05, m.shoulderY)
        ..lineTo(m.cx + m.shoulderHW * 1.05, m.shoulderY)
        ..lineTo(m.cx + bottomHW, torsoBottom)
        ..lineTo(m.cx - bottomHW, torsoBottom)
        ..close();
      canvas.drawPath(path, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            m.cx - m.shoulderHW * 1.05,
            m.shoulderY - m.s * 0.01,
            m.cx + m.shoulderHW * 1.05,
            torsoBottom,
          ),
          Radius.circular(m.shoulderHW * 0.3),
        ),
        paint,
      );
    }

    if (c.top == 'hoodie') {
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(m.cx, m.headBottomY),
          radius: m.headR * 1.15,
        ),
        3.4,
        2.7,
        false,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = m.s * 0.05,
      );
    }
    if (c.top == 'jacket') {
      canvas.drawLine(
        Offset(m.cx, m.shoulderY),
        Offset(m.cx, torsoBottom),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = m.s * 0.008,
      );
      final collar = Path()
        ..moveTo(m.cx - m.neckW, m.shoulderY)
        ..lineTo(m.cx, m.shoulderY + m.s * 0.04)
        ..lineTo(m.cx + m.neckW, m.shoulderY)
        ..close();
      canvas.drawPath(
        collar,
        Paint()..color = Colors.black.withValues(alpha: 0.15),
      );
    }
  }

  void _paintBackpackBody(Canvas canvas, _M m) {
    final rect = Rect.fromLTRB(
      m.cx - m.shoulderHW * 1.2,
      m.shoulderY + m.s * 0.02,
      m.cx + m.shoulderHW * 1.2,
      m.waistY + m.s * 0.02,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(m.s * 0.03)),
      Paint()..color = const Color(0xFF6D4C41),
    );
  }

  void _paintBackpackStraps(Canvas canvas, _M m) {
    final strap = Paint()
      ..color = const Color(0xFF4E342E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = m.s * 0.025;
    canvas.drawLine(
      Offset(m.cx - m.shoulderHW * 0.6, m.shoulderY - m.s * 0.01),
      Offset(m.cx - m.shoulderHW * 0.3, m.waistY),
      strap,
    );
    canvas.drawLine(
      Offset(m.cx + m.shoulderHW * 0.6, m.shoulderY - m.s * 0.01),
      Offset(m.cx + m.shoulderHW * 0.3, m.waistY),
      strap,
    );
  }

  void _paintScarf(Canvas canvas, _M m, Color color) {
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          m.cx - m.neckW * 1.4,
          m.headBottomY,
          m.cx + m.neckW * 1.4,
          m.shoulderY + m.s * 0.03,
        ),
        Radius.circular(m.s * 0.02),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          m.cx - m.s * 0.03,
          m.shoulderY,
          m.cx + m.s * 0.03,
          m.shoulderY + m.s * 0.09,
        ),
        Radius.circular(m.s * 0.015),
      ),
      paint,
    );
  }

  void _paintWatch(Canvas canvas, _M m) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          m.rightArmCx - m.armWidth * 0.55,
          m.armEndY - m.s * 0.05,
          m.rightArmCx + m.armWidth * 0.55,
          m.armEndY - m.s * 0.01,
        ),
        Radius.circular(m.s * 0.01),
      ),
      Paint()..color = const Color(0xFF263238),
    );
  }

  void _paintHair(
    Canvas canvas,
    Offset c,
    double r,
    String style,
    Color color,
  ) {
    final paint = Paint()..color = color;
    switch (style) {
      case 'bald':
        return;
      case 'short':
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.05),
          3.5,
          2.6,
          true,
          paint,
        );
        break;
      case 'medium':
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.12),
          3.3,
          2.9,
          true,
          paint,
        );
        break;
      case 'long':
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.1),
          3.3,
          2.9,
          true,
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              c.dx - r * 1.15,
              c.dy - r * 0.2,
              c.dx - r * 0.75,
              c.dy + r * 2.2,
            ),
            Radius.circular(r * 0.35),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              c.dx + r * 0.75,
              c.dy - r * 0.2,
              c.dx + r * 1.15,
              c.dy + r * 2.2,
            ),
            Radius.circular(r * 0.35),
          ),
          paint,
        );
        break;
      case 'curly':
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.1),
          3.3,
          2.9,
          true,
          paint,
        );
        for (final dx in [-0.75, -0.35, 0.05, 0.45, 0.8]) {
          canvas.drawCircle(
            Offset(c.dx + dx * r, c.dy - r * 0.75),
            r * 0.35,
            paint,
          );
        }
        break;
      case 'bun':
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.05),
          3.5,
          2.6,
          true,
          paint,
        );
        canvas.drawCircle(Offset(c.dx, c.dy - r * 1.25), r * 0.4, paint);
        break;
    }
  }

  void _mouth(
    Canvas canvas,
    Offset c,
    double r,
    Paint stroke, {
    bool smile = true,
  }) {
    final p = Path()
      ..moveTo(c.dx - r * 0.22, c.dy + r * 0.32)
      ..quadraticBezierTo(
        c.dx,
        c.dy + (smile ? r * 0.55 : r * 0.32),
        c.dx + r * 0.22,
        c.dy + r * 0.32,
      );
    canvas.drawPath(p, stroke);
  }

  void _paintFace(Canvas canvas, Offset c, double r, String expression) {
    final eye = Paint()..color = const Color(0xFF2B2B2B);
    Paint stroke() => Paint()
      ..color = const Color(0xFF2B2B2B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round;
    final ex = r * 0.4, ey = -r * 0.05;
    switch (expression) {
      case 'wink':
        canvas.drawCircle(Offset(c.dx - ex, c.dy + ey), r * 0.09, eye);
        canvas.drawLine(
          Offset(c.dx + ex - r * 0.12, c.dy + ey),
          Offset(c.dx + ex + r * 0.12, c.dy + ey),
          stroke(),
        );
        _mouth(canvas, c, r, stroke());
        break;
      case 'surprised':
        for (final dx in [-ex, ex]) {
          canvas.drawCircle(
            Offset(c.dx + dx, c.dy + ey),
            r * 0.13,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            Offset(c.dx + dx, c.dy + ey),
            r * 0.13,
            Paint()
              ..color = const Color(0xFF2B2B2B)
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.05,
          );
          canvas.drawCircle(Offset(c.dx + dx, c.dy + ey), r * 0.06, eye);
        }
        canvas.drawCircle(
          Offset(c.dx, c.dy + r * 0.35),
          r * 0.09,
          Paint()..color = const Color(0xFF2B2B2B),
        );
        break;
      case 'neutral':
        canvas.drawCircle(Offset(c.dx - ex, c.dy + ey), r * 0.09, eye);
        canvas.drawCircle(Offset(c.dx + ex, c.dy + ey), r * 0.09, eye);
        canvas.drawLine(
          Offset(c.dx - r * 0.15, c.dy + r * 0.38),
          Offset(c.dx + r * 0.15, c.dy + r * 0.38),
          stroke(),
        );
        break;
      case 'cool':
        canvas.drawCircle(Offset(c.dx - ex, c.dy + ey), r * 0.09, eye);
        canvas.drawCircle(Offset(c.dx + ex, c.dy + ey), r * 0.09, eye);
        final p = Path()
          ..moveTo(c.dx - r * 0.18, c.dy + r * 0.36)
          ..quadraticBezierTo(
            c.dx,
            c.dy + r * 0.3,
            c.dx + r * 0.2,
            c.dy + r * 0.4,
          );
        canvas.drawPath(p, stroke());
        break;
      case 'happy':
      default:
        canvas.drawCircle(Offset(c.dx - ex, c.dy + ey), r * 0.09, eye);
        canvas.drawCircle(Offset(c.dx + ex, c.dy + ey), r * 0.09, eye);
        _mouth(canvas, c, r, stroke());
    }
  }

  void _paintGlasses(Canvas canvas, Offset c, double r, bool sun) {
    final frameColor = sun ? const Color(0xFF1A1A1A) : const Color(0xFF37474F);
    final lensPaint = Paint()
      ..color = sun
          ? const Color(0xFF1A1A1A)
          : Colors.white.withValues(alpha: 0.15);
    final frame = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06;
    final ex = r * 0.4, ey = -r * 0.05, lw = r * 0.32, lh = r * 0.24;
    for (final dx in [-ex, ex]) {
      final rect = Rect.fromCenter(
        center: Offset(c.dx + dx, c.dy + ey),
        width: lw,
        height: lh,
      );
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(r * 0.08));
      canvas.drawRRect(rr, lensPaint);
      canvas.drawRRect(rr, frame);
    }
    canvas.drawLine(
      Offset(c.dx - ex + lw / 2, c.dy + ey),
      Offset(c.dx + ex - lw / 2, c.dy + ey),
      frame,
    );
  }

  void _paintEarrings(Canvas canvas, Offset c, double r) {
    final paint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawCircle(Offset(c.dx - r * 0.95, c.dy + r * 0.3), r * 0.09, paint);
    canvas.drawCircle(Offset(c.dx + r * 0.95, c.dy + r * 0.3), r * 0.09, paint);
  }

  void _paintHat(Canvas canvas, Offset c, double r, String style, Color color) {
    final paint = Paint()..color = color;
    switch (style) {
      case 'none':
        return;
      case 'cap':
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(c.dx, c.dy - r * 0.05),
            radius: r * 1.08,
          ),
          3.4,
          2.9,
          true,
          paint,
        );
        final brim = Path()
          ..moveTo(c.dx - r * 0.1, c.dy - r * 0.55)
          ..quadraticBezierTo(
            c.dx + r * 0.75,
            c.dy - r * 0.7,
            c.dx + r * 0.85,
            c.dy - r * 0.35,
          )
          ..quadraticBezierTo(
            c.dx + r * 0.3,
            c.dy - r * 0.35,
            c.dx - r * 0.1,
            c.dy - r * 0.35,
          )
          ..close();
        canvas.drawPath(brim, paint);
        break;
      case 'beanie':
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(c.dx, c.dy - r * 0.1),
            radius: r * 1.12,
          ),
          3.14,
          3.14,
          true,
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              c.dx - r * 1.1,
              c.dy - r * 0.35,
              c.dx + r * 1.1,
              c.dy - r * 0.05,
            ),
            Radius.circular(r * 0.15),
          ),
          Paint()..color = Color.lerp(color, Colors.white, 0.2)!,
        );
        canvas.drawCircle(
          Offset(c.dx, c.dy - r * 1.2),
          r * 0.13,
          Paint()..color = Color.lerp(color, Colors.white, 0.3)!,
        );
        break;
      case 'sunhat':
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(c.dx, c.dy - r * 0.5),
            width: r * 3.0,
            height: r * 0.9,
          ),
          paint,
        );
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(c.dx, c.dy - r * 0.65),
            radius: r * 0.85,
          ),
          3.14,
          3.14,
          true,
          paint,
        );
        break;
      case 'headband':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              c.dx - r * 1.02,
              c.dy - r * 0.35,
              c.dx + r * 1.02,
              c.dy - r * 0.1,
            ),
            Radius.circular(r * 0.1),
          ),
          paint,
        );
        break;
      case 'cowboy':
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(c.dx, c.dy - r * 0.45),
            width: r * 3.2,
            height: r * 0.85,
          ),
          paint,
        );
        final crown = Path()
          ..moveTo(c.dx - r * 0.7, c.dy - r * 0.5)
          ..quadraticBezierTo(
            c.dx,
            c.dy - r * 1.5,
            c.dx + r * 0.7,
            c.dy - r * 0.5,
          )
          ..close();
        canvas.drawPath(crown, paint);
        break;
    }
  }
}
