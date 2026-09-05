-- Rebuilds trip-planning persistence for the simplified, tab-based daily
-- timeline Create Trip flow (day tabs, per-day accommodation, greedy
-- route optimization, weather-flagged outdoor/mixed stops). Only touches
-- trip-planning tables — Group, Budget, Community, Utilities, and every
-- other module's tables are untouched.
--
-- `trip_stops` is kept (never dropped/renamed): Emergency Contacts
-- (TripService.watchTripStops) and Budget's expense tracker
-- (BudgetService.watchStopNames) both already read it, and
-- `trip_favorite_stops` (a separate "saved for quick directions" list,
-- unrelated to itinerary scheduling) is untouched too. This only adds
-- new nullable columns to `trip_stops` — every existing column, row, and
-- query against it keeps working.
--
-- `trip_schedule_stops` (the old hotel-anchor/is_hotel schedule join
-- table) is dropped and not replaced with a same-named table: nothing in
-- the app queries it any more (the old day-schedule/optimizer services it
-- backed were removed along with the old Create Trip flow), and the new
-- flow doesn't need a separate join table at all — a stop is now added to
-- exactly one day, once, rather than the same physical stop (e.g. a
-- hotel) appearing across several days' schedules. Its day/sequence/timing
-- columns move directly onto `trip_stops` instead.
--
-- `trip_accommodations` already matches the new flow exactly (one row per
-- night, `night_number` 1-indexed) and is left as-is.

-- ============================================================
-- trips: whole-trip transport preference
-- ============================================================

-- Driving vs transit — applies to every travel leg in the trip, chosen
-- once via the toggle above the day tabs. `start_time`/`end_time`
-- (already existing columns) continue to double as the Trip Start Time
-- (when the traveler leaves the starting location) and the optional Trip
-- End Time target (e.g. a flight departure) — no new columns needed for
-- those.
alter table public.trips
  add column if not exists transport_mode text not null default 'driving'
    check (transport_mode in ('driving', 'transit'));

-- ============================================================
-- trip_days: one row per day tab — its date and its own start-time
-- override (Day 1 has none; it always uses `trips.start_time`).
-- ============================================================

create table if not exists public.trip_days (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  day_number integer not null check (day_number > 0),
  date date not null,
  -- Null means "use trips.start_time" — only ever set for day_number > 1,
  -- via each day panel's own start-time edit icon.
  start_time_override time,
  created_at timestamptz not null default now(),
  unique (trip_id, day_number)
);

-- ============================================================
-- trip_stops: extended with the full Google Places record, the
-- estimated visit duration, and — new — which day/position it's
-- scheduled at, its computed arrival/end time, and whether it was
-- flagged for forecast rain.
-- ============================================================

alter table public.trip_stops
  -- Google Places identity/classification — fetched once via Place
  -- Details when the stop is added, not re-derived later.
  add column if not exists place_id text,
  add column if not exists primary_type text,
  add column if not exists types text[] not null default '{}',
  add column if not exists business_status text,
  -- Raw weekday-description lines (e.g. "Monday: 9:00 AM – 6:00 PM"),
  -- kept as text[] rather than re-parsed from `opening_hours_periods` for
  -- display — see TripStopLocation.openingHours.
  add column if not exists opening_hours text[],
  -- Machine-readable open/close windows behind `opening_hours`, as
  -- Places' own `periods` JSON — see TripStopLocation.openingHoursPeriods
  -- / OpeningHoursPeriod.fromJson for the shape stored here.
  add column if not exists opening_hours_periods jsonb,
  add column if not exists environment text
    check (environment in ('indoor', 'outdoor', 'mixed', 'unknown')),
  add column if not exists visit_minutes integer,

  -- Where this stop sits in the itinerary. Both null for a
  -- `trip_favorite_stops`-style row — this table is shared, but only
  -- itinerary stops (added via a day's "Add Stop") ever populate these.
  add column if not exists day_number integer check (day_number > 0),
  -- 0-indexed add/optimize order within its day.
  add column if not exists sequence integer check (sequence >= 0),

  -- Computed timeline: minutes since that day's midnight — may exceed
  -- 1440 for a plan that runs past it, matching the app's own clock
  -- arithmetic (see _minutesToClock/_computeDayTimes).
  add column if not exists arrival_minutes integer,
  add column if not exists end_minutes integer,

  -- Weather flag as of when the trip was saved — a snapshot, not a live
  -- forecast (MET Malaysia's window is only ever a few days out, so this
  -- is only ever meaningful shortly before the trip). Null
  -- `weather_checked_at` means it was never checked (indoor stop, or the
  -- day was outside the forecast window at save time).
  add column if not exists weather_flagged boolean not null default false,
  -- The DayPeriod(s) (subset of 'morning','afternoon','night') forecast
  -- as rain/thunderstorm during this stop's visit window, if any.
  add column if not exists weather_bad_periods text[] not null default '{}',
  add column if not exists weather_forecast_phrase text,
  add column if not exists weather_checked_at timestamptz,

  add constraint trip_stops_day_sequence_unique unique (trip_id, day_number, sequence);

comment on column public.trip_stops.day_number is
  'Which trip day this stop is scheduled on (1-indexed) — null for a row that is only a trip_favorite_stops-style saved place, never scheduled.';
comment on column public.trip_stops.sequence is
  '0-indexed position within day_number, in add/optimize order — the order the timeline renders stops in.';

-- ============================================================
-- trip_travel_segments: one row per travel leg actually shown in a
-- day's timeline — origin/previous-night-accommodation to the first
-- stop, stop to stop, last stop to that night's accommodation, and the
-- last day's final leg to the trip's ending location. Denormalized
-- endpoints (name + coordinates) rather than only foreign keys, since an
-- endpoint can be the trip's starting location, a night's accommodation,
-- or the trip's ending location — none of which are `trip_stops` rows —
-- as well as an actual stop.
-- ============================================================

create table if not exists public.trip_travel_segments (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  day_number integer not null check (day_number > 0),
  -- 0-indexed position within the day: segment 0 arrives at that day's
  -- first stop (or, for an empty day, straight at its accommodation);
  -- segment N (N = that day's stop count) is the trailing leg to the
  -- day's accommodation or, on the last day, to the trip's ending
  -- location.
  sequence integer not null check (sequence >= 0),

  from_name text not null,
  from_latitude double precision not null,
  from_longitude double precision not null,

  to_name text not null,
  to_latitude double precision not null,
  to_longitude double precision not null,
  -- Set only when the destination is an actual scheduled stop — null for
  -- a leg ending at accommodation or the trip's ending location.
  to_stop_id uuid references public.trip_stops (id) on delete cascade,
  leg_kind text not null check (leg_kind in ('stop', 'accommodation', 'trip_end')),

  transport_mode text not null check (transport_mode in ('driving', 'transit')),
  -- Null means the leg's travel time couldn't be computed (no Routes API
  -- result) rather than an actual zero-duration leg.
  duration_minutes integer,

  created_at timestamptz not null default now(),
  unique (trip_id, day_number, sequence)
);

-- ============================================================
-- Row Level Security — same "any trip member can read/manage" shape as
-- trip_stops/trip_accommodations already use.
-- ============================================================

alter table public.trip_days enable row level security;
alter table public.trip_travel_segments enable row level security;

create policy "trip_days_select_members" on public.trip_days
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_days_write_members" on public.trip_days
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_travel_segments_select_members" on public.trip_travel_segments
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_travel_segments_write_members" on public.trip_travel_segments
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

-- ============================================================
-- Realtime + delete-payload fix, matching the existing trip_stops entry
-- (see 0026_add_trip_stops_realtime.sql for why this guard exists —
-- `alter publication ... add table` errors instead of no-op-ing if the
-- table's already listed).
-- ============================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trip_days'
  ) then
    alter publication supabase_realtime add table public.trip_days;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trip_travel_segments'
  ) then
    alter publication supabase_realtime add table public.trip_travel_segments;
  end if;
end $$;

-- Both tables support deleting rows through the app (re-saving a trip's
-- schedule, or a future edit flow) filtered by trip_id — same DELETE-
-- payload gotcha `trip_stops`'s realtime migration documents.
alter table public.trip_days replica identity full;
alter table public.trip_travel_segments replica identity full;

-- ============================================================
-- Old hotel-anchor schedule join table — superseded by the day_number/
-- sequence/arrival_minutes/end_minutes columns added to trip_stops
-- above. Nothing in the app queries this any more.
-- ============================================================

drop table if exists public.trip_schedule_stops;
