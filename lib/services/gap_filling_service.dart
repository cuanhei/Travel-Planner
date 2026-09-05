import 'package:flutter/material.dart';

import '../models/day_schedule.dart';
import '../models/trip_day.dart';
import '../models/trip_stop_location.dart';
import '../models/unscheduled_stop.dart';
import '../models/weather_forecast.dart';
import 'day_forecast_resolver.dart';
import 'day_schedule_service.dart';

/// Last stage of the itinerary pipeline: after weather adjustment, each
/// day may still have usable leftover time — a gap between two stops
/// (one finished early, or the next didn't open right away), or the
/// stretch after the last stop before heading to the hotel. This tries
/// to work floating-pool stops (from any day — [DaySchedule.unscheduledStops]
/// is pooled trip-wide, not just checked against its own original day)
/// into that leftover time.
///
/// Unlike [DayScheduleService.scheduleDay]'s normal `dayEnd` cutoff, the
/// end anchor here has no fixed arrival deadline — only "before
/// midnight, the next calendar day" (see [DayScheduleService.scheduleFixedOrder]'s
/// `endCutoff`). A trailing gap can legitimately run into the evening
/// as long as the hotel is still reached before then.
///
/// For each candidate, every insertion position in a day's existing stop
/// order is tried (between two stops, or after the last one) by
/// re-running the day's *exact* fixed order with the candidate spliced
/// in — recalculating travel, arrival, opening hours, visit duration,
/// and the hotel arrival together, exactly like a manual "recalculate
/// everything" would. A position is only accepted when the whole
/// resulting day is unequivocally feasible: every originally-scheduled
/// stop stays scheduled, the candidate itself gets scheduled, and the
/// hotel is still reached before midnight. If no position on any day
/// works, the candidate is left in the floating pool — never forced in.
class GapFillingService {
  GapFillingService({
    DayForecastResolver? forecastResolver,
    DayScheduleService? scheduleService,
  }) : _forecastResolver = forecastResolver ?? DayForecastResolver(),
       _scheduleService = scheduleService ?? DayScheduleService();

  final DayForecastResolver _forecastResolver;
  final DayScheduleService _scheduleService;

  Future<List<DaySchedule>> fillGaps({
    required List<DaySchedule> schedules,
    required TimeOfDay dayStart,
  }) async {
    if (schedules.isEmpty) return schedules;

    final pool = <UnscheduledStop>[
      for (final schedule in schedules) ...schedule.unscheduledStops,
    ];
    if (pool.isEmpty) return schedules;

    final dayByNumber = {
      for (final s in schedules) s.day.dayNumber: s.day,
    };
    final scheduleByDay = <int, DaySchedule>{
      for (final s in schedules) s.day.dayNumber: s,
    };
    final placed = <TripStopLocation>{};

    for (final candidate in pool) {
      final stop = candidate.stop;
      for (final dayNumber in dayByNumber.keys) {
        final day = dayByNumber[dayNumber]!;
        final current = scheduleByDay[dayNumber]!;
        final forecast = await _forecastResolver.resolve(day);

        final fitted = await _tryInsert(
          day: day,
          current: current,
          candidate: stop,
          dayStart: dayStart,
          forecast: forecast,
        );
        if (fitted != null) {
          scheduleByDay[dayNumber] = fitted;
          placed.add(stop);
          debugPrint(
            '[GapFilling] Fit "${stop.name}" into Day $dayNumber\'s '
            'schedule.',
          );
          break;
        }
      }
      if (!placed.contains(stop)) {
        debugPrint(
          '[GapFilling] "${stop.name}": no usable gap on any day — '
          'stays unscheduled (${candidate.reason}).',
        );
      }
    }

    return [
      for (final s in schedules)
        _withRemainingUnscheduled(scheduleByDay[s.day.dayNumber]!, placed),
    ];
  }

  /// Tries [candidate] at every position in [current]'s existing stop
  /// order — between two stops, or trailing after the last one — using
  /// midnight (the start of the next calendar day) as the hard cutoff
  /// for reaching [TripDay.endAnchor] instead of the normal `dayEnd`.
  /// Returns the first fully-feasible result, or null if nothing fit.
  Future<DaySchedule?> _tryInsert({
    required TripDay day,
    required DaySchedule current,
    required TripStopLocation candidate,
    required TimeOfDay dayStart,
    WeatherForecast? forecast,
  }) async {
    final existingOrder = [for (final s in current.scheduledStops) s.stop];
    final midnight = DateTime(
      day.date.year,
      day.date.month,
      day.date.day,
    ).add(const Duration(days: 1));

    for (var position = 0; position <= existingOrder.length; position++) {
      final trialOrder = [...existingOrder]..insert(position, candidate);
      final trial = await _scheduleService.scheduleFixedOrder(
        day: day,
        order: trialOrder,
        dayStart: dayStart,
        endCutoff: midnight,
        forecast: forecast,
      );

      final everythingFit = trial.unscheduledStops.isEmpty;
      final hotelBeforeMidnight = trial.endArrival.isBefore(midnight);
      if (everythingFit && hotelBeforeMidnight) {
        return trial;
      }
    }
    return null;
  }

  DaySchedule _withRemainingUnscheduled(
    DaySchedule schedule,
    Set<TripStopLocation> placed,
  ) {
    final remaining = [
      for (final u in schedule.unscheduledStops)
        if (!placed.contains(u.stop)) u,
    ];
    if (remaining.length == schedule.unscheduledStops.length) return schedule;
    return DaySchedule(
      day: schedule.day,
      scheduledStops: schedule.scheduledStops,
      unscheduledStops: remaining,
      endArrival: schedule.endArrival,
    );
  }
}
