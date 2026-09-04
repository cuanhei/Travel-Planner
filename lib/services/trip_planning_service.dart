import 'package:uuid/uuid.dart';

import '../models/trip.dart';
import '../models/trip_draft.dart';
import '../models/trip_stop_location.dart';
import '../utils/scheduling/accommodation_recommendation.dart';
import 'google_places_service.dart';
import 'trip_scheduler_service.dart';

class PreparedTrip {
  const PreparedTrip({
    required this.trip,
    required this.fields,
    required this.stops,
    required this.accommodationByNight,
    required this.schedule,
  });
  final Trip trip;
  final Map<String, dynamic> fields;
  final List<TripStopLocation> stops;
  final Map<DateTime, TripStopLocation> accommodationByNight;
  final ScheduleResult schedule;
}

/// No database writes. IDs belong to this prepared plan and stay stable across
/// retries of its eventual atomic commit.
Future<PreparedTrip> prepareTripDraft(
  TripDraft draft, {
  required String tripId,
  required TripSchedulerService scheduler,
  required GooglePlacesService placesService,
}) async {
  TripStopLocation identify(TripStopLocation stop) =>
      stop.copyWith(id: const Uuid().v4());
  final selected = draft.selectedStops.map(identify).toList();
  final start = draft.startLocation == null
      ? null
      : identify(draft.startLocation!);
  final end = draft.endLocation == null ? null : identify(draft.endLocation!);
  final nights = <DateTime, TripStopLocation>{};
  if (draft.accommodationMode == 'add_mine') {
    final identified = <TripStopLocation, TripStopLocation>{};
    for (final entry in draft.accommodationByNight.entries) {
      nights[entry.key] = identified.putIfAbsent(
        entry.value,
        () => identify(
          entry.value.copyWith(visitPurpose: VisitPurpose.accommodation),
        ),
      );
    }
  } else if (draft.accommodationMode == 'recommend' &&
      draft.startDate != null &&
      draft.endDate != null &&
      draft.startDate!.isBefore(draft.endDate!)) {
    final hotel = await findRecommendedAccommodation(
      nearStops: selected,
      fallbackCenter: start,
      placesService: placesService,
    );
    if (hotel != null) {
      final identified = identify(hotel);
      for (
        var night = draft.startDate!;
        night.isBefore(draft.endDate!);
        night = night.add(const Duration(days: 1))
      ) {
        nights[DateTime(night.year, night.month, night.day)] = identified;
      }
    }
  }
  final fields = <String, dynamic>{
    'name': draft.name,
    'description': draft.description,
    'destination': draft.destination ?? '',
    'start_city': draft.startCity,
    'end_city': draft.endCity,
    'start_date': draft.startDate?.toIso8601String().split('T').first,
    'end_date': draft.endDate?.toIso8601String().split('T').first,
    'start_time': draft.startTime,
    'end_time': draft.endTime,
    'total_budget': draft.totalBudget,
    'auto_recommend': draft.autoRecommend,
    'transport_mode': draft.transportMode,
    'accommodation_mode': draft.accommodationMode,
    'start_location_stop_id': start?.id,
    'end_location_stop_id': end?.id,
  };
  final trip = Trip.fromMap({
    ...fields,
    'id': tripId,
    'created_by': '',
    'created_at': DateTime.now().toIso8601String(),
  });
  final allStops = [
    ...selected,
    ...{for (final stop in nights.values) stop.id: stop}.values,
    ?start,
    ?end,
  ];
  final result = await scheduler.plan(
    trip: trip,
    allStops: allStops,
    accommodationByNight: nights,
  );
  final byId = {
    for (final stop in allStops) stop.id: stop,
    for (final day in result.days)
      for (final visit in day.ordering.visits) visit.stop.id: visit.stop,
  };
  return PreparedTrip(
    trip: trip,
    fields: fields,
    stops: byId.values.toList(),
    accommodationByNight: nights,
    schedule: result,
  );
}
