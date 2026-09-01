import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/transit_route.dart';
import '../../models/transport_location.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/transit_vehicle_display.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/route_map_view.dart';
import 'transit_navigation_screen.dart';

/// Full step-by-step view of one public-transport route — walk → board →
/// ride → alight → walk → destination — pushed when the traveler taps a
/// route summary card on the Transport screen.
class TransitRouteDetailsScreen extends StatelessWidget {
  const TransitRouteDetailsScreen({
    super.key,
    required this.route,
    required this.departure,
    required this.destination,
  });

  final TransitRoute route;
  final TransportLocation departure;
  final TransportLocation destination;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Route Details',
              subtitle: 'Public transport journey',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  RouteMapView(
                    source: LatLng(departure.latitude, departure.longitude),
                    destination: LatLng(
                      destination.latitude,
                      destination.longitude,
                    ),
                    polylinePoints: route.polylinePoints,
                  ),
                  const SizedBox(height: 16),
                  _SummaryStrip(route: route),
                  const SizedBox(height: 20),
                  for (var i = 0; i < route.steps.length; i++) ...[
                    _StepRow(step: route.steps[i]),
                    const _TimelineArrow(),
                  ],
                  _DestinationRow(name: destination.name),
                ],
              ),
            ),
            _StartNavigationBar(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransitNavigationScreen(
                    route: route,
                    departure: departure,
                    destination: destination,
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

class _StartNavigationBar extends StatelessWidget {
  const _StartNavigationBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation_rounded, color: Colors.white, size: 19),
                  SizedBox(width: 8),
                  Text(
                    'Start Navigation',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.route});

  final TransitRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatItem(
            icon: Icons.schedule_rounded,
            label: formatDuration(route.duration),
          ),
          _StatDivider(),
          _StatItem(
            icon: Icons.social_distance_rounded,
            label: formatDistanceMeters(route.distanceMeters),
          ),
          _StatDivider(),
          _StatItem(
            icon: Icons.sync_alt_rounded,
            label: route.transferCount == 0
                ? 'Direct'
                : '${route.transferCount} transfer${route.transferCount == 1 ? '' : 's'}',
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: context.colors.muted.withValues(alpha: 0.15),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: context.colors.muted),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineArrow extends StatelessWidget {
  const _TimelineArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 16,
              color: context.colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final TransitStep step;

  @override
  Widget build(BuildContext context) {
    if (step.type == TransitStepType.walk) {
      return _StepCard(
        icon: Icons.directions_walk_rounded,
        iconColor: const Color(0xFF6E7A93),
        title: 'Walk ${formatDuration(step.duration)}',
        subtitle: step.instructions,
      );
    }

    final details = step.details;
    if (details == null) {
      return const _StepCard(
        icon: Icons.directions_transit_filled_rounded,
        iconColor: Color(0xFF11998E),
        title: 'Transit',
      );
    }
    final display = TransitVehicleDisplay.of(details.vehicleType);
    final lineLabel = details.lineShortName?.isNotEmpty == true
        ? '${display.label} ${details.lineShortName}'
        : details.lineName;
    final times = [
      formatClockTime(details.departureTime),
      formatClockTime(details.arrivalTime),
    ].where((t) => t.isNotEmpty).join(' → ');

    return _StepCard(
      icon: display.icon,
      iconColor: const Color(0xFF11998E),
      title: lineLabel,
      subtitle: '${details.departureStop} → ${details.arrivalStop}',
      trailingText: times.isEmpty ? null : times,
      footerText: details.headsign != null
          ? 'Towards ${details.headsign}'
          : null,
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.footerText,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final String? footerText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailingText!,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
          if (footerText != null && footerText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Text(
                footerText!,
                style: TextStyle(color: context.colors.muted, fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.location_on_rounded,
            color: AppColors.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
