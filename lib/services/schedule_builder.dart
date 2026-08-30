import 'package:flutter/material.dart' show IconData, Icons, TimeOfDay;
import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'route_optimizer.dart';

const Distance _distance = Distance();

/// Typical time spent at a stop, by category — used to space out a day's
/// schedule. Not measured, just a reasonable default per category.
const _visitMinutes = {
  'Hotel': 0,
  'Food': 60,
  'Shopping': 75,
  'Attraction': 90,
  'Nature': 90,
  'Beach': 120,
  'Culture': 75,
  'Transport': 15,
  'Health': 30,
  'Finance': 15,
  'Other': 45,
};

int visitMinutesFor(String category) => _visitMinutes[category] ?? 45;

/// A travel hop between two points on the schedule — either from the
/// day's hotel to its first stop, between two stops, or from the last
/// stop back to the hotel.
class TravelLeg {
  const TravelLeg({
    required this.mode,
    required this.icon,
    required this.durationMinutes,
    required this.distanceKm,
  });

  final String mode;
  final IconData icon;
  final int durationMinutes;
  final double distanceKm;
}

/// [TravelLeg] estimated from straight-line [distanceKm] — walking pace
/// under 1 km, e-hailing/bus at typical city speeds beyond that. A rough
/// estimate, not a routed travel time (there's no directions API here).
TravelLeg estimateTravelLeg(double distanceKm) {
  if (distanceKm < 1) {
    return TravelLeg(
      mode: 'Walk',
      icon: Icons.directions_walk_rounded,
      durationMinutes: (distanceKm * 15).round().clamp(5, 60),
      distanceKm: distanceKm,
    );
  }
  if (distanceKm < 8) {
    return TravelLeg(
      mode: 'E-hailing / Bus',
      icon: Icons.directions_bus_filled_rounded,
      durationMinutes: (distanceKm * 3).round().clamp(10, 60),
      distanceKm: distanceKm,
    );
  }
  return TravelLeg(
    mode: 'E-hailing (Grab)',
    icon: Icons.local_taxi_rounded,
    durationMinutes: (distanceKm * 2).round().clamp(15, 180),
    distanceKm: distanceKm,
  );
}

TimeOfDay addMinutes(TimeOfDay time, int minutes) {
  final total = (time.hour * 60 + time.minute + minutes) % (24 * 60);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// One stop with the time the traveler is scheduled to arrive and leave,
/// and the estimated travel leg that got them there.
class ScheduledStop {
  const ScheduledStop({
    required this.stop,
    required this.arrival,
    required this.departure,
    required this.travelFromPrevious,
  });

  final TripStopLocation stop;
  final TimeOfDay arrival;
  final TimeOfDay departure;

  /// Null only for the very first stop of a day with no hotel to start
  /// from (the no-hotel fallback case).
  final TravelLeg? travelFromPrevious;
}

/// A single day's schedule: depart the hotel at [startTime], visit each
/// stop in order (with estimated travel + visit time), and — if there's a
/// hotel to return to — arrive back at [endTime].
class DaySchedule {
  const DaySchedule({
    required this.day,
    required this.hotel,
    required this.stops,
    required this.startTime,
    required this.endTime,
    required this.returnLeg,
  });

  final int day;
  final TripStopLocation? hotel;
  final List<ScheduledStop> stops;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  /// The trip back to [hotel] after the last stop — null if there's no
  /// hotel, or the day has no stops to return from.
  final TravelLeg? returnLeg;
}

/// Turns a [DayPlan] (already geographically ordered — see [planDays])
/// into a real clock schedule: departing [startTime], with estimated
/// travel time between each stop layered on top of typical visit
/// durations per category.
DaySchedule buildDaySchedule({required DayPlan plan, required TimeOfDay startTime}) {
  final scheduled = <ScheduledStop>[];
  var clock = startTime;
  LatLng? currentPoint = plan.hotel != null
      ? LatLng(plan.hotel!.latitude, plan.hotel!.longitude)
      : null;

  for (final stop in plan.stops) {
    final stopPoint = LatLng(stop.latitude, stop.longitude);
    TravelLeg? leg;
    if (currentPoint != null) {
      final km = _distance(currentPoint, stopPoint) / 1000;
      leg = estimateTravelLeg(km);
      clock = addMinutes(clock, leg.durationMinutes);
    }
    final arrival = clock;
    final departure = addMinutes(arrival, visitMinutesFor(stop.category));
    scheduled.add(
      ScheduledStop(stop: stop, arrival: arrival, departure: departure, travelFromPrevious: leg),
    );
    clock = departure;
    currentPoint = stopPoint;
  }

  TravelLeg? returnLeg;
  var endTime = clock;
  if (plan.hotel != null && currentPoint != null) {
    final hotelPoint = LatLng(plan.hotel!.latitude, plan.hotel!.longitude);
    final km = _distance(currentPoint, hotelPoint) / 1000;
    returnLeg = estimateTravelLeg(km);
    endTime = addMinutes(clock, returnLeg.durationMinutes);
  }

  return DaySchedule(
    day: plan.day,
    hotel: plan.hotel,
    stops: scheduled,
    startTime: startTime,
    endTime: endTime,
    returnLeg: returnLeg,
  );
}
