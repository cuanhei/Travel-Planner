import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:travelplanner/models/nearby_place.dart';
import 'package:travelplanner/models/opening_period.dart';
import 'package:travelplanner/models/trip.dart';
import 'package:travelplanner/models/trip_draft.dart';
import 'package:travelplanner/models/trip_stop_location.dart';
import 'package:travelplanner/services/google_places_service.dart';
import 'package:travelplanner/services/trip_planning_service.dart';
import 'package:travelplanner/services/trip_scheduler_service.dart';
import 'package:travelplanner/services/trip_service.dart';
import 'package:travelplanner/services/weather_service.dart';
import 'package:travelplanner/utils/scheduling/day_ordering.dart';
import 'package:travelplanner/utils/scheduling/nearby_recommendation.dart';
import 'package:travelplanner/utils/scheduling/place_identity.dart';
import 'package:travelplanner/utils/scheduling/recommendation_requests.dart';
import 'package:travelplanner/utils/scheduling/schedule_insertion.dart';
import 'package:travelplanner/utils/scheduling/travel_matrix.dart';
import 'package:travelplanner/utils/scheduling/trip_day.dart';

DateTime at(int hour, [int minute = 0]) => DateTime(2026, 9, 10, hour, minute);
TripStopLocation stop(
  String name, {
  int minutes = 60,
  String? placeId,
  MealType? meal,
  List<OpeningPeriod>? hours,
}) => TripStopLocation(
  id: name,
  name: name,
  address: name,
  latitude: 5.4,
  longitude: 100.3,
  placeId: placeId,
  category: meal == null ? 'Attraction' : 'Food',
  visitPurpose: meal == null ? VisitPurpose.attraction : VisitPurpose.meal,
  mealType: meal,
  estimatedVisitDurationMinutes: minutes,
  openingPeriods: hours,
);
TripDay day({
  TripStopLocation? start,
  TripStopLocation? end,
  int endHour = 18,
  List<TripStopLocation> stops = const [],
}) => TripDay(
  date: at(0),
  dailyStart: at(9),
  dailyEnd: at(endHour),
  startAnchor: start,
  endAnchor: end,
  assignedStops: stops.toList(),
);
NearbyPlace nearby(
  String id, {
  String type = 'tourist_attraction',
  double latitude = 5.41,
}) => NearbyPlace.fromJson(
  {
    'id': id,
    'displayName': {'text': id},
    'formattedAddress': id,
    'location': {'latitude': latitude, 'longitude': 100.31},
    'primaryType': type,
    'businessStatus': 'OPERATIONAL',
    'rating': 4.5,
  },
  apiKey: 'test',
  photoMaxWidthPx: 100,
);

class Matrix implements TravelMatrixSource {
  Matrix([this.resolve]);
  final Duration? Function(TripStopLocation, TripStopLocation)? resolve;
  final List<(TripStopLocation, TripStopLocation)> calls = [];
  @override
  Future<Duration?> travelTime(
    TripStopLocation from,
    TripStopLocation to,
  ) async {
    calls.add((from, to));
    return resolve == null ? const Duration(minutes: 10) : resolve!(from, to);
  }
}

class Places extends GooglePlacesService {
  Places(this.results, {this.failSearch = false});
  final List<NearbyPlace> results;
  final bool failSearch;
  int calls = 0;
  @override
  Future<List<NearbyPlace>> nearbySearch({
    required LatLng center,
    double radiusMeters = 3000,
    Set<String>? includedTypes,
  }) async {
    calls++;
    if (failSearch) throw StateError('offline');
    return results;
  }
}

class NoWeather extends WeatherService {
  @override
  Future<ResolvedWeatherWindow> getForecastWindowForPosition(
    LatLng position,
  ) async =>
      const ResolvedWeatherWindow(forecasts: [], areaLabel: 'Unavailable');
}

Future<List<GapRecommendations>> recommendations(
  TripDay d,
  Matrix matrix,
  List<NearbyPlace> candidates, {
  Set<TripStopLocation> excluded = const {},
}) async => findGapRecommendations(
  day: d,
  ordering: await orderDay(d, travelMatrix: matrix),
  alreadyOnTrip: excluded,
  travelMatrix: matrix,
  placesService: Places(candidates),
);

void main() {
  test(
    'duplicate loads are skipped and stale responses cannot finish a newer load',
    () {
      final requests = RecommendationRequests<String>();
      final oldTicket = requests.begin('day-2')!;
      expect(requests.begin('day-2'), isNull);
      requests.invalidate();
      final newTicket = requests.begin('day-2')!;
      expect(requests.complete('day-2', oldTicket), isFalse);
      expect(requests.begin('day-2'), isNull);
      expect(requests.complete('day-2', newTicket), isTrue);
      expect(requests.begin('day-2'), isNotNull);
    },
  );
  group('required travel and gap feasibility', () {
    test(
      'empty and tail gaps reject a late return to the final anchor',
      () async {
        final hotel = stop('hotel');
        final matrix = Matrix(
          (from, to) => Duration(minutes: to == hotel ? 80 : 10),
        );
        expect(
          await recommendations(
            day(start: hotel, end: hotel, endHour: 11),
            matrix,
            [nearby('museum')],
          ),
          isEmpty,
        );
        expect(
          await recommendations(
            day(
              start: hotel,
              end: hotel,
              endHour: 12,
              stops: [stop('existing')],
            ),
            matrix,
            [nearby('museum')],
          ),
          isEmpty,
        );
      },
    );
    test(
      'unknown required return route rejects recommendations and visits',
      () async {
        final hotel = stop('hotel');
        final matrix = Matrix(
          (from, to) => to == hotel ? null : const Duration(minutes: 10),
        );
        expect(
          await recommendations(day(start: hotel, end: hotel), matrix, [
            nearby('museum'),
          ]),
          isEmpty,
        );
        final result = await orderDay(
          day(start: hotel, end: hotel, stops: [stop('first'), stop('second')]),
          travelMatrix: matrix,
        );
        expect(result.visits, isEmpty);
        expect(result.unfitStops, hasLength(2));
        expect(result.endAnchorReachable, isFalse);
      },
    );
    test('end-anchor trimming rechecks more than one stop', () async {
      final hotel = stop('hotel');
      final matrix = Matrix(
        (from, to) => Duration(minutes: to == hotel ? 600 : 10),
      );
      final result = await orderDay(
        day(
          start: hotel,
          end: hotel,
          stops: [stop('one'), stop('two'), stop('three')],
        ),
        travelMatrix: matrix,
      );
      expect(result.visits, isEmpty);
      expect(result.unfitStops, hasLength(3));
    });
    test(
      'real optimizer output exposes leading and internal waiting gaps',
      () async {
        final first = stop(
          'first',
          hours: const [
            OpeningPeriod(
              openDay: 4,
              openHour: 11,
              openMinute: 0,
              closeDay: 4,
              closeHour: 13,
              closeMinute: 0,
            ),
          ],
        );
        final second = stop(
          'second',
          hours: const [
            OpeningPeriod(
              openDay: 4,
              openHour: 15,
              openMinute: 0,
              closeDay: 4,
              closeHour: 18,
              closeMinute: 0,
            ),
          ],
        );
        final d = day(
          start: stop('hotel'),
          end: stop('hotel'),
          stops: [first, second],
        );
        final matrix = Matrix();
        final ordering = await orderDay(d, travelMatrix: matrix);
        final gaps = findScheduleGaps(day: d, ordering: ordering);
        expect(gaps.first.availableUntil, at(11));
        final internal = gaps.firstWhere((g) => g.from == first);
        expect(ordering.visits.last.arrival, at(12, 10));
        expect(internal.availableUntil, at(15));
        final inserted = await insertIntoGap(
          day: d,
          ordering: ordering,
          gap: internal,
          stop: stop('extra'),
          travelMatrix: matrix,
        );
        expect(inserted, isNotNull);
        expect(inserted!.visits.last.visitStart, at(15));
        expect(d.assignedStops, [first, second]);
        expect(ordering.visits, hasLength(2));
      },
    );
    test('a meal-only day gains a visit without moving lunch', () async {
      final lunch = stop('lunch', meal: MealType.lunch);
      final d = day(start: stop('hotel'), end: stop('hotel'), stops: [lunch]);
      final matrix = Matrix();
      final ordering = await orderDay(d, travelMatrix: matrix);
      expect(ordering.visits.single.visitStart, at(11, 30));
      final gap = findScheduleGaps(day: d, ordering: ordering).first;
      final result = await insertIntoGap(
        day: d,
        ordering: ordering,
        gap: gap,
        stop: stop('museum'),
        travelMatrix: matrix,
      );
      expect(result!.visits.last.stop, lunch);
      expect(result.visits.last.visitStart, at(11, 30));
      expect(
        await insertIntoGap(
          day: d,
          ordering: ordering,
          gap: gap,
          stop: stop('too-long', minutes: 180),
          travelMatrix: matrix,
        ),
        isNull,
      );
      expect(d.assignedStops, [lunch]);
    });
    test(
      'three empty days use trip origin fallback without needing hotels',
      () async {
        final origin = stop('origin');
        final days = buildTripDays(
          startDate: at(0),
          endDate: at(0).add(const Duration(days: 2)),
          tripStartLocation: origin,
          tripEndLocation: stop('end'),
        );
        expect(days[1].startAnchor, isNull);
        expect(days[1].routeOrigin, origin);
        for (final d in days) {
          expect(
            await recommendations(d, Matrix(), [nearby('candidate')]),
            isNotEmpty,
          );
        }
      },
    );
    test('no origin skips Nearby Search', () async {
      final places = Places([], failSearch: true);
      final d = day();
      final matrix = Matrix();
      expect(
        await findGapRecommendations(
          day: d,
          ordering: await orderDay(d, travelMatrix: matrix),
          alreadyOnTrip: {},
          travelMatrix: matrix,
          placesService: places,
        ),
        isEmpty,
      );
      expect(places.calls, 0);
    });
  });
  group('candidate identity and validation', () {
    test('same Place ID is excluded even with changed coordinates', () async {
      final d = day(start: stop('hotel'));
      final selected = stop('old-name', placeId: 'same-google-id');
      expect(
        await recommendations(
          d,
          Matrix(),
          [nearby('same-google-id', latitude: 5.42)],
          excluded: {selected},
        ),
        isEmpty,
      );
      expect(
        await recommendations(
          d,
          Matrix(),
          [nearby('different-id')],
          excluded: {selected},
        ),
        isNotEmpty,
      );
      expect(
        stop('visit-1', placeId: 'same'),
        isNot(stop('visit-2', placeId: 'same')),
      );
      expect(
        placeIdentity(stop('visit-1', placeId: 'same')),
        placeIdentity(stop('visit-2', placeId: 'same')),
      );
    });
    test('only five unique candidates per day', () async {
      final result =
          await recommendations(day(start: stop('hotel')), Matrix(), [
            nearby('duplicate'),
            nearby('duplicate'),
            for (var n = 0; n < 9; n++) nearby('$n'),
          ]);
      final all = result.expand((g) => g.candidates).toList();
      expect(all, hasLength(5));
      expect(all.map((c) => placeIdentity(c.visit.stop)).toSet(), hasLength(5));
    });
    test(
      'invalid coordinates and hotel/business candidates are rejected',
      () async {
        final missing = NearbyPlace.fromJson(
          {'id': 'missing'},
          apiKey: '',
          photoMaxWidthPx: 100,
        );
        expect(
          hasValidCoordinates(TripStopLocation.fromNearbyPlace(missing)),
          isFalse,
        );
        expect(
          await recommendations(day(start: stop('hotel')), Matrix(), [
            missing,
            nearby('bad', latitude: 100),
            nearby('hotel', type: 'lodging'),
            nearby('bank', type: 'bank'),
          ]),
          isEmpty,
        );
      },
    );
    test('search failure is distinguishable from zero results', () async {
      final d = day(start: stop('hotel'));
      final matrix = Matrix();
      final ordering = await orderDay(d, travelMatrix: matrix);
      await expectLater(
        findGapRecommendations(
          day: d,
          ordering: ordering,
          alreadyOnTrip: {},
          travelMatrix: matrix,
          placesService: Places([], failSearch: true),
        ),
        throwsA(isA<RecommendationSearchException>()),
      );
      expect(await recommendations(d, matrix, []), isEmpty);
    });
    test('closed weekdays are rejected for manually assigned stops', () async {
      final d = day(
        stops: [
          stop(
            'closed',
            hours: const [
              OpeningPeriod(
                openDay: 5,
                openHour: 9,
                openMinute: 0,
                closeDay: 5,
                closeHour: 18,
                closeMinute: 0,
              ),
            ],
          ),
        ],
      );
      expect((await orderDay(d, travelMatrix: Matrix())).visits, isEmpty);
    });
    test(
      'overnight carry-over and later fitting opening windows work',
      () async {
        final overnight = stop(
          'overnight',
          hours: const [
            OpeningPeriod(
              openDay: 3,
              openHour: 22,
              openMinute: 0,
              closeDay: 4,
              closeHour: 11,
              closeMinute: 0,
            ),
          ],
        );
        expect(
          (await orderDay(
            day(stops: [overnight]),
            travelMatrix: Matrix(),
          )).visits,
          hasLength(1),
        );
        final split = stop(
          'split',
          hours: const [
            OpeningPeriod(
              openDay: 4,
              openHour: 9,
              openMinute: 0,
              closeDay: 4,
              closeHour: 9,
              closeMinute: 30,
            ),
            OpeningPeriod(
              openDay: 4,
              openHour: 14,
              openMinute: 0,
              closeDay: 4,
              closeHour: 17,
              closeMinute: 0,
            ),
          ],
        );
        expect(
          (await orderDay(
            day(stops: [split]),
            travelMatrix: Matrix(),
          )).visits.single.visitStart,
          at(14),
        );
      },
    );
    test('meals wait for their window and cannot finish outside it', () async {
      final lunch = stop('lunch', meal: MealType.lunch);
      final result = await orderDay(
        day(stops: [lunch]),
        travelMatrix: Matrix(),
      );
      expect(result.visits.single.visitStart, at(11, 30));
      expect(
        await evaluateCandidateVisit(
          lunch,
          day: day(),
          from: null,
          currentTime: at(14),
          travelMatrix: Matrix(),
        ),
        isNull,
      );
    });
  });
  group('atomic persistence and draft generation', () {
    test(
      'save uses one RPC and keeps the same payload when retrying',
      () async {
        final requests = <Map<String, dynamic>>[];
        final client = SupabaseClient(
          'https://example.test',
          'test-key',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/rest/v1/rpc/commit_trip_schedule');
            expect(request.method, 'POST');
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return requests.length == 1
                ? http.Response(
                    '{"message":"conflict","code":"40001"}',
                    409,
                    headers: {'content-type': 'application/json'},
                    request: request,
                  )
                : http.Response(
                    '2',
                    200,
                    headers: {'content-type': 'application/json'},
                    request: request,
                  );
          }),
        );
        final service = TripService(client: client);
        final d = day(start: stop('hotel'), stops: [stop('museum')]);
        final ordering = await orderDay(d, travelMatrix: Matrix());
        final rows = buildScheduleRows([
          (day: d, ordering: ordering),
        ], travelMode: 'walk');
        Future<int> save() => service.saveSchedule(
          'trip',
          rows,
          expectedRevision: 1,
          operationId: 'operation',
          newStops: [stop('museum')],
          recommendation: true,
        );
        await expectLater(save(), throwsA(isA<PostgrestException>()));
        expect(await save(), 2);
        expect(requests[0], requests[1]);
        final persisted = (requests.first['p_rows'] as List).single as Map;
        expect(persisted['travel_mode'], 'walk');
        expect(persisted['travel_minutes'], 10);
        expect(persisted['scheduled_visit_start'], '09:10:00');
        await client.dispose();
      },
    );
    test(
      'draft planning makes zero database requests and retains selected stops',
      () async {
        var requests = 0;
        final client = SupabaseClient(
          'https://example.test',
          'test-key',
          httpClient: MockClient((_) async {
            requests++;
            throw StateError('Planning must not access the database');
          }),
        );
        final scheduler = TripSchedulerService(
          tripService: TripService(client: client),
          travelMatrix: Matrix(),
          placesService: Places([]),
          weatherService: NoWeather(),
        );
        final draft = TripDraft(
          name: 'Trip',
          description: '',
          destination: '',
          startCity: '',
          endCity: '',
          startDate: at(0),
          endDate: at(0).add(const Duration(days: 2)),
          startTime: '09:00:00',
          endTime: '18:00:00',
          totalBudget: 0,
          autoRecommend: true,
          transportMode: 'walk',
          accommodationMode: 'skip',
          selectedStops: {stop('short'), stop('impossible', minutes: 1000)},
          selectedInterests: {},
          accommodationByNight: {},
          startLocation: stop('origin'),
          endLocation: stop('end'),
        );
        final prepared = await prepareTripDraft(
          draft,
          tripId: 'trip',
          scheduler: scheduler,
          placesService: Places([]),
        );
        expect(requests, 0);
        expect(prepared.schedule.days, hasLength(3));
        expect(
          prepared.schedule.unscheduledStops.map((u) => u.stop.name),
          contains('impossible'),
        );
        expect(
          prepared.schedule.days
              .expand((d) => d.ordering.visits)
              .map((v) => v.stop.name),
          contains('short'),
        );
        expect(buildScheduleDayRows(prepared.schedule.days), hasLength(3));
        expect(prepared.stops.every((s) => s.id != null), isTrue);
        await client.dispose();
      },
    );
    test('new auto meals cannot remove a selected stop', () async {
      final client = SupabaseClient('https://example.test', 'test-key');
      final scheduler = TripSchedulerService(
        tripService: TripService(client: client),
        travelMatrix: Matrix(),
        placesService: Places([nearby('restaurant', type: 'restaurant')]),
        weatherService: NoWeather(),
      );
      final trip = Trip(
        id: 'trip',
        name: 'test',
        destination: '',
        startDate: at(0),
        endDate: at(0),
        totalBudget: 0,
        createdBy: '',
        createdAt: at(0),
        startTime: (hour: 9, minute: 0),
        endTime: (hour: 12, minute: 0),
      );
      final result = await scheduler.plan(
        trip: trip,
        allStops: [stop('selected', minutes: 175)],
        accommodationByNight: {},
      );
      expect(
        result.days.single.ordering.visits.map((v) => v.stop.name),
        contains('selected'),
      );
      await client.dispose();
    });
  });
}
