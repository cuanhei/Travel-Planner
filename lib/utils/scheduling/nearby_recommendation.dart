import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import 'day_ordering.dart';
import 'travel_matrix.dart';
import 'trip_day.dart';
import 'validation.dart';
import 'place_identity.dart';

/// spec §37's example minimum — a free stretch shorter than this isn't
/// worth searching for another stop in at all.
const _defaultMinGapMinutes = 90;

/// At most five unique places across the day's gaps.
const _defaultMaxCandidates = 5;

const _maxRating = 5.0;
const _ratingPenaltyPerStar = 8.0;

/// A place with no [TripStopLocation.rating] at all is scored as if it
/// were a little below a known-good (4-star-ish) place — not as bad as
/// an actually-low-rated one, but not free-riding a null into looking
/// perfect either.
const _noRatingPenalty = _ratingPenaltyPerStar;

/// A candidate whose category matches one of the traveler's picked
/// Create Trip interests (spec's `trip_interests`, previously collected
/// but never consulted by anything) is nudged ahead of an equally-good
/// but uninteresting one — a soft preference, same spirit as
/// [_ratingPenaltyPerStar], not a hard filter: Google's own top-result
/// ranking still decides what's even in the candidate pool.
const _interestMatchBonus = -10.0;

/// One free stretch of time within a day worth searching for an extra
/// stop in. A day isn't just "however much time is left after the last
/// stop" — it can have idle time in the *middle* too (an 11am finish and
/// a next stop that doesn't open until 3pm), and a day with nothing
/// scheduled on it at all is itself one single whole-day gap, not a
/// dead end. [findScheduleGaps] enumerates every one of these for a day;
/// [findGapRecommendations] searches each.
class ScheduleGap {
  const ScheduleGap({
    required this.from,
    required this.availableFrom,
    required this.to,
    required this.availableUntil,
    required this.label,
  });

  /// The stop (or day start anchor) the traveler would be leaving from
  /// to reach a candidate — also where the search is centered.
  final TripStopLocation from;
  final DateTime availableFrom;

  /// The stop the traveler needs to reach [to] by — the *original*
  /// visit-start time already locked in for it. Tail and empty-day gaps
  /// use the final anchor instead; null only when that side is unconstrained.
  final TripStopLocation? to;
  final DateTime availableUntil;

  /// Traveler-facing description of where this gap sits in the day.
  final String label;

  Duration get duration => availableUntil.difference(availableFrom);
}

/// [gap]'s ranked, already-feasible candidates (spec §46: top 3-5,
/// never auto-added) — empty results for a gap aren't returned at all
/// by [findGapRecommendations], so every entry here has at least one
/// candidate.
class GapRecommendations {
  const GapRecommendations({required this.gap, required this.candidates});
  final ScheduleGap gap;
  final List<CandidateEvaluation> candidates;
}

/// Enumerates every gap in [day] worth searching, given how [ordering]
/// currently lays it out: the stretch before/between/after visits (and,
/// for a day with no visits at all, the *entire* day) that's at least
/// [minGapMinutes] long. A day with no visits and no anchor at all
/// (nothing to search "near") yields no gaps — there's simply nowhere
/// to center a search.
List<ScheduleGap> findScheduleGaps({
  required TripDay day,
  required DayOrderingResult ordering,
  int minGapMinutes = _defaultMinGapMinutes,
}) {
  final visits = ordering.visits;
  final gaps = <ScheduleGap>[];

  if (visits.isEmpty) {
    final reference = day.routeOrigin ?? day.endAnchor;
    if (reference != null && hasValidCoordinates(reference)) {
      gaps.add(
        ScheduleGap(
          from: reference,
          availableFrom: day.dailyStart,
          to: day.endAnchor,
          availableUntil: day.dailyEnd,
          label: 'Nothing scheduled yet today',
        ),
      );
    }
    return gaps
        .where(
          (g) =>
              hasValidCoordinates(g.from) &&
              g.duration.inMinutes >= minGapMinutes,
        )
        .toList();
  }

  final origin = day.routeOrigin;
  if (origin != null && hasValidCoordinates(origin)) {
    gaps.add(
      ScheduleGap(
        from: origin,
        availableFrom: day.dailyStart,
        to: visits.first.stop,
        availableUntil: visits.first.visitStart,
        label: 'Free time before ${visits.first.stop.name}',
      ),
    );
  }
  for (var i = 0; i < visits.length - 1; i++) {
    final current = visits[i];
    final next = visits[i + 1];
    gaps.add(
      ScheduleGap(
        from: current.stop,
        availableFrom: current.visitEnd,
        to: next.stop,
        availableUntil: next.visitStart,
        label: 'Free time between ${current.stop.name} and ${next.stop.name}',
      ),
    );
  }

  final last = visits.last;
  gaps.add(
    ScheduleGap(
      from: last.stop,
      availableFrom: last.visitEnd,
      to: day.endAnchor,
      availableUntil: day.dailyEnd,
      label: 'Free time after ${last.stop.name}',
    ),
  );

  return gaps
      .where(
        (g) =>
            hasValidCoordinates(g.from) &&
            g.duration.inMinutes >= minGapMinutes,
      )
      .toList();
}

/// spec §36-45, generalized to every gap [findScheduleGaps] finds (not
/// just "after the last stop"): for each sufficiently long gap, searches
/// near whichever stop the traveler would be leaving from, filters out
/// anything already on the trip / closed / that can't actually be
/// reached and finished in time — and, when the gap has something
/// scheduled *after* it, that can't be reached by its original arrival
/// time either, so an addition here never pushes back the rest of the
/// day — and ranks what's left. Spec §46: nothing here is ever
/// auto-added, only returned for the traveler to choose from.
///
/// Successful empty searches return an empty list. A failed search with no
/// usable results throws [RecommendationSearchException] so the UI can retry.
Future<List<GapRecommendations>> findGapRecommendations({
  required TripDay day,
  required DayOrderingResult ordering,
  required Set<TripStopLocation> alreadyOnTrip,
  required TravelMatrixSource travelMatrix,
  GooglePlacesService? placesService,
  Set<String> interestCategories = const {},
  int minGapMinutes = _defaultMinGapMinutes,
  int maxCandidatesPerGap = _defaultMaxCandidates,
}) async {
  final gaps = findScheduleGaps(
    day: day,
    ordering: ordering,
    minGapMinutes: minGapMinutes,
  );
  if (gaps.isEmpty) return const [];

  final places = placesService ?? GooglePlacesService();
  final results = <GapRecommendations>[];
  final excluded = alreadyOnTrip.map(placeIdentity).toSet();
  var failedSearches = 0;

  for (final gap in gaps) {
    List<NearbyPlace> found;
    try {
      found = await places.nearbySearch(
        center: LatLng(gap.from.latitude, gap.from.longitude),
      );
    } catch (_) {
      failedSearches++;
      continue;
    }

    final scored = <CandidateEvaluation>[];
    for (final place in found) {
      final stop = TripStopLocation.fromNearbyPlace(place);

      // spec §40: not already on this trip in any capacity.
      if (excluded.contains(placeIdentity(stop)) ||
          !hasValidCoordinates(stop) ||
          !const {
            'Attraction',
            'Nature',
            'Culture',
            'Shopping',
            'Beach',
            'Food',
          }.contains(stop.category) ||
          stop.visitPurpose == VisitPurpose.accommodation) {
        continue;
      }

      // spec §40: operational, and open at all on this date within the
      // daily window.
      if (validateStopForDate(
            stop,
            date: day.date,
            dailyStart: day.dailyStart,
            dailyEnd: day.dailyEnd,
          ) ==
          StopValidationResult.invalid) {
        continue;
      }

      // spec §42-43: real travel time from [gap.from], and the same
      // arrival/opening-hours/weather/meal simulation the core
      // scheduler uses for every other candidate.
      final evaluated = await evaluateCandidateVisit(
        stop,
        day: day,
        from: gap.from,
        currentTime: gap.availableFrom,
        travelMatrix: travelMatrix,
      );
      if (evaluated == null) continue;

      // spec §44, generalized: must still reach whatever comes after
      // this gap (the day's own end/end anchor for a tail/whole-day
      // gap, or the next already-scheduled stop's original arrival time
      // for a between-visits gap) without pushing it back.
      final to = gap.to;
      if (to != null) {
        final travelToNext = await travelMatrix.travelTime(stop, to);
        if (travelToNext == null ||
            evaluated.visit.visitEnd
                .add(travelToNext)
                .isAfter(gap.availableUntil)) {
          continue;
        }
      } else if (evaluated.visit.visitEnd.isAfter(gap.availableUntil)) {
        continue;
      }

      // spec §45: RouteTravelTime + OpeningHourPenalty + TimeFitPenalty
      // + WeatherPenalty are already folded into evaluated.score by
      // evaluateCandidateVisit — only RatingPenalty is still to add,
      // plus this module's own interest-match bonus.
      var score = evaluated.score + _ratingPenalty(stop.rating);
      if (interestCategories.contains(stop.category)) {
        score += _interestMatchBonus;
      }
      scored.add(CandidateEvaluation(visit: evaluated.visit, score: score));
    }

    if (scored.isEmpty) continue;
    scored.sort((a, b) => a.score.compareTo(b.score));
    results.add(GapRecommendations(gap: gap, candidates: scored));
  }

  if (failedSearches > 0 && results.isEmpty) {
    throw const RecommendationSearchException();
  }
  // Rank across gaps, keeping the best slot for each place and at most five
  // unique suggestions for the whole day.
  final ranked = [
    for (final result in results)
      for (final candidate in result.candidates)
        (gap: result.gap, candidate: candidate),
  ]..sort((a, b) => a.candidate.score.compareTo(b.candidate.score));
  final used = <String>{};
  final byGap = <ScheduleGap, List<CandidateEvaluation>>{};
  for (final entry in ranked) {
    if (!used.add(placeIdentity(entry.candidate.visit.stop))) continue;
    byGap.putIfAbsent(entry.gap, () => []).add(entry.candidate);
    if (used.length >= maxCandidatesPerGap) break;
  }
  return [
    for (final entry in byGap.entries)
      GapRecommendations(gap: entry.key, candidates: entry.value),
  ];
}

double _ratingPenalty(double? rating) {
  if (rating == null) return _noRatingPenalty;
  return (_maxRating - rating).clamp(0, _maxRating) * _ratingPenaltyPerStar;
}

class RecommendationSearchException implements Exception {
  const RecommendationSearchException();
  @override
  String toString() => 'Nearby places could not be loaded. Please retry.';
}
