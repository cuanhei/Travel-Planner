# Empty-day recommendations: implemented fixes

Updated: 2026-09-04. This follows the baseline findings in `empty_day_recommendation_audit.md`.

## Database setup

Apply `supabase/migrations/0012_atomic_planned_itineraries.sql` to the existing Supabase project after migration 0011, before running the updated app. For a fresh database, `supabase/schema.sql` includes these changes.

The migration was tested in an isolated PostgreSQL runtime. It has **not** been applied to the hosted project.

It adds:

- `trips.schedule_revision` for detecting stale edits.
- `trip_schedule_stops.scheduled_visit_start`, separate from arrival and departure.
- `trip_schedule_days` for all calendar days and their start/end anchors and return travel.
- `trip_schedule_operations` for idempotent save receipts.
- `commit_trip_schedule` and `create_planned_trip`, authenticated transaction functions.

## Recommendations and route feasibility — F1, F2, F5

- Empty days produce a whole-day recommendation window. Middle days without a hotel can use the trip's starting location as an explicitly labelled assumed origin.
- Search covers waiting time before the first visit, between visits, and after the final visit.
- Intermediate deadlines use the next visit's start, including usable waiting time before opening.
- Every candidate must fit inbound travel, waiting, its visit duration, and outgoing travel to the next visit or final anchor.
- Unknown required routes are rejected. Final-route validation repeatedly removes infeasible trailing visits rather than trimming only once.
- Missing/out-of-range coordinates and unsuitable hotel/business results are excluded.
- Unknown opening hours remain permissive; known closures, closed weekdays, overnight periods, later opening windows, and invalid visit durations are checked by the shared evaluator.

## Safe additions and editing — F3, F4

- Recommendation additions are simulated before changing live state or writing records. Existing visit start times, including meals, stay protected.
- If a previously shown suggestion no longer fits, it is rejected without dropping or moving existing visits.
- Google Place ID controls recommendation deduplication. Separate visit IDs preserve intentional repeat visits and distinct businesses at the same coordinates.
- Suggestions are limited to five unique places across the day's gaps. All days' recommendation results are invalidated after an accepted addition.
- Add operations are serialized across the trip. The database also rejects stale schedule revisions and duplicate recommendation additions.
- Adding a stop in Edit Schedule stages it locally. Save inserts new stops, removes explicitly deleted stops, and replaces the itinerary in one transaction. Failed writes preserve the previous itinerary.
- Edits with unresolved unfit visits or an unreachable end anchor cannot be saved as a feasible itinerary.
- Trip Details refreshes its itinerary after returning from Edit Schedule.

## Meals and unscheduled stops — F6

- Meals wait until their allowed window and must finish inside it.
- Automatic meal candidates are accepted only if every already scheduled stop still fits.
- The final scheduling pass reconciles every user-selected stop into either a visit or an explicit unscheduled entry.
- Unscheduled explanations distinguish invalid coordinates/durations, known closure, missing routes, excessive duration, and conflicting daily/opening windows.

## Recommendation feedback — F7

- Failed searches have a visible retry action, separate from successful searches with no feasible results.
- Empty states explain missing origins or insufficient free time.
- Duplicate loads are skipped; results from before a schedule change cannot overwrite newer results.
- Route failures are not permanently cached, allowing a later retry to recover.

## Creation and reloading — F8

- Draft planning, accommodation lookup and automatic meal planning happen in memory. No trip row is created before planning finishes.
- The completed trip, membership, stops, interests, accommodation, daily metadata and schedule are then committed together.
- Prepared IDs and save operation IDs survive retries, preventing duplicate records after an uncertain response.
- Saved visits retain arrival, visit start, departure, transport mode and inbound travel duration.
- The planner shows the first travel leg and return-to-anchor information. Daily Timeline includes every trip date and displays saved start/end anchors and return travel.
- Edit Schedule respects saved visit start times on reload, including waiting before opening.

## Verification

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 48 tests passed, including scheduling regressions and recommendation retry widgets.
- `test/atomic_schedule_database_test.cjs`: nine checks passed against PGlite 0.5.8, an isolated embedded PostgreSQL runtime. These check successful creation, rollback after creation/save failures, retry idempotency, duplicate rejection, member authorization, stale writes, and intentional repeat meals.

To repeat the database checks with Node and PGlite installed:

```sh
node test/atomic_schedule_database_test.cjs /absolute/path/to/pglite/dist/index.cjs
```

No live Google Places/Routes or hosted Supabase requests were used for verification. Provider results, quotas and availability still require an end-to-end check with the configured project.

## Remaining enhancement boundaries

- Automatic accommodation selection still chooses one hotel for the trip. Per-night manual hotels work; automatic multi-city hotel selection remains the later enhancement from the priority list.
- Weather is resolved per day from its location context and scored by the visit's morning/afternoon/night period. Candidate-specific weather regions and forecasts across an entire long visit are not newly implemented here.
- Optional gap additions preserve existing appointments. They do not automatically displace selected visits to another day; manual cross-day moves remain available in Edit Schedule.
- Opening data remains weekly provider data; special-date closures can only be enforced when represented in the available data.
