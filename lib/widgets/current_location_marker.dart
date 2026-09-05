import 'package:flutter/material.dart';

class CurrentLocationMarker extends StatefulWidget {
  const CurrentLocationMarker({super.key});

  @override
  State<CurrentLocationMarker> createState() => _CurrentLocationMarkerState();
}

class _CurrentLocationMarkerState extends State<CurrentLocationMarker>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Opacity(
                opacity: (1 - t).clamp(0.0, 1.0) * 0.5,
                child: Transform.scale(
                  scale: 0.4 + t * 1.6,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E9CCA),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF2E9CCA),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
