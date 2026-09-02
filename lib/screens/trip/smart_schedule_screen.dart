import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../explore/explore_tab.dart' show Place;
import 'optimized_itinerary_screen.dart';

/// UI-only "smart scheduling" progress screen: simulates checking
/// weather, matching transport, and optimizing the route before landing
/// on the generated day-by-day plan.
class SmartScheduleScreen extends StatefulWidget {
  const SmartScheduleScreen({
    super.key,
    required this.places,
    this.tripName = '',
    this.description = '',
    this.recommendedNames = const {},
  });

  final String tripName;
  final String description;
  final List<Place> places;
  final Set<String> recommendedNames;

  @override
  State<SmartScheduleScreen> createState() => _SmartScheduleScreenState();
}

class _SmartScheduleScreenState extends State<SmartScheduleScreen> {
  // A getter (not `static const`) so the step text re-runs tr() on every
  // build and picks up language changes.
  List<String> get _steps => [
    tr('trip_step_weather'),
    tr('trip_step_transport'),
    tr('trip_step_optimizing'),
    tr('trip_step_balancing'),
  ];

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _advance();
  }

  void _advance() {
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_step < _steps.length - 1) {
        setState(() => _step++);
        _advance();
      } else {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OptimizedItineraryScreen(
                tripName: widget.tripName,
                description: widget.description,
                places: widget.places,
                recommendedNames: widget.recommendedNames,
              ),
            ),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.tripName.isEmpty
        ? '${tr('trip_planning_stops_prefix')} ${widget.places.length}-${tr('trip_planning_stops_suffix')}'
        : '${tr('trip_planning_word')} "${widget.tripName}"';

    return Scaffold(
      backgroundColor: context.colors.ink,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _steps[_step],
                    key: ValueKey(_step),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _steps.length,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
