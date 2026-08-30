-- Adds `trip_schedule_stops`: the day-by-day, timed schedule computed
-- from the optimized route (see `planDays`/`buildDaySchedule` in the
-- Flutter app). Kept separate from `trip_stops` (the raw stop catalog —
-- name/address/coordinates/category) because the same physical stop can
-- appear in more than one day's schedule (e.g. a single hotel used as
-- the base for every day of the trip) — this table is the join between
-- "which stop" and "which day, in what order, at what time".
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus 0003/0004) applied. On a brand-new project, just
-- run schema.sql — it already has this merged shape built in.

create table if not exists public.trip_schedule_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  stop_id uuid not null references public.trip_stops (id) on delete cascade,
  day_number integer not null,
  sequence integer not null,
  is_hotel boolean not null default false,
  scheduled_arrival time,
  scheduled_departure time,
  travel_mode text,
  travel_minutes integer,
  created_at timestamptz not null default now()
);

alter table public.trip_schedule_stops enable row level security;

drop policy if exists "trip_schedule_stops_select_members" on public.trip_schedule_stops;
create policy "trip_schedule_stops_select_members" on public.trip_schedule_stops
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_schedule_stops_write_members" on public.trip_schedule_stops;
create policy "trip_schedule_stops_write_members" on public.trip_schedule_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));
