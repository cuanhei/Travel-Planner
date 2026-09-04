import 'package:flutter/material.dart';

import '../models/day_schedule.dart';
import '../models/trip_stop_location.dart';
import '../models/unscheduled_stop.dart';
import '../models/weather_forecast.dart';
import 'day_forecast_resolver.dart';
import 'day_schedule_service.dart';

/// Weather stage of the itinerary pipeline: takes each day's already-
/// feasible base timeline (from [DayScheduleService], with no weather
/// awareness) and, only for a day whose date actually falls within MET
/// Malaysia's forecast window (see [DayForecastResolver]), tries to keep
/// outdoor/mixed stops out of forecast-bad-weather periods — in this
/// order, matching the cascade [DayScheduleService] already enforces per
/// opening hours:
///
/// 1 & 2. Reorder within the same day / swap with an indoor stop — both
///    realized by re-running [DayScheduleService.scheduleDay] with the
///    day's forecast, since its order search already treats a
///    weather-blocked outdoor stop as infeasible for that ordering,
///    exactly like a closing-time conflict (see that class's doc).
/// 3. Move it to another day with better weather for it — tried here by
///    re-running the target day's schedule with the stop appended, only
///    keeping the move if it actually lands there weather-clean and
///    doesn't bump anything else off that day.
/// 4. Otherwise: the floating pool — appended to its original day's
///    [DaySchedule.unscheduledStops], not deleted.
///
/// Every move re-runs the full day scheduler for whichever day changed,
/// so travel times, arrivals, opening-hours feasibility, visit
/// durations, and the hotel/end-anchor arrival are always recalculated
/// together rather than patched in place.
class WeatherAdjustmentService {
  WeatherAdjustmentService({
    DayForecastResolver? forecastResolver,
    DayScheduleService? scheduleService,
  }) : _forecastResolver = forecastResolver ?? DayForecastResolver(),
       _scheduleService = scheduleService ?? DayScheduleService();

  final DayForecastResolver _forecastResolver;
  final DayScheduleService _scheduleService;

  /// Adjusts [baseSchedules] for forecast weather where possible. Days
  /// outside the forecast window, or whose area's forecast can't be
  /// resolved, pass through unchanged. Returns a full new list in the
  /// same day order as [baseSchedules].
  Future<List<DaySchedule>> adjust({
    required List<DaySchedule> baseSchedules,
    required TimeOfDay dayStart,
    required TimeOfDay dayEnd,
  }) async {
    if (baseSchedules.isEmpty) return baseSchedules;

    final dayByNumber = {
      for (final s in baseSchedules) s.day.dayNumber: s.day,
    };
    final forecastByDay = <int, WeatherForecast?>{};
    for (final day in dayByNumber.values) {
      forecastByDay[day.dayNumber] = await _forecastResolver.resolve(day);
    }

    if (forecastByDay.values.every((f) => f == null)) {
      debugPrint(
        '[WeatherAdjustment] No day within the forecast window — '
        'leaving the base timeline untouched.',
      );
      return baseSchedules;
    }

    final stopsByDay = <int, List<TripStopLocation>>{
      for (final s in baseSchedules)
        s.day.dayNumber: [for (final ss in s.scheduledStops) ss.stop],
    };
    final scheduleByDay = <int, DaySchedule>{
      for (final s in baseSchedules) s.day.dayNumber: s,
    };

    // Stage 1 (steps 1 & 2): weather-aware reschedule, one day in
    // isolation at a time. A stop newly unscheduled here — that wasn't
    // already unscheduled on [baseSchedules] for feasibility reasons —
    // is precisely one this day's own reordering couldn't save from bad
    // weather, so it's queued for stage 2's cross-day attempt.
    final weatherBlocked = <int, List<UnscheduledStop>>{};
    for (final dayNumber in stopsByDay.keys) {
      final forecast = forecastByDay[dayNumber];
      if (forecast == null) continue;

      final baseline = scheduleByDay[dayNumber]!;
      final weatherAware = await _scheduleService.scheduleDay(
        day: dayByNumber[dayNumber]!,
        stops: stopsByDay[dayNumber]!,
        dayStart: dayStart,
        dayEnd: dayEnd,
        forecast: forecast,
      );

      final baselineUnscheduled = baseline.unscheduledStops.toSet();
      final blockedHere = [
        for (final entry in weatherAware.unscheduledStops)
          if (!baselineUnscheduled.contains(entry)) entry,
      ];

      scheduleByDay[dayNumber] = weatherAware;
      if (blockedHere.isNotEmpty) {
        weatherBlocked[dayNumber] = blockedHere;
        debugPrint(
          '[WeatherAdjustment] Day $dayNumber: no in-day order keeps '
          '${blockedHere.map((e) => e.stop.name).join(', ')} out of the '
          'forecast weather — trying another day.',
        );
      }
    }

    // Stage 2 (step 3, else step 4): try every other forecast-covered
    // day for each weather-blocked stop; floating pool if none works.
    for (final fromDay in weatherBlocked.keys.toList()) {
      for (final blocked in weatherBlocked[fromDay]!) {
        final stop = blocked.stop;
        var placed = false;
        for (final dayNumber in stopsByDay.keys) {
          if (dayNumber == fromDay) continue;
          final forecast = forecastByDay[dayNumber];
          if (forecast == null) continue;

          final currentDaySchedule = scheduleByDay[dayNumber]!;
          final trialStops = [...stopsByDay[dayNumber]!, stop];
          final trial = await _scheduleService.scheduleDay(
            day: dayByNumber[dayNumber]!,
            stops: trialStops,
            dayStart: dayStart,
            dayEnd: dayEnd,
            forecast: forecast,
          );

          final landedCleanly = trial.scheduledStops.any(
            (s) => s.stop == stop && !s.hasWeatherConcern,
          );
          final otherCasualties = trial.unscheduledStops
              .where((u) => u.stop != stop)
              .length;
          final noNewCasualties =
              otherCasualties <= currentDaySchedule.unscheduledStops.length;

          if (landedCleanly && noNewCasualties) {
            stopsByDay[dayNumber] = trialStops;
            scheduleByDay[dayNumber] = trial;
            placed = true;
            debugPrint(
              '[WeatherAdjustment] Moved ${stop.name} from Day $fromDay '
              'to Day $dayNumber — better weather there.',
            );
            break;
          }
        }

        if (!placed) {
          final current = scheduleByDay[fromDay]!;
          scheduleByDay[fromDay] = DaySchedule(
            day: current.day,
            scheduledStops: current.scheduledStops,
            unscheduledStops: [
              ...current.unscheduledStops,
              UnscheduledStop(
                stop: stop,
                reason: 'No day has weather suitable for this outdoor stop',
              ),
            ],
            endArrival: current.endArrival,
          );
          debugPrint(
            '[WeatherAdjustment] ${stop.name}: no day has workable '
            'weather for it — moved to Floating Pool / Unscheduled.',
          );
        }
      }
    }

    return [for (final s in baseSchedules) scheduleByDay[s.day.dayNumber]!];
  }
}
