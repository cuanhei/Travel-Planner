import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/current_location_marker.dart';
import '../../widgets/street_map_painter.dart';
import 'transport_routes_screen.dart';

class _NavStep {
  const _NavStep({
    required this.title,
    required this.detail,
    required this.icon,
    required this.minutes,
  });

  final String title;
  final String detail;
  final IconData icon;
  final int minutes;
}

/// UI-only "live" navigation view for one bus departure: a stylized map
/// with the traveler's position animating along the route, plus a
/// bottom card walking through walk → wait → ride → alight with a live
/// countdown per step. No real GPS/turn-by-turn — each step's timer is
/// simulated so the flow still feels like it's progressing.
class StartNavigationScreen extends StatefulWidget {
  const StartNavigationScreen({super.key, required this.departure});

  final BusDeparture departure;

  @override
  State<StartNavigationScreen> createState() => _StartNavigationScreenState();
}

class _StartNavigationScreenState extends State<StartNavigationScreen>
    with SingleTickerProviderStateMixin {
  static const _start = Alignment(-0.7, 0.7);
  static const _end = Alignment(0.7, -0.7);

  late final List<_NavStep> _steps = [
    _NavStep(
      title: tr('transport_step_walk_to_title').replaceAll(
        '{stop}',
        widget.departure.nearestStop,
      ),
      detail: tr('transport_step_walk_to_detail').replaceAll(
        '{min}',
        '${widget.departure.walkToStopMinutes}',
      ),
      icon: Icons.directions_walk_rounded,
      minutes: widget.departure.walkToStopMinutes,
    ),
    _NavStep(
      title: tr('transport_step_wait_title').replaceAll(
        '{bus}',
        widget.departure.busNumber,
      ),
      detail: tr('transport_step_wait_detail').replaceAll(
        '{min}',
        '${widget.departure.waitMinutes}',
      ),
      icon: Icons.schedule_rounded,
      minutes: widget.departure.waitMinutes,
    ),
    _NavStep(
      title: tr('transport_step_ride_title').replaceAll(
        '{bus}',
        widget.departure.busNumber,
      ),
      detail: tr('transport_step_ride_fare_detail')
          .replaceAll('{min}', '${widget.departure.rideMinutes}')
          .replaceAll('{fare}', widget.departure.fare),
      icon: Icons.directions_bus_filled_rounded,
      minutes: widget.departure.rideMinutes,
    ),
    _NavStep(
      title: tr('transport_step_walk_dest_title').replaceAll(
        '{dest}',
        widget.departure.destinationName,
      ),
      detail: tr('transport_step_walk_dest_detail').replaceAll(
        '{min}',
        '${widget.departure.walkFromStopMinutes}',
      ),
      icon: Icons.flag_rounded,
      minutes: widget.departure.walkFromStopMinutes,
    ),
  ];

  late final AnimationController _controller;
  int _stepIndex = 0;
  bool _arrived = false;

  int get _totalMinutes => _steps.fold(0, (sum, s) => sum + s.minutes);

  int get _elapsedBeforeCurrent =>
      _steps.take(_stepIndex).fold(0, (sum, s) => sum + s.minutes);

  Duration _durationFor(int minutes) =>
      Duration(milliseconds: (minutes * 650).clamp(1200, 6000));

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(_steps.first.minutes),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _advance();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    if (_stepIndex >= _steps.length - 1) {
      setState(() => _arrived = true);
      return;
    }
    setState(() => _stepIndex += 1);
    _controller
      ..duration = _durationFor(_steps[_stepIndex].minutes)
      ..reset()
      ..forward();
  }

  void _skip() {
    if (_arrived) return;
    _controller.stop();
    _advance();
  }

  double get _liveFraction {
    final current = _steps[_stepIndex];
    final elapsed = _elapsedBeforeCurrent + current.minutes * _controller.value;
    return (elapsed / _totalMinutes).clamp(0.0, 1.0);
  }

  int get _minutesRemaining {
    final current = _steps[_stepIndex];
    final elapsed = _elapsedBeforeCurrent + current.minutes * _controller.value;
    return (_totalMinutes - elapsed).round().clamp(0, _totalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: context.colors.ink),
                  ),
                  Expanded(
                    child: Text(
                      tr('transport_bus_to_subtitle')
                          .replaceAll('{bus}', widget.departure.busNumber)
                          .replaceAll(
                            '{dest}',
                            widget.departure.destinationName,
                          ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: List.generate(_steps.length, (i) {
                  final done = i < _stepIndex || _arrived;
                  final active = i == _stepIndex && !_arrived;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i == _steps.length - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: done
                            ? const Color(0xFF11998E)
                            : active
                            ? AppColors.accent
                            : context.colors.muted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    color: const Color(0xFFEFEDE6),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: StreetMapPainter()),
                        ),
                        const Positioned.fill(
                          child: CustomPaint(
                            painter: _DashedRoutePainter(from: _start, to: _end),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) => Align(
                            alignment: Alignment.lerp(
                              _start,
                              _end,
                              _arrived ? 1.0 : _liveFraction,
                            )!,
                            child: child,
                          ),
                          child: const CurrentLocationMarker(),
                        ),
                        const Align(
                          alignment: _end,
                          child: _DestinationPin(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _arrived
                  ? _ArrivedCard(
                      destinationName: widget.departure.destinationName,
                      onDone: () => Navigator.of(context).maybePop(),
                    )
                  : AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _StepCard(
                        step: _steps[_stepIndex],
                        progress: _controller.value,
                        minutesRemaining: _minutesRemaining,
                        isLastStep: _stepIndex == _steps.length - 1,
                        onSkip: _skip,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.progress,
    required this.minutesRemaining,
    required this.isLastStep,
    required this.onSkip,
  });

  final _NavStep step;
  final double progress;
  final int minutesRemaining;
  final bool isLastStep;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(step.icon, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      step.detail,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$minutesRemaining ${tr('transport_min')}',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    tr('transport_left'),
                    style: TextStyle(color: context.colors.muted, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: context.colors.surface,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                backgroundColor: context.colors.surface,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                isLastStep
                    ? tr('transport_arrived_button')
                    : tr('transport_skip_next_step'),
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivedCard extends StatelessWidget {
  const _ArrivedCard({required this.destinationName, required this.onDone});

  final String destinationName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.lagoon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.lagoon.last.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('transport_arrived_at').replaceAll(
                    '{dest}',
                    destinationName,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onDone,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    tr('transport_done'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on_rounded,
      color: AppColors.accent,
      size: 34,
    );
  }
}

class _DashedRoutePainter extends CustomPainter {
  const _DashedRoutePainter({required this.from, required this.to});

  final Alignment from;
  final Alignment to;

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = from.alongSize(size);
    final p2 = to.alongSize(size);
    final total = (p2 - p1).distance;
    if (total == 0) return;
    final direction = (p2 - p1) / total;
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.7)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const dash = 8.0;
    const gap = 6.0;
    var covered = 0.0;
    while (covered < total) {
      final segmentEnd = (covered + dash).clamp(0.0, total);
      canvas.drawLine(
        p1 + direction * covered,
        p1 + direction * segmentEnd,
        paint,
      );
      covered += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoutePainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
}
