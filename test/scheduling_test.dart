// Unit tests for the pure trip-scheduling engine (lib/utils/scheduling/)
// — see trip_planning_and_stop_scheduling_flow.md for the spec these
// implement. Deliberately pure-Dart-logic tests: no widgets, no
// Supabase/HTTP — every dependency (travel times, weather) is faked so
// these run instantly and never flake on network state.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:travelplanner/models/nearby_place.dart';
import 'package:travelplanner/models/opening_period.dart';
import 'package:travelplanner/models/trip_stop_location.dart';
import 'package:travelplanner/models/weather_forecast.dart';
import 'package:travelplanner/services/google_places_service.dart';
import 'package:travelplanner/services/trip_scheduler_service.dart';
import 'package:travelplanner/utils/scheduling/day_assignment.dart';
import 'package:travelplanner/utils/scheduling/day_ordering.dart';
import 'package:travelplanner/utils/scheduling/meal_planning.dart';
import 'package:travelplanner/utils/scheduling/nearby_recommendation.dart';
import 'package:travelplanner/utils/scheduling/travel_matrix.dart';
import 'package:travelplanner/utils/scheduling/trip_day.dart';
import 'package:travelplanner/utils/scheduling/validation.dart';

/// Fixed-duration travel matrix for deterministic tests — every pair
/// takes [minutes] minutes.
class _FakeTravelMatrix implements TravelMatrixSource {
  _FakeTravelMatrix({this.minutes = 10});

  final int minutes;

  @override
  Future<Duration?> travelTime(
    TripStopLocation from,
    TripStopLocation to,
  ) async {
    return Duration(minutes: minutes);
  }
}

TripStopLocation _stop(
  String name, {
  String category = 'Attraction',
  VisitPurpose? visitPurpose,
  MealType? mealType,
  EnvironmentType? environmentType,
  int? durationMinutes,
  List<OpeningPeriod>? openingPeriods,
  String? businessStatus,
  String? id,
}) {
  return TripStopLocation(
    id: id ?? name,
    name: name,
    address: '$name address',
    latitude: 5.4,
    longitude: 100.3,
    category: category,
    visitPurpose: visitPurpose,
    mealType: mealType,
    environmentType: environmentType,
    estimatedVisitDurationMinutes: durationMinutes,
    openingPeriods: openingPeriods,
    businessStatus: businessStatus,
  );
}

/// Returns [results] from [nearbySearch] without any real HTTP call —
/// [GooglePlacesService.nearbySearch] is a normal instance method (not
/// behind an interface), so overriding it in a test subclass is enough.
/// Throws if called at all when [failIfCalled] is set, to prove a
/// caller short-circuited before ever searching (e.g. not enough
/// remaining time).
class _FakePlacesService extends GooglePlacesService {
  _FakePlacesService(this.results, {this.failIfCalled = false});

  final List<NearbyPlace> results;
  final bool failIfCalled;

  @override
  Future<List<NearbyPlace>> nearbySearch({
    required LatLng center,
    double radiusMeters = 3000,
    Set<String>? includedTypes,
  }) async {
    if (failIfCalled) {
      fail('nearbySearch should not have been called');
    }
    return results;
  }
}

NearbyPlace _nearbyPlace(
  String name, {
  String id = 'nearby-id',
  double? rating,
  String? businessStatus = 'OPERATIONAL',
}) {
  return NearbyPlace(
    id: id,
    name: name,
    address: '$name address',
    latitude: 5.41,
    longitude: 100.31,
    primaryType: 'tourist_attraction',
    photoUrl: null,
    businessStatus: businessStatus,
    editorialSummary: null,
    priceLevel: null,
    priceRangeLabel: null,
    regularOpeningHours: null,
    currentOpeningHours: null,
    openNow: null,
    rating: rating,
    userRatingCount: null,
    regularOpeningPeriods: null,
    currentOpeningPeriods: null,
  );
}

void main() {
  group('buildTripDays', () {
    test(
      'enumerates every date inclusive and applies daily start/end time',
      () {
        final days = buildTripDays(
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 12),
          dailyStartTime: (hour: 9, minute: 0),
          dailyEndTime: (hour: 20, minute: 0),
        );

        expect(days, hasLength(3));
        expect(days[0].date, DateTime(2026, 9, 10));
        expect(days[2].date, DateTime(2026, 9, 12));
        for (final day in days) {
          expect(day.dailyStart.hour, 9);
          expect(day.dailyEnd.hour, 20);
        }
      },
    );

    test('chains accommodation anchors night to night', () {
      final hotelA = _stop('Hotel A', id: 'hotel-a');
      final hotelB = _stop('Hotel B', id: 'hotel-b');
      final tripStart = _stop('Airport', id: 'airport-start');
      final tripEnd = _stop('Airport', id: 'airport-end');

      final days = buildTripDays(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        tripStartLocation: tripStart,
        tripEndLocation: tripEnd,
        accommodationByNight: {
          DateTime(2026, 9, 10): hotelA,
          DateTime(2026, 9, 11): hotelB,
        },
      );

      expect(days, hasLength(3));
      // Day 1 (10th): trip start -> Hotel A (night of the 10th).
      expect(days[0].startAnchor, tripStart);
      expect(days[0].endAnchor, hotelA);
      // Day 2 (11th): Hotel A -> Hotel B (night of the 11th).
      expect(days[1].startAnchor, hotelA);
      expect(days[1].endAnchor, hotelB);
      // Day 3 (12th, last day): Hotel B -> trip end.
      expect(days[2].startAnchor, hotelB);
      expect(days[2].endAnchor, tripEnd);
    });

    test(
      'every anchor stays null with no accommodation and no trip start/end',
      () {
        final days = buildTripDays(
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 10),
        );
        expect(days, hasLength(1));
        expect(days.single.startAnchor, isNull);
        expect(days.single.endAnchor, isNull);
      },
    );

    test('weatherAvailable reflects presence in weatherByDate only', () {
      final forecast = WeatherForecast(
        locationId: 'Tn001',
        locationName: 'George Town',
        date: DateTime(2026, 9, 10),
        morningForecast: 'Tiada Hujan',
        afternoonForecast: 'Tiada Hujan',
        nightForecast: 'Tiada Hujan',
        summaryForecast: 'Tiada Hujan',
        minTemp: 24,
        maxTemp: 32,
      );
      final days = buildTripDays(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 11),
        weatherByDate: {DateTime(2026, 9, 10): forecast},
      );
      expect(days[0].weatherAvailable, isTrue);
      expect(days[1].weatherAvailable, isFalse);
    });
  });

  group('validateStopForDate', () {
    final dailyStart = DateTime(2026, 9, 10, 9, 0);
    final dailyEnd = DateTime(2026, 9, 10, 18, 0);
    final thursday = DateTime(2026, 9, 10); // Google weekday 4

    test('no opening-hours data at all is treated as valid', () {
      final stop = _stop('Mystery Stop');
      expect(
        validateStopForDate(
          stop,
          date: thursday,
          dailyStart: dailyStart,
          dailyEnd: dailyEnd,
        ),
        StopValidationResult.valid,
      );
    });

    test('permanently closed is always invalid regardless of hours', () {
      final stop = _stop(
        'Closed Museum',
        businessStatus: 'CLOSED_PERMANENTLY',
        openingPeriods: [
          const OpeningPeriod(
            openDay: 4,
            openHour: 9,
            openMinute: 0,
            closeDay: 4,
            closeHour: 18,
            closeMinute: 0,
          ),
        ],
      );
      expect(
        validateStopForDate(
          stop,
          date: thursday,
          dailyStart: dailyStart,
          dailyEnd: dailyEnd,
        ),
        StopValidationResult.invalid,
      );
    });

    test('not open on this weekday is invalid', () {
      final stop = _stop(
        'Monday Only Shop',
        openingPeriods: [
          const OpeningPeriod(
            openDay: 1,
            openHour: 9,
            openMinute: 0,
            closeDay: 1,
            closeHour: 18,
            closeMinute: 0,
          ),
        ],
      );
      expect(
        validateStopForDate(
          stop,
          date: thursday,
          dailyStart: dailyStart,
          dailyEnd: dailyEnd,
        ),
        StopValidationResult.invalid,
      );
    });

    test('open period fully containing the daily window is valid', () {
      final stop = _stop(
        'All Day Cafe',
        openingPeriods: [
          const OpeningPeriod(
            openDay: 4,
            openHour: 7,
            openMinute: 0,
            closeDay: 4,
            closeHour: 22,
            closeMinute: 0,
          ),
        ],
      );
      expect(
        validateStopForDate(
          stop,
          date: thursday,
          dailyStart: dailyStart,
          dailyEnd: dailyEnd,
        ),
        StopValidationResult.valid,
      );
    });

    test(
      'open period only partially overlapping is validWithTimeRestriction',
      () {
        final stop = _stop(
          'Evening Bar',
          openingPeriods: [
            const OpeningPeriod(
              openDay: 4,
              openHour: 16,
              openMinute: 0,
              closeDay: 4,
              closeHour: 23,
              closeMinute: 0,
            ),
          ],
        );
        expect(
          validateStopForDate(
            stop,
            date: thursday,
            dailyStart: dailyStart,
            dailyEnd: dailyEnd,
          ),
          StopValidationResult.validWithTimeRestriction,
        );
      },
    );
  });

  group('assignStopsToDays', () {
    test('assigns a schedulable stop to a day', () async {
      final days = buildTripDays(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        dailyStartTime: (hour: 9, minute: 0),
        dailyEndTime: (hour: 18, minute: 0),
      );
      final stop = _stop('Museum', durationMinutes: 90);

      final unscheduled = await assignStopsToDays(
        [stop],
        days,
        travelMatrix: _FakeTravelMatrix(),
      );

      expect(unscheduled, isEmpty);
      expect(days.single.assignedStops, [stop]);
    });

    test('a stop longer than every day is reported unscheduled', () async {
      final days = buildTripDays(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        dailyStartTime: (hour: 9, minute: 0),
        dailyEndTime: (hour: 10, minute: 0), // only 60 minutes available
      );
      final stop = _stop('All-Day Festival', durationMinutes: 600);

      final unscheduled = await assignStopsToDays(
        [stop],
        days,
        travelMatrix: _FakeTravelMatrix(),
      );

      expect(unscheduled, [stop]);
      expect(days.single.assignedStops, isEmpty);
    });

    test('a stop closed the entire trip is reported unscheduled', () async {
      final days = buildTripDays(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 11),
      );
      final stop = _stop(
        'Permanently Shut',
        businessStatus: 'CLOSED_PERMANENTLY',
      );

      final unscheduled = await assignStopsToDays(
        [stop],
        days,
        travelMatrix: _FakeTravelMatrix(),
      );

      expect(unscheduled, [stop]);
    });
  });

  group('orderDay', () {
    test(
      'orders stops and simulates arrival/departure with travel time',
      () async {
        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 9, 0),
          dailyEnd: DateTime(2026, 9, 10, 18, 0),
          assignedStops: [
            _stop('B', id: 'b', durationMinutes: 30),
            _stop('A', id: 'a', durationMinutes: 60),
          ],
        );

        final result = await orderDay(
          day,
          travelMatrix: _FakeTravelMatrix(minutes: 15),
        );

        expect(result.unfitStops, isEmpty);
        expect(result.visits, hasLength(2));
        final first = result.visits.first;
        expect(first.arrival, day.dailyStart); // no anchor -> starts fresh
        expect(first.travelFromPrevious, Duration.zero);
        final second = result.visits[1];
        expect(second.arrival, first.visitEnd.add(const Duration(minutes: 15)));
      },
    );

    test("accounts for travel time from the previous night's hotel "
        '(startAnchor) to the first stop of the day', () async {
      final hotel = _stop('Hotel', id: 'hotel');
      final day = TripDay(
        date: DateTime(2026, 9, 11),
        dailyStart: DateTime(2026, 9, 11, 9, 0),
        dailyEnd: DateTime(2026, 9, 11, 18, 0),
        startAnchor: hotel,
        assignedStops: [_stop('First Stop', id: 'first', durationMinutes: 60)],
      );

      final result = await orderDay(
        day,
        travelMatrix: _FakeTravelMatrix(minutes: 25),
      );

      expect(result.unfitStops, isEmpty);
      expect(result.visits, hasLength(1));
      expect(
        result.visits.first.travelFromPrevious,
        const Duration(minutes: 25),
      );
      expect(
        result.visits.first.arrival,
        day.dailyStart.add(const Duration(minutes: 25)),
      );
    });

    test('a stop that would finish after dailyEnd is left unfit', () async {
      final day = TripDay(
        date: DateTime(2026, 9, 10),
        dailyStart: DateTime(2026, 9, 10, 17, 0),
        dailyEnd: DateTime(2026, 9, 10, 18, 0),
        assignedStops: [_stop('Too Long', durationMinutes: 120)],
      );

      final result = await orderDay(day, travelMatrix: _FakeTravelMatrix());

      expect(result.visits, isEmpty);
      expect(result.unfitStops, hasLength(1));
    });

    test(
      'cuts the last stop if there is no time to reach the end anchor',
      () async {
        final hotel = _stop('Hotel', id: 'hotel');
        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 17, 0),
          dailyEnd: DateTime(2026, 9, 10, 18, 0),
          endAnchor: hotel,
          assignedStops: [_stop('Last Stop', durationMinutes: 30)],
        );

        // 30-minute travel back to the hotel doesn't fit after a
        // 30-minute visit starting at 17:00 within a window that ends at
        // 18:00 (17:00 visit + 30min = 17:30 finish, +30min travel =
        // 18:00 exactly — still fits) so use a longer travel time back to
        // force the cut.
        final result = await orderDay(
          day,
          travelMatrix: _FakeTravelMatrix(minutes: 45),
        );

        expect(result.visits, isEmpty);
        expect(result.unfitStops, hasLength(1));
      },
    );

    test(
      'outdoor stop is ordered into the good-weather morning, indoor into the bad-weather afternoon',
      () async {
        final forecast = WeatherForecast(
          locationId: 'Tn001',
          locationName: 'George Town',
          date: DateTime(2026, 9, 10),
          morningForecast: 'Tiada Hujan',
          afternoonForecast: 'Ribut Petir',
          nightForecast: 'Tiada Hujan',
          summaryForecast: 'Ribut Petir',
          minTemp: 24,
          maxTemp: 32,
        );
        final museum = _stop(
          'Museum',
          id: 'museum',
          environmentType: EnvironmentType.indoor,
          durationMinutes: 60,
        );
        // 3 hours, so visiting it first (9:00-12:00) pushes whatever's
        // scheduled next into the afternoon forecast period.
        final park = _stop(
          'Park',
          id: 'park',
          environmentType: EnvironmentType.outdoor,
          durationMinutes: 180,
        );

        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 9, 0),
          dailyEnd: DateTime(2026, 9, 10, 18, 0),
          weatherAvailable: true,
          weatherForecast: forecast,
          // Indoor listed first: with no weather scoring, both stops
          // tie on every other term (equal travel time, no opening-hour
          // or meal constraints), so a tied score keeps list order —
          // an outdoor-first result below can only come from the
          // weather-time penalty actually breaking that tie.
          assignedStops: [museum, park],
        );

        final result = await orderDay(
          day,
          travelMatrix: _FakeTravelMatrix(minutes: 15),
        );

        expect(result.unfitStops, isEmpty);
        expect(result.visits, hasLength(2));
        expect(result.visits[0].stop, park);
        expect(result.visits[0].visitStart.hour, lessThan(12));
        expect(result.visits[1].stop, museum);
        expect(result.visits[1].visitStart.hour, greaterThanOrEqualTo(12));
      },
    );
  });

  group('findScheduleGaps / findGapRecommendations', () {
    TripDay dayEndingAt18({TripStopLocation? startAnchor}) => TripDay(
      date: DateTime(2026, 9, 10),
      dailyStart: DateTime(2026, 9, 10, 9, 0),
      dailyEnd: DateTime(2026, 9, 10, 18, 0),
      startAnchor: startAnchor,
    );

    DayOrderingResult orderingEndingAt(
      DateTime lastVisitEnd,
      TripStopLocation lastStop,
    ) => DayOrderingResult(
      visits: [
        ScheduledVisit(
          stop: lastStop,
          arrival: lastVisitEnd.subtract(const Duration(hours: 1)),
          visitStart: lastVisitEnd.subtract(const Duration(hours: 1)),
          visitEnd: lastVisitEnd,
          travelFromPrevious: Duration.zero,
        ),
      ],
      unfitStops: const [],
      finishTime: lastVisitEnd,
    );

    test(
      'returns a nearby candidate scored from the real travel time and visit-time simulation',
      () async {
        final lastStop = _stop('KLCC', id: 'klcc');
        final lastVisitEnd = DateTime(2026, 9, 10, 11, 0);

        final results = await findGapRecommendations(
          day: dayEndingAt18(),
          ordering: orderingEndingAt(lastVisitEnd, lastStop),
          alreadyOnTrip: const {},
          travelMatrix: _FakeTravelMatrix(minutes: 15),
          placesService: _FakePlacesService([
            _nearbyPlace('Aquaria KLCC', rating: 4.5),
          ]),
        );

        expect(results, hasLength(1));
        expect(results.single.gap.to, isNull); // the tail gap
        final candidate = results.single.candidates.single;
        expect(candidate.visit.stop.name, 'Aquaria KLCC');
        expect(
          candidate.visit.arrival,
          lastVisitEnd.add(const Duration(minutes: 15)),
        );
      },
    );

    test(
      'skips the search entirely when not enough time remains (spec §37)',
      () async {
        final lastStop = _stop('KLCC', id: 'klcc');
        // Only 30 minutes left before dailyEnd — below the default
        // 90-minute minimum.
        final lastVisitEnd = DateTime(2026, 9, 10, 17, 30);

        final results = await findGapRecommendations(
          day: dayEndingAt18(),
          ordering: orderingEndingAt(lastVisitEnd, lastStop),
          alreadyOnTrip: const {},
          travelMatrix: _FakeTravelMatrix(minutes: 15),
          // Fails the test outright if the implementation ever calls
          // nearbySearch here — proves the time check short-circuits
          // before spending an API call.
          placesService: _FakePlacesService(const [], failIfCalled: true),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'excludes a candidate already on the trip (spec §40 dedupe)',
      () async {
        final lastStop = _stop('KLCC', id: 'klcc');
        final lastVisitEnd = DateTime(2026, 9, 10, 11, 0);

        // The Google Place ID remains stable even if coordinates change.
        final duplicate = TripStopLocation(
          id: 'already-there',
          placeId: 'nearby-id',
          name: 'Aquaria KLCC',
          address: 'x',
          latitude: 5.41,
          longitude: 100.31,
        );

        final results = await findGapRecommendations(
          day: dayEndingAt18(),
          ordering: orderingEndingAt(lastVisitEnd, lastStop),
          alreadyOnTrip: {duplicate},
          travelMatrix: _FakeTravelMatrix(minutes: 15),
          placesService: _FakePlacesService([_nearbyPlace('Aquaria KLCC')]),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'finds a whole-day gap (and recommends into it) on a day with nothing scheduled yet',
      () async {
        final hotel = _stop('Hotel', id: 'hotel');
        final day = dayEndingAt18(startAnchor: hotel);
        final ordering = DayOrderingResult(
          visits: const [],
          unfitStops: const [],
          finishTime: day.dailyStart,
        );

        final gaps = findScheduleGaps(day: day, ordering: ordering);
        expect(gaps, hasLength(1));
        expect(gaps.single.from, hotel);
        expect(gaps.single.duration, const Duration(hours: 9));

        final results = await findGapRecommendations(
          day: day,
          ordering: ordering,
          alreadyOnTrip: const {},
          travelMatrix: _FakeTravelMatrix(minutes: 15),
          placesService: _FakePlacesService([_nearbyPlace('Aquaria KLCC')]),
        );

        expect(results, hasLength(1));
        expect(results.single.candidates, isNotEmpty);
      },
    );

    test('finds a gap between two already-scheduled visits and respects the '
        "second visit's original arrival time as the deadline", () async {
      final first = _stop('Morning Stop', id: 'first');
      final second = _stop('Evening Stop', id: 'second');
      final day = dayEndingAt18();

      final firstVisit = ScheduledVisit(
        stop: first,
        arrival: DateTime(2026, 9, 10, 9, 0),
        visitStart: DateTime(2026, 9, 10, 9, 0),
        visitEnd: DateTime(2026, 9, 10, 10, 0),
        travelFromPrevious: Duration.zero,
      );
      final secondVisit = ScheduledVisit(
        stop: second,
        // A big gap before it (second visit doesn't start until 3pm),
        // but ending only 15 min before dailyEnd (18:00) so the *tail*
        // gap stays below the 90-minute threshold — isolates the
        // between-visits gap as the only one found.
        arrival: DateTime(2026, 9, 10, 15, 0),
        visitStart: DateTime(2026, 9, 10, 15, 0),
        visitEnd: DateTime(2026, 9, 10, 17, 45),
        travelFromPrevious: const Duration(minutes: 15),
      );
      final ordering = DayOrderingResult(
        visits: [firstVisit, secondVisit],
        unfitStops: const [],
        finishTime: secondVisit.visitEnd,
      );

      final gaps = findScheduleGaps(day: day, ordering: ordering);
      expect(gaps, hasLength(1));
      expect(gaps.single.from, first);
      expect(gaps.single.to, second);
      expect(gaps.single.availableFrom, firstVisit.visitEnd);
      expect(gaps.single.availableUntil, secondVisit.visitStart);

      final results = await findGapRecommendations(
        day: day,
        ordering: ordering,
        alreadyOnTrip: const {},
        travelMatrix: _FakeTravelMatrix(minutes: 20),
        placesService: _FakePlacesService([_nearbyPlace('Midday Cafe')]),
      );

      expect(results, hasLength(1));
      final candidate = results.single.candidates.single;
      // Arrives 20 min after leaving the first stop, and must finish
      // with enough time (another 20 min) to reach the second stop by
      // its original 3pm arrival — well within the ~4h gap.
      expect(
        candidate.visit.arrival,
        firstVisit.visitEnd.add(const Duration(minutes: 20)),
      );
    });
  });

  group('planMissingMeals', () {
    test(
      'plans breakfast, lunch, and dinner from a shared reference anchor',
      () async {
        final hotel = _stop('Hotel', id: 'hotel');
        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 7, 0),
          dailyEnd: DateTime(2026, 9, 10, 22, 0),
          startAnchor: hotel,
          endAnchor: hotel,
        );
        final ordering = DayOrderingResult(
          visits: const [],
          unfitStops: const [],
          finishTime: day.dailyStart,
        );

        final meals = await planMissingMeals(
          day: day,
          ordering: ordering,
          travelMatrix: _FakeTravelMatrix(minutes: 5),
          placesService: _FakePlacesService([
            _nearbyPlace('Restaurant', id: 'r1'),
          ]),
        );

        expect(meals, hasLength(3));
        expect(meals.map((m) => m.mealType).toSet(), {
          MealType.breakfast,
          MealType.lunch,
          MealType.dinner,
        });
        for (final meal in meals) {
          expect(meal.visitPurpose, VisitPurpose.meal);
        }
      },
    );

    test(
      "does not plan a meal the traveler already selected themselves (spec §6)",
      () async {
        final hotel = _stop('Hotel', id: 'hotel');
        final userLunch = _stop(
          'User Picked Lunch',
          id: 'user-lunch',
          visitPurpose: VisitPurpose.meal,
          mealType: MealType.lunch,
        );
        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 7, 0),
          dailyEnd: DateTime(2026, 9, 10, 22, 0),
          startAnchor: hotel,
          assignedStops: [userLunch],
        );
        final lunchVisit = ScheduledVisit(
          stop: userLunch,
          arrival: DateTime(2026, 9, 10, 12, 0),
          visitStart: DateTime(2026, 9, 10, 12, 0),
          visitEnd: DateTime(2026, 9, 10, 13, 0),
          travelFromPrevious: Duration.zero,
        );
        final ordering = DayOrderingResult(
          visits: [lunchVisit],
          unfitStops: const [],
          finishTime: lunchVisit.visitEnd,
        );

        final meals = await planMissingMeals(
          day: day,
          ordering: ordering,
          travelMatrix: _FakeTravelMatrix(minutes: 5),
          placesService: _FakePlacesService([
            _nearbyPlace('Restaurant', id: 'r1'),
          ]),
        );

        expect(meals.map((m) => m.mealType).toSet(), {
          MealType.breakfast,
          MealType.dinner,
        });
      },
    );

    test(
      "skips a meal whose allowed window doesn't overlap the daily window",
      () async {
        final hotel = _stop('Hotel', id: 'hotel');
        // 9:00-15:00 doesn't overlap dinner's 18:00-21:00 allowed window
        // at all.
        final day = TripDay(
          date: DateTime(2026, 9, 10),
          dailyStart: DateTime(2026, 9, 10, 9, 0),
          dailyEnd: DateTime(2026, 9, 10, 15, 0),
          startAnchor: hotel,
        );
        final ordering = DayOrderingResult(
          visits: const [],
          unfitStops: const [],
          finishTime: day.dailyStart,
        );

        final meals = await planMissingMeals(
          day: day,
          ordering: ordering,
          travelMatrix: _FakeTravelMatrix(minutes: 5),
          placesService: _FakePlacesService([
            _nearbyPlace('Restaurant', id: 'r1'),
          ]),
        );

        expect(meals.map((m) => m.mealType), isNot(contains(MealType.dinner)));
      },
    );
  });

  group('explainUnscheduled', () {
    final days = buildTripDays(
      startDate: DateTime(2026, 9, 10),
      endDate: DateTime(2026, 9, 10),
      dailyStartTime: (hour: 9, minute: 0),
      dailyEndTime: (hour: 18, minute: 0),
    ); // Thursday, Google weekday 4, 9 hours available.

    test('names a stop closed on every day of the trip', () {
      final stop = _stop(
        'Monday Only Shop',
        openingPeriods: [
          const OpeningPeriod(
            openDay: 1,
            openHour: 9,
            openMinute: 0,
            closeDay: 1,
            closeHour: 18,
            closeMinute: 0,
          ),
        ],
      );

      expect(explainUnscheduled(stop, days), contains('closed on every day'));
    });

    test('names a stop whose visit duration exceeds every day', () {
      final stop = _stop('All-Day Festival', durationMinutes: 600);

      expect(
        explainUnscheduled(stop, days),
        contains('longer than any single'),
      );
    });

    test('falls back to a generic reason otherwise', () {
      final stop = _stop('Ordinary Attraction', durationMinutes: 60);

      expect(explainUnscheduled(stop, days), contains("Couldn't fit"));
    });
  });
}
