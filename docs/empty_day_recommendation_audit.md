# Empty-day recommendations — implementation cross-check

Audit date: 2026-09-04
Scope: the user's 62-point Empty-Day Auto-Suggestion checklist, compared against the current working-tree implementation and relevant CLAUDE.md requirements.

> Implementation follow-up: see [empty_day_recommendation_fixes.md](empty_day_recommendation_fixes.md). The findings below preserve the original pre-fix audit.

## Verdict

**Partially implemented; the definition of done is not met.**

The current code already has `findScheduleGaps` and `findGapRecommendations`. An empty `ordering.visits` list produces a full-day gap when a start or end anchor exists. This is more implementation than the earlier conversation described.

However, return-to-anchor checking, gap discovery, safe additions, duplicate prevention, and several required tests are incomplete. Passing the existing scheduling tests does not prove the checklist's acceptance scenarios.

This was a source-code audit plus execution of the existing analyzer and test suite. No implementation files were changed. No live Google API calls or Supabase database inspection were performed.

## Validation actually performed

- `flutter analyze --no-pub`: **passed**, no issues.
- `flutter test --no-pub`: **failed overall**.
- All **28 tests in test/scheduling_test.dart passed**.
- `test/widget_test.dart:19` fails because the old counter-app smoke test expects text "0" in the current application.
- The recommendation tests cover a normal tail suggestion, insufficient raw gap duration, coordinate-based exclusion, one empty day with a start anchor, and a manually constructed between-visits gap.
- There are no integration tests proving safe Add-to-Day persistence, concurrent additions, save failure recovery, or the complete three-day empty-trip flow.

## Findings that prevent completion

### F1 — Return travel is omitted from empty-day and tail recommendations [P1]

[nearby_recommendation.dart:94](C:/Users/User/Desktop/travelplanner/lib/utils/scheduling/nearby_recommendation.dart:94) creates an empty-day gap with `to: null`. The tail gap also has `to: null`. At [line 217](C:/Users/User/Desktop/travelplanner/lib/utils/scheduling/nearby_recommendation.dart:217), outgoing travel is checked only when `gap.to != null`; there is no fallback to `day.endAnchor`.

Example: a candidate finishes at 19:30, the hotel is 50 minutes away, and daily end is 20:00. The recommendation filter can accept this candidate because 19:30 is before 20:00. It never checks the 20:20 hotel arrival.

The shared evaluator checks travel into the candidate and its closing/daily-end times, but does not check travel out to the end anchor. The later optimizer is not a complete safeguard: [day_ordering.dart:248](C:/Users/User/Desktop/travelplanner/lib/utils/scheduling/day_ordering.dart:248) accepts an unknown return duration and trims at most one visit without rechecking the resulting route.

Required correction: reserve the actual outgoing route to the next fixed visit or end anchor, reject unavailable required routes, and validate the resulting full route.

### F2 — Actual waiting gaps are missed [P1]

[nearby_recommendation.dart:110](C:/Users/User/Desktop/travelplanner/lib/utils/scheduling/nearby_recommendation.dart:110) uses the next stop's `arrival` as the gap deadline. In real optimizer output:

```text
Next arrival = previous visit end + travel
Next visit start = arrival, or later if waiting for opening
```

Therefore the measured gap normally contains only the existing travel leg. A stop ending at 10:00 followed by a 10-minute journey to a museum opening at 15:00 produces a 10-minute "gap", even though there is several hours of usable waiting time.

There is also no gap before the first scheduled visit. The existing middle-gap test manually sets a 15:00 arrival after a 10:00 departure with 15 minutes of travel, so it does not reproduce the scheduler's real arrival/wait semantics.

Required correction: discover leading and intermediate free time from visit-start deadlines, include travel on both sides, and test using actual `orderDay` output.

### F3 — Accepting a suggestion can change or lose existing plans without safe rollback [P1]

[ai_planner_screen.dart:351](C:/Users/User/Desktop/travelplanner/lib/screens/trip/ai_planner_screen.dart:351) inserts the new database stop and mutates the live day before validating the complete addition.

The added candidate itself may be moved to another day or left unscheduled. Existing stops may also be displaced. Other affected days are reordered, but their newly unfit stops are not fully reconciled. There is no all-stops-fit acceptance gate.

On failure, the catch block removes only the selected stop from one local list. It does not delete the inserted database row or restore every changed day. [TripService.saveSchedule:467](C:/Users/User/Desktop/travelplanner/lib/services/trip_service.dart:467) deletes the existing schedule before inserting its replacement in a separate request; a failed insert can leave the database without the previous schedule.

Required correction: evaluate changes on copies first; explicitly report proposed displacements; reject invalid additions; commit the accepted stop and schedule atomically or with reliable recovery and idempotency.

### F4 — Duplicate prevention and concurrent updates are incomplete [P1]

[TripStopLocation equality:337](C:/Users/User/Desktop/travelplanner/lib/models/trip_stop_location.dart:337) compares latitude, longitude, and OSM ID, not Google Place ID.

Consequences:
- The same Google place with slightly changed coordinates can be recommended again.
- Different businesses at identical coordinates can be incorrectly treated as duplicates.
- Accepting a place refreshes only touched days, so the same place can remain on another day's recommendation cards.
- The Add handler does not recheck current trip membership before insertion.
- `_addingTo` prevents a second addition to the same day, but simultaneous additions to different days can both rewrite the whole schedule from different snapshots.
- The checked-in schema has no recommendation-specific uniqueness/idempotency rule preventing these duplicate additions.

Required correction: separate physical-place identity from visit identity, deduplicate suggestions by Place ID, refresh/invalidate duplicates across all days, and serialize or version whole-trip updates. Preserve intentional repeated meal/hotel visits when designing database constraints.

### F5 — Anchor fallback and candidate input checks are incomplete [P2]

Empty-day origin selection currently stops at `day.startAnchor ?? day.endAnchor`. A middle day without accommodation has neither, even when the trip has valid Starting-From and Ending-At locations.

No trip-level fallback or coordinate validation exists in the recommendation function. [NearbyPlace parsing:173](C:/Users/User/Desktop/travelplanner/lib/models/nearby_place.dart:173) substitutes zero for missing coordinates; those values are not rejected before route evaluation.

Nearby Search is unrestricted, and there is no candidate visit-purpose filter. A new hotel or unrelated business can be offered as a normal visit.

Required correction: supply explicit trip-level fallback context, validate coordinates, and restrict recommendation candidates to suitable visit purposes while preserving interests as soft ranking preferences.

### F6 — Meal and user-selected-stop protection is insufficient [P1]

Days containing only meals are not treated as sightseeing-empty. They rely on the same incomplete gap logic described in F2.

Meal timing in [day_ordering.dart:414](C:/Users/User/Desktop/travelplanner/lib/utils/scheduling/day_ordering.dart:414) is a soft score, with no hard allowed-window rejection or deliberate wait until mealtime. Reordering after a recommendation can therefore put a meal outside its allowed window.

Separately, [trip_scheduler_service.dart:285](C:/Users/User/Desktop/travelplanner/lib/services/trip_scheduler_service.dart:285) removes all unfit stops after adding automatic meals, not just newly suggested meals, without adding the removed selected stops to the returned unscheduled list. This violates the checklist's user-choice preservation requirement.

Required correction: preserve all user-selected stops in either scheduled or explicitly unscheduled results; keep meal commitments when inserting attractions; test a meal-only day with real scheduled times.

### F7 — Recommendation failures are hidden and stale requests can overwrite results [P2]

Search errors become empty arrays. [_DaySection:851](C:/Users/User/Desktop/travelplanner/lib/screens/trip/ai_planner_screen.dart:851) renders loading or non-empty recommendations, but no distinct failed/no-results/no-origin state and no retry action.

Per-day state exists, but there is no request generation/version check. A request started before a schedule change can later publish stale suggestions. There is also no early duplicate-load guard.

Required correction: track loading/loaded/failed per day, expose retry and meaningful empty states, and discard responses for obsolete schedule versions.

### F8 — Reloaded itinerary presentation loses information [P2]

[buildScheduleRows:421](C:/Users/User/Desktop/travelplanner/lib/services/trip_scheduler_service.dart:421) saves arrival, departure, and incoming travel minutes, but sets travel mode to null and does not store visit-start separately from arrival.

When a visitor arrives at 09:15 and waits until 10:00, the recommendation card shows a 10:00 visit start, while persisted readers only have the 09:15 arrival. The AI Planner and Daily Timeline also skip rendering the incoming leg for the first visit, even when it starts from a hotel. Daily Timeline builds days only from stored visit rows, so an empty day disappears there.

Required correction: preserve or reconstruct arrival, waiting, visit start, travel mode, and anchor legs consistently; build timeline days from trip dates, including free days.

## Checklist results

"Supported" means the relevant code path exists and was inspected; it does not imply live API/database verification. "Partial" means at least one requested condition is missing. "Unverified" means required scenario coverage or live evidence is absent.

| # | Check | Result and evidence |
|---|---|---|
| 1 | Detect empty scheduled days | Supported: uses actual `ordering.visits.isEmpty` after scheduling; anchors are separate. Meal-only case is incomplete, see 31. |
| 2 | Avoid last-stop access on empty days | Supported: empty branch returns before `.last`. |
| 3 | Choose correct empty-day origin | Partial: start anchor then end anchor only; no trip-level fallback. F5. |
| 4 | Handle missing anchors safely | Partial: returns no gaps without crashing, but no fallback/message or coordinate checks. |
| 5 | Full available-time calculation | Partial: starts at dailyStart, includes inbound travel/wait/visit, omits end-anchor return. F1. |
| 6 | Apply minimum-time rule correctly | Partial: empty days get their full raw window and configurable 90-minute minimum; mandatory outgoing travel is not deducted. |
| 7 | Execute Nearby Search | Partial: service call exists and fake tests exercise it; unrestricted types, missing coordinate validation. Live call unverified. |
| 8 | Use interests | Supported: loaded interests apply a soft category bonus after feasibility filtering; no-interest search works. |
| 9 | Exclude existing trip places | Partial: a broad exclusion set is built, but identity, dropped stops, stale cards, and accepted duplicates remain problems. F4/F6. |
| 10 | Validate business status | Supported: permanent and temporary closures rejected; missing status is permissive. |
| 11 | Validate opening date | Partial: weekly checks exist; overnight carry-over is not fully handled and date-specific exceptions are not fully modeled. |
| 12 | Simulate arrival and opening wait | Supported for ordinary opening windows; wait contributes to score. |
| 13 | Finish before closing | Supported for the chosen ordinary opening window; missing hours are treated as unknown/unconstrained. |
| 14 | Include estimated visit duration | Supported: positive category defaults exist and feed simulation; no general malformed-duration validation. |
| 15 | Use Routes API | Partial: actual route durations used for inbound and internal-gap outbound legs; tail/empty outbound legs omitted. |
| 16 | Respect transport mode | Supported for drive/walk/public_transport; unknown values fall back to drive. Date-specific transit departure time is not passed. |
| 17 | Reserve return to final anchor | **Fail**. F1. |
| 18 | Apply weather suitability | Partial: uses candidate visit-start period and day forecast; not each candidate's own location or whole visit span. |
| 19 | Keep weather as soft preference | Supported: weather adds bonuses/penalties instead of banning all outdoor visits. |
| 20 | Rank candidates | Supported: travel, waiting, closing risk, meal/weather, interest, rating; review count is not used. |
| 21 | Limit result count | Partial: five per gap, not five unique results per day; duplicate cards across gaps are possible. |
| 22 | Clear empty-day UI | Partial: empty text and candidate details exist; no anchor-context, failed-search, no-results, or retry message. |
| 23 | Do not auto-insert optional suggestions | Supported for recommendation fetching; core generation separately writes meals/accommodation. |
| 24 | Persist accepted place fields | Supported insert mapping; intended-day placement is not guaranteed after reoptimization. F3. |
| 25 | Re-optimize after adding | Supported: calls orderDay, recalculates visits, and saves schedule rows; safe-acceptance conditions missing. |
| 26 | Validate complete addition | **Fail**: no complete feasibility/preservation gate, strict meal-window check, or reconciliation of all affected days. |
| 27 | Roll back failed addition | **Fail**: database insert, local mutations, and schedule replacement are not restored together. F3. |
| 28 | Refresh after first addition | Partial: touched days refresh; obsolete requests and duplicate cards on other days remain. |
| 29 | Support multiple additions safely | Partial: sequential happy path exists; concurrency, identity, and failed-addition cases are not safe. |
| 30 | Stop when no useful time remains | Partial: raw gap threshold exists; end-anchor deduction and exhausted-capacity message missing. |
| 31 | Meal-only day interaction | **Fail** as a complete requirement: no sightseeing-empty distinction, correct waiting-gap discovery, or protected meal windows. |
| 32 | Accommodation interaction | Partial: starting near hotel works; outgoing hotel deadline and route/backtracking quality are incomplete. |
| 33 | Day 1 special case | Partial: correct Starting-From anchor and inbound travel; tonight's hotel return not checked by recommendations. |
| 34 | Final-day special case | **Fail**: final destination exists on TripDay but is omitted by the whole-day/tail recommendation check. |
| 35 | One-day empty trip | Partial: correct initial origin and suggestions path; safe acceptance and return-trip guarantee incomplete. |
| 36 | Auto Recommend OFF | Supported: optional recommendation startup exits immediately; automatic meals are independent. No dedicated UI test. |
| 37 | Zero selected stops + ON | Partial: create form allows it; anchor days can get suggestions; middle-day fallback and meal interaction incomplete. |
| 38 | Zero selected stops + OFF | Not allowed by current Create Trip location validation. Direct scheduler callers can have empty days; no fake attractions are inserted. |
| 39 | Day-specific recommendation state | Supported map keyed by TripDay; cross-day invalidation remains incomplete. |
| 40 | Prevent duplicate searches | Partial: rebuilds do not start searches, but no in-flight guard or stale-response version check. |
| 41 | Places failure non-fatal | Partial: existing trip remains; failure is silently hidden rather than shown with retry. |
| 42 | Route failure non-fatal | Partial: inbound unavailable routes are skipped; required end-route checks are missing or permissive. |
| 43 | Database duplicate protection | **Fail**: same-day button guard only; no applicable Place-ID/idempotency constraint or global update guard. |
| 44 | Persistence survives reload | Partial: rows are written/read; visit-start/mode/anchor presentation gaps remain. Live round-trip unverified. |
| 45 | Safe widget/request lifecycle | Partial: post-await mounted checks exist; obsolete results and loads begun after disposal remain unguarded in some paths. |
| 46 | Non-empty-day regression | Partial: happy-path tail test passes, but return-to-anchor feasibility is still missing. |
| 47 | Preserve core scheduler behavior | Partial: selected stops are initially scheduled first; meal/addition displacement can still lose choices. F6. |
| 48 | Preserve unscheduled user choices | Partial: known unscheduled choices are displayed/excluded, but not every dropped/displaced stop reaches that list. |
| 49 | Update recommendation origin | Partial: touched-day origin is recalculated; obsolete asynchronous results can replace fresh state. |
| 50 | Display tentative vs final time | Partial: card uses simulated visitStart and final optimizer recomputes; tentative label and reload consistency missing. |
| 51 | Explain candidate rejection | **Missing**: filters silently continue; no structured rejection reasons/counters. |
| 52 | Empty-origin unit tests | Partial: one start-anchor empty-day test exists; fallback/no-anchor/recorded-search-center tests absent. |
| 53 | Recommendation feasibility tests | Partial: successful candidates and raw time threshold tested; required closing/wait/return failure coverage absent. |
| 54 | Real-schedule deterministic integration | **Missing**: no specified fitting-A/rejected-B anchored scenario. |
| 55 | Mixed three-day integration | **Missing**. |
| 56 | Empty-day weather integration | **Missing**: existing weather test exercises orderDay, not empty-day recommendation ranking. |
| 57 | Interest ranking tests | **Missing**, including closed matching candidate vs open alternative. |
| 58 | Transport-mode integration | **Missing**: recommendation tests use a fixed-duration fake, not all three routing modes. |
| 59 | Database consistency test | **Unverified**, with known atomicity and duplicate risks. |
| 60 | Flutter analyzer | **Pass**: flutter analyze --no-pub, no issues. |
| 61 | Complete automated test suite | **Fail overall**: 28 scheduling tests pass; old counter widget test fails. |
| 62 | Final acceptance scenarios | **Not complete**; see below. |

## Final acceptance scenarios A–H

| Scenario | Audit result |
|---|---|
| A — Empty middle day with hotel | Basic branch and cards exist; full integration untested and meal-only behavior incomplete. |
| B — Accept first suggestion | Inbound route works; return feasibility, intended-day guarantee, and atomic persistence fail the complete scenario. |
| C — Accept second suggestion | Reordering exists; no verified safe multi-addition/cross-day duplicate handling. |
| D — Visit finishes after closing | Ordinary closing-window check rejects it; no dedicated recommendation regression test. |
| E — Cannot return to hotel by daily end | **Fails recommendation filtering**. |
| F — No hotel, empty Day 1 | Starting-From origin works; intermediate no-hotel days do not inherit a trip fallback. |
| G — Places API failure | Trip survives; requested user-facing failure/retry message missing. |
| H — Auto Recommend OFF | Optional suggestions/search disabled; a completely empty create form is currently rejected unless ON. Meals remain separate. |

## Correction to earlier documentation

The earlier explanation that the database is written only after planning succeeds is inaccurate. [AiPlannerScreen._generate:121](C:/Users/User/Desktop/travelplanner/lib/screens/trip/ai_planner_screen.dart:121) creates the trip row **before** calling the scheduler at line 143. It attempts best-effort deletion on failure; this is not a deferred commit or database transaction.

This timing is outside the empty-day feature itself, but it affects the earlier creation requirement and any database-consistency claims.

## Recommended fix order

1. Correct anchor-return feasibility and real waiting/leading-gap discovery.
2. Make accepted additions validate on copies and commit safely; preserve all existing choices.
3. Add Place-ID-based suggestion identity, trip-wide update coordination, and stale-response protection.
4. Add trip-level fallback origins, coordinate/type checks, and meal-safe attraction insertion.
5. Provide explicit loading/error/empty states and consistent saved itinerary presentation.
6. Add the missing deterministic acceptance tests and replace the obsolete widget smoke test.
7. Verify the finished flow with a controlled live trip and database round-trip.

Do not mark this feature complete based only on the existing empty-day test or the presence of recommendation cards.
