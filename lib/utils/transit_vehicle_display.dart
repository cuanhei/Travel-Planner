import 'package:flutter/material.dart';

import '../models/transit_route.dart';

/// Icon + short label for a transit vehicle type, shared by the route
/// summary cards and the full route-details view so both render the
/// same "🚌 Bus" / "🚆 LRT" style chips.
class TransitVehicleDisplay {
  const TransitVehicleDisplay(this.icon, this.label);

  final IconData icon;
  final String label;

  static TransitVehicleDisplay of(TransitVehicleType type) {
    switch (type) {
      case TransitVehicleType.bus:
        return const TransitVehicleDisplay(
          Icons.directions_bus_filled_rounded,
          'Bus',
        );
      case TransitVehicleType.subway:
        return const TransitVehicleDisplay(Icons.subway_rounded, 'MRT');
      case TransitVehicleType.lightRail:
        return const TransitVehicleDisplay(
          Icons.directions_railway_filled_rounded,
          'LRT',
        );
      case TransitVehicleType.rail:
        return const TransitVehicleDisplay(Icons.train_rounded, 'Train');
      case TransitVehicleType.tram:
        return const TransitVehicleDisplay(Icons.tram_rounded, 'Tram');
      case TransitVehicleType.ferry:
        return const TransitVehicleDisplay(
          Icons.directions_boat_filled_rounded,
          'Ferry',
        );
      case TransitVehicleType.other:
        return const TransitVehicleDisplay(
          Icons.directions_transit_filled_rounded,
          'Transit',
        );
    }
  }
}
