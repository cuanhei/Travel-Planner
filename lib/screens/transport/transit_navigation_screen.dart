import 'package:flutter/material.dart';

import '../../models/transit_route.dart';
import '../../models/transport_location.dart';
import '../../services/transit_navigation_controller.dart';
import '../../utils/format.dart';
import '../../utils/transit_vehicle_display.dart';
import '../../widgets/navigation_map_view.dart';

/// Full-screen, live public-transport navigation for one already-picked
/// [TransitRoute] — walks its WALK/TRANSIT steps in order, following the
/// traveler's GPS via [TransitNavigationController]. Pushed from
/// [TransitRouteDetailsScreen]'s "Start Navigation" button; does not
/// request a new route or touch the Transport search underneath it.
class TransitNavigationScreen extends StatefulWidget {
  const TransitNavigationScreen({
    super.key,
    required this.route,
    required this.departure,
    required this.destination,
  });

  final TransitRoute route;
  final TransportLocation departure;
  final TransportLocation destination;

  @override
  State<TransitNavigationScreen> createState() =>
      _TransitNavigationScreenState();
}

class _TransitNavigationScreenState extends State<TransitNavigationScreen> {
  late final _controller = TransitNavigationController(
    route: widget.route,
    departure: widget.departure,
    destination: widget.destination,
  );

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _endNavigation() {
    _controller.stop();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller.stop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1D3A),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_controller.status) {
      case NavigationStatus.idle:
      case NavigationStatus.starting:
        return _LoadingState(onClose: _endNavigation);
      case NavigationStatus.error:
        return _ErrorState(
          message: _controller.error ?? 'Navigation could not start.',
          onClose: _endNavigation,
        );
      case NavigationStatus.arrived:
        return _ArrivedState(onEnd: _endNavigation);
      case NavigationStatus.walking:
        return _WalkingNavigation(controller: _controller, onClose: _endNavigation);
      case NavigationStatus.transit:
      case NavigationStatus.approachingAlight:
        return _TransitNavigation(controller: _controller, onClose: _endNavigation);
    }
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CloseBar(onClose: onClose),
        const Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Getting your location…',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CloseBar(onClose: onClose),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: Colors.white70,
                    size: 36,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrivedState extends StatelessWidget {
  const _ArrivedState({required this.onEnd});

  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFF11998E),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 18),
          const Text(
            'You have arrived',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onEnd,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0B1D3A),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'End Navigation',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkingNavigation extends StatelessWidget {
  const _WalkingNavigation({required this.controller, required this.onClose});

  final TransitNavigationController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep;
    final remaining = controller.remainingDistanceMeters;

    return Column(
      children: [
        _InstructionBar(
          onClose: onClose,
          child: Row(
            children: [
              const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.instructions ?? 'Continue toward your stop',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        formatDistanceMeters(remaining.round()),
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: NavigationMapView(
            userPosition: controller.currentUserPosition,
            targetPosition: controller.walkTargetPosition,
            polylinePoints: controller.currentStepPolyline,
            polylineColor: const Color(0xFF11998E),
          ),
        ),
        _BottomBar(
          child: Row(
            children: [
              const Icon(
                Icons.directions_walk_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Walk to ${controller.walkTargetLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        formatDuration(step.duration),
                        if (remaining != null) formatDistanceMeters(remaining.round()),
                      ].join(' • '),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (controller.isRerouting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransitNavigation extends StatelessWidget {
  const _TransitNavigation({required this.controller, required this.onClose});

  final TransitNavigationController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep;
    final details = step.details;
    final display = TransitVehicleDisplay.of(
      details?.vehicleType ?? TransitVehicleType.other,
    );
    final lineLabel = details == null
        ? 'Transit'
        : (details.lineShortName?.isNotEmpty == true
            ? '${display.label} ${details.lineShortName}'
            : details.lineName);
    final gettingReady = controller.status == NavigationStatus.approachingAlight &&
        !controller.showAlightBanner;

    return Column(
      children: [
        _InstructionBar(
          onClose: onClose,
          child: controller.showAlightBanner
              ? const _AlightNowRow()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(display.icon, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lineLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Get off: ${details?.arrivalStop ?? '—'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                    if (gettingReady) ...[
                      const SizedBox(height: 8),
                      const _WarningChip(text: 'Get ready to get off'),
                    ],
                  ],
                ),
        ),
        Expanded(
          child: NavigationMapView(
            userPosition: controller.currentUserPosition,
            targetPosition: details?.arrivalStopLocation,
            polylinePoints: step.polylinePoints,
            polylineColor: const Color(0xFF5C6BC0),
          ),
        ),
        _BottomBar(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.stopsRemaining != null
                    ? '${controller.stopsRemaining} stop${controller.stopsRemaining == 1 ? '' : 's'} remaining'
                    : 'Riding $lineLabel',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                details?.headsign != null
                    ? 'Towards ${details!.headsign} · Board at ${details.departureStop}'
                    : 'Board at ${details?.departureStop ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlightNowRow extends StatelessWidget {
  const _AlightNowRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.directions_walk_rounded, color: Colors.white, size: 24),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Get off here',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB347).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB347), size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFFFB347),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top bar wrapping walking/transit instructions — always carries the
/// close button so navigation can be ended manually at any time.
class _InstructionBar extends StatelessWidget {
  const _InstructionBar({required this.onClose, required this.child});

  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      color: const Color(0xFF0B1D3A),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CloseBar extends StatelessWidget {
  const _CloseBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded, color: Colors.white70),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      color: const Color(0xFF0B1D3A),
      child: child,
    );
  }
}
