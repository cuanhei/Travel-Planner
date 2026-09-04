# Create Trip & AI Planner — How It Currently Works

This documents the **as-implemented** behavior of trip creation and
auto-planning, as opposed to `CLAUDE.md`'s spec (the target behavior). Where
the two differ, it's called out explicitly.

## 1. High-level flow

Trip creation is split across two screens, and — importantly — **nothing is
written to the database until the second screen finishes successfully**:

```
CreateTripScreen                    AiPlannerScreen
─────────────────                   ───────────────
Collects everything     TripDraft   1. Create trip row
the traveler picks    ──────────►   2. Save stops/interests
into local widget      (in-memory,  3. Save/recommend accommodation
state. No Supabase      no DB)      4. Save start/end locations
calls at all.                       5. Run TripSchedulerService.run()
                                     6. On ANY failure: delete the trip
                                        (cascades clean up everything)
                                     7. On success: show the itinerary,
                                        then lazily fetch nearby
                                        recommendations per day
```

This means tapping **Plan My Trip** never creates a database row by itself —
`AiPlannerScreen` is the only place a `trips` row gets created, and only once
every step below it has actually succeeded.

---

## 2. Phase 1 — Create Trip (`lib/screens/trip/create_trip_screen.dart`)

A single scrollable form (`Form` + `SingleChildScrollView` + `Column` — not a
`ListView`, deliberately: `ListView`'s lazy virtualization used to unmount
off-screen `FormField`s and silently skip validating them once the traveler
scrolled past them) with five sections:

### Trip Details
- **Trip Name*** — free text, required (`TextFormField`).
- **Description** — free text, optional.

### Travel Information
- **Starting From\*** / **Ending At\*** — real Google Places search
  (`GooglePlaceSearchField` inside a bottom sheet), not a fixed city list.
  Produces a real `TripStopLocation` with coordinates, opening hours, etc.
  These become the trip's real start/end anchors later.
- **Travel Dates & Time\*** — a date-range picker plus daily start/end time
  (`TimeOfDay`). Also checks the new range against the traveler's other trips
  and blocks overlapping dates.
- **Transport Mode\*** — Driving / Public Transport / Walking (chip
  selector). Feeds `TravelMode` in the scheduler's travel-time matrix.
- **Budget\*** — numeric, required.

### Locations
- Real place search (`TripLocationPicker`) plus a map of everything picked
  so far. Each pick becomes a `TripStopLocation`.
- **Auto-recommend more places** toggle + **Interests** chips (Hotel,
  Restaurant, Shopping, Museum, Beach, Nature, Attraction). If the toggle is
  on, at least one location isn't required.

### Accommodation
Three mutually exclusive choices (`_AccommodationChoice`):
- **Add my accommodation** — a lodging-only place search per night of the
  trip (`_AccommodationPickerSheet`, restricted to Google's `lodging` type).
  A "use this for every remaining night" shortcut copies one hotel to every
  unfilled night.
- **Recommend accommodation** — the traveler picks nothing themselves; the
  AI Planner searches for one later (see §3.3).
- **I don't need accommodation planning** — skipped entirely; the scheduler
  falls back to the trip's own Starting-From/Ending-At locations as day
  anchors.

### Preferences
Just the auto-recommend toggle + interest chips (shown inline under
Locations in the current layout, described here separately for clarity).

### Submission
On **Plan My Trip**:
1. `Form.validate()` runs (now reliably, since every field stays mounted).
2. If valid, everything collected above is bundled into a `TripDraft`
   (`lib/models/trip_draft.dart`) — a plain, immutable, in-memory object.
   No `TripService` write calls happen here.
3. `Navigator.pushReplacement` to `AiPlannerScreen(draft: draft)`.

---

## 3. Phase 2 — AI Planner (`lib/screens/trip/ai_planner_screen.dart`)

`AiPlannerScreen._generate()` runs once on `initState` (and again on
"Retry"). It owns the entire "make this trip real" pipeline:

### 3.1 Create the trip row
```dart
tripId = await _tripService.createTrip(...)   // from TripDraft's fields
```

### 3.2 Save stops & interests
```dart
await _tripService.addStops(tripId, draft.selectedStops);
await _tripService.setInterests(tripId, draft.selectedInterests);
```

### 3.3 Save accommodation (`_saveAccommodation`)
- **`add_mine`** — saves every distinct hotel the traveler picked (dedup'd),
  then links each night to its stop via `TripService.setAccommodations`.
- **`recommend`** — calls
  `findRecommendedAccommodation()`
  (`lib/utils/scheduling/accommodation_recommendation.dart`):
  - Centers a Google Places **lodging** search on the centroid of the
    traveler's selected stops (falls back to the Starting-From location if
    no stops were picked).
  - Filters out permanently/temporarily closed results.
  - Picks the highest-rated (ties broken by review count) operational
    result.
  - Applies that one hotel to every night of the trip.
  - If nothing is found (no API key, no lodging nearby, network failure),
    accommodation is simply left unset — not a fatal error.
- **`skip`** — no-op.

### 3.4 Save trip start/end locations (`_saveTripLocations`)
Saves the Starting-From/Ending-At `TripStopLocation`s as their own
`trip_stops` rows and links them via `trips.start_location_stop_id` /
`end_location_stop_id`.

### 3.5 Run the scheduler
```dart
final trip = await _tripService.getTrip(tripId);
final result = await _schedulerService.run(tripId);
```
See §4 for what this actually does.

### 3.6 Rollback on any failure
If **any** step in 3.1–3.5 throws:
```dart
if (tripId != null) {
  try { await _tripService.deleteTrip(tripId); } catch (_) {}
}
```
`trips.id` cascades (`on delete cascade`) into every child table
(`trip_stops`, `trip_schedule_stops`, `trip_accommodations`,
`trip_interests`, `trip_members`, …), so one delete cleans up everything.
The traveler sees a generic "Could not generate your itinerary" error with
a **Retry** button, which re-runs the whole pipeline from the same
`TripDraft` (so retry never accumulates duplicate broken trips).

### 3.7 Post-generation: nearby recommendations
Once the schedule is on screen, if `trip.autoRecommend` is true, the screen
kicks off a **background, per-day** search (`_startRecommendations`) — see
§5. This never blocks the itinerary from showing.

---

## 4. The scheduling engine (`lib/services/trip_scheduler_service.dart`)

`TripSchedulerService.run(tripId)` is the constraint-based scheduler. Steps,
in order:

1. **Load the trip & pick a travel matrix.** Builds
   `RouteServiceTravelMatrix(travelMode: TravelMode.fromDbValue(trip.transportMode))`
   unless a fake was injected (tests only).
2. **Bail early if there are no dates.** Every stop is reported
   "unscheduled" rather than guessed at.
3. **Fetch all stops**, then split off:
   - the trip's own Starting-From/Ending-At stops (`start_location_stop_id`
     / `end_location_stop_id`, resolved by id against the already-fetched
     list),
   - accommodation stops (`visitPurpose == accommodation`).
   Neither is put in the "things to visit" pool — both are anchors only.
4. **Resolve weather** for the trip's forecast window (MET Malaysia, via the
   first stop's coordinates) — per-day, never assumed for a date outside
   the forecast window.
5. **Build the day list** (`buildTripDays`, in
   `lib/utils/scheduling/trip_day.dart`): one `TripDay` per calendar date,
   each carrying `dailyStart`/`dailyEnd`, weather (if available), and
   **anchors**:
   - Day 1's start = the trip's Starting-From location (never an
     accommodation — there's no "previous night" yet).
   - The last day's end = the trip's Ending-At location.
   - Every day in between: start = last night's hotel, end = tonight's
     hotel (chained night-to-night from `trip_accommodations`).
6. **Precompute the travel-time matrix** for every stop + every anchor
   (batched Routes API calls, cached for the rest of the run).
7. **Assign stops to days** (`assignStopsToDays`, in
   `lib/utils/scheduling/day_assignment.dart`): time-sensitive (meal) and
   long-duration (≥3h) stops are placed first, each into whichever day
   scores lowest on geographic-travel-penalty + capacity-penalty +
   closed-date-penalty + opening-hour-penalty + weather-penalty. A stop
   that can't fit anywhere ends up in `unscheduled`.
8. **Order each day** (`orderDay`, in `lib/utils/scheduling/day_ordering.dart`):
   repeatedly picks the lowest-score next stop (never nearest-neighbor),
   simulating real arrival/wait-for-opening/visit/departure time for each.
   Score = travel time + wait time + closing-risk + meal-time-drift +
   **weather-time-penalty** (an outdoor stop is pulled toward whichever of
   the day's morning/afternoon/night forecast periods is "good", an indoor
   one toward a "bad"/"severe" one). A stop that genuinely can't fit lands
   in that day's `unfitStops` rather than forcing an impossible plan.
9. **Re-optimize across days** (up to 3 passes): any stop left in a day's
   `unfitStops` is pulled out and re-run through `assignStopsToDays` against
   every day again, then every day is re-ordered. Stops that still can't
   fit anywhere after 3 passes are reported unscheduled.
10. **Plan missing meals** (`planMissingMeals`, in
    `lib/utils/scheduling/meal_planning.dart`) — for each day, for each of
    breakfast/lunch/dinner the traveler didn't already pick a restaurant
    for themselves:
    - Skipped outright if that meal's allowed window (spec: breakfast
      7–10am, lunch 11:30am–2:30pm, dinner 6–9pm) doesn't overlap the
      day's daily-start/end window at all.
    - Otherwise, finds the visit (or start/end anchor) the traveler would
      be at/near around that meal's *preferred* clock time, searches
      Google Places (**restaurant** type) centered there, and evaluates
      every candidate with the exact same arrival/opening-hours/weather/
      meal-drift simulation `orderDay` uses for everything else.
    - The best-scoring candidate is saved as a real stop and added to that
      day; the day is then fully re-ordered. If the *full* re-sequence
      still can't fit the new stop, it's dropped rather than left
      assigned-but-invisible.
11. **Persist the schedule** (`buildScheduleRows` → `TripService.saveSchedule`,
    a delete-then-insert of every `trip_schedule_stops` row for the trip).
12. **Return** a `ScheduleResult`: one `ScheduledDay` (day + its final
    visit order) per day, plus the list of stops that couldn't be
    scheduled anywhere.

---

## 5. Nearby recommendations (post-generation, `lib/utils/scheduling/nearby_recommendation.dart`)

Runs only if `trip.autoRecommend` is on, once the core schedule (§4) is
already showing. For each day, independently and in the background:

1. Compute remaining time after the day's last visit (minus the trip back
   to the day's end anchor, if any). Skip entirely if under ~90 minutes —
   no Places call is even made.
2. Google Places **Nearby Search**, centered on the day's *last scheduled
   stop*.
3. Filter out: anything already on the trip in any role (visited,
   unfit-but-assigned, unscheduled, or an anchor), anything closed, and
   anything that fails the same feasibility simulation `orderDay` uses
   (can't reach it in time, would close before the visit ends, or
   couldn't get back to the end anchor afterward).
4. Score survivors: the same travel/opening/timing/weather terms, plus a
   rating penalty and a bonus if the place's category matches one of the
   traveler's picked Interests chips.
5. Show up to 5 ranked cards per day (name, indoor/outdoor, rating, travel
   time, time window) with an explicit **Add to Day N** button — nothing
   is ever added automatically.
6. On tap: saves the stop, re-runs `orderDay` for *just that day* (a fresh
   search for the best position, not an append), re-persists the whole
   schedule, and updates the UI.

---

## 6. Data model touched

| Table | Written by | Notes |
|---|---|---|
| `trips` | `AiPlannerScreen` step 3.1 | Deleted wholesale on any pipeline failure |
| `trip_stops` | stops, accommodation, start/end locations, meals, recommendations | One row per real place; `visit_purpose`/`meal_type`/`environment_type` drive scheduling |
| `trip_accommodations` | `_saveAccommodation` | One row per night → stop id |
| `trip_interests` | `AiPlannerScreen` step 3.2 | Now actually read (§5's interest-match bonus, §3.3's implicit search bias) |
| `trip_schedule_stops` | `TripSchedulerService._persistSchedule` / recommendation "Add" | Delete-then-insert; day number, sequence, arrival/departure, travel minutes |

All child tables reference `trips (id) on delete cascade`, which is what
makes the §3.6 rollback a single `delete` call.

---

## 7. Key files

| File | Role |
|---|---|
| `lib/models/trip_draft.dart` | In-memory bundle Create Trip hands to AI Planner |
| `lib/screens/trip/create_trip_screen.dart` | The form; no DB writes |
| `lib/screens/trip/ai_planner_screen.dart` | Creates the trip, runs the scheduler, shows the itinerary + recommendations |
| `lib/services/trip_scheduler_service.dart` | Orchestrates §4's whole pipeline |
| `lib/services/trip_service.dart` | All Supabase reads/writes (`createTrip`, `deleteTrip`, `addStops`, `setAccommodations`, `saveSchedule`, …) |
| `lib/utils/scheduling/trip_day.dart` | `buildTripDays` — day list + anchor chaining |
| `lib/utils/scheduling/day_assignment.dart` | Which day each stop goes to |
| `lib/utils/scheduling/day_ordering.dart` | Visiting order within a day (`orderDay`, `evaluateCandidateVisit`) |
| `lib/utils/scheduling/meal_planning.dart` | Auto-fills missing breakfast/lunch/dinner |
| `lib/utils/scheduling/accommodation_recommendation.dart` | Auto-suggests a hotel |
| `lib/utils/scheduling/nearby_recommendation.dart` | Post-generation "add one more stop" suggestions |
| `lib/utils/scheduling/weather_suitability.dart` | Weather → scheduling-suitability scoring |
| `lib/utils/scheduling/validation.dart` | Opening-hours/business-status validity per date |
| `lib/utils/scheduling/travel_matrix.dart` | Routes-API-backed travel times, cached per run |

---

## 8. Known gaps

- **Editing an existing trip's stops** (`lib/screens/trip/real_edit_schedule_view.dart`)
  supports reordering, moving a stop between days, and removing one — but
  not *adding* a new real stop to an already-created trip. Only Create
  Trip (before the trip exists) and the post-generation "nearby
  recommendation" flow (§5) can add stops.
- Accommodation recommendation always applies the **same** hotel to every
  night — there's no per-night "recommend a different one" logic.
- Meal-planning and nearby-recommendation both call the real Google Places
  API at generation time, so `AiPlannerScreen`'s loading step can take
  noticeably longer on trips with many days/meals than the core schedule
  alone would.
