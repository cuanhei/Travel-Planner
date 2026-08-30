import 'package:flutter/material.dart';

import '../../models/trip_stop_location.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'stop_map_picker.dart';

/// Full-screen wrapper around [StopMapPicker] for callers that want a
/// dedicated "pick some stops, then come back" flow (e.g. Edit Schedule's
/// "add a stop" form). Returns every confirmed [TripStopLocation] via
/// `Navigator.pop` when "Done" is tapped.
class StopSelectionScreen extends StatefulWidget {
  const StopSelectionScreen({super.key, this.initialStops = const []});

  final List<TripStopLocation> initialStops;

  @override
  State<StopSelectionScreen> createState() => _StopSelectionScreenState();
}

class _StopSelectionScreenState extends State<StopSelectionScreen> {
  late final List<TripStopLocation> _stops = List.of(widget.initialStops);

  void _addStop(TripStopLocation stop) {
    if (!_stops.contains(stop)) setState(() => _stops.add(stop));
  }

  void _removeStop(TripStopLocation stop) {
    setState(() => _stops.remove(stop));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Select Stops',
              subtitle: '${_stops.length} stop${_stops.length == 1 ? '' : 's'} added',
              trailing: TextButton(
                onPressed: () => Navigator.of(context).pop(_stops),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StopMapPicker(markedStops: _stops, onAdd: _addStop),
              ),
            ),
            if (_stops.isNotEmpty)
              _AddedStopsBar(stops: _stops, onRemove: _removeStop),
          ],
        ),
      ),
    );
  }
}

class _AddedStopsBar extends StatelessWidget {
  const _AddedStopsBar({required this.stops, required this.onRemove});

  final List<TripStopLocation> stops;
  final ValueChanged<TripStopLocation> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.muted.withValues(alpha: 0.15))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stops.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final stop = stops[i];
          return Container(
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: context.colors.ink),
                const SizedBox(width: 6),
                Text(
                  stop.name,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                IconButton(
                  onPressed: () => onRemove(stop),
                  icon: Icon(Icons.close_rounded, size: 16, color: context.colors.muted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
