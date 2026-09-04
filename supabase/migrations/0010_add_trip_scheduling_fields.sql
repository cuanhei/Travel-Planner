-- Adds the columns/tables the constraint-based trip-scheduling engine
-- needs (see trip_planning_and_stop_scheduling_flow.md):
--   * `trip_stops` gains Places-sourced scheduling data (place_id for
--     re-fetching fresh hours/status, structured opening_periods,
--     rating/business status) plus app-level scheduling fields
--     (visit_purpose, meal_type, environment_type,
--     estimated_visit_duration_minutes) that are independent of
--     `category` — the same HOTEL-category place can be
--     visit_purpose='accommodation' (the overnight stay) or
--     visit_purpose='meal' (picked just for its buffet).
--   * `trips` gains transport_mode and accommodation_mode (which of the
--     3 Create Trip accommodation choices was made).
--   * new `trip_accommodations`: one row per night, since accommodation
--     is assignable per-night (a trip can use a different hotel on
--     different nights) — `trip_schedule_stops.is_hotel` alone can't
--     express *which night* a stop is the anchor for.
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus prior migrations) applied. On a brand-new project,
-- just run schema.sql — it already has this merged shape built in.

alter table public.trip_stops
  add column if not exists place_id text,
  add column if not exists visit_purpose text not null default 'attraction'
    check (visit_purpose in ('accommodation', 'meal', 'attraction', 'shopping', 'transport', 'other')),
  add column if not exists meal_type text
    check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack')),
  add column if not exists environment_type text
    check (environment_type in ('indoor', 'outdoor', 'mixed')),
  add column if not exists estimated_visit_duration_minutes integer not null default 60,
  add column if not exists rating numeric(2, 1),
  add column if not exists user_rating_count integer,
  add column if not exists business_status text,
  add column if not exists opening_periods jsonb;

alter table public.trips
  add column if not exists transport_mode text
    check (transport_mode in ('walk', 'drive', 'public_transport', 'mixed')),
  add column if not exists accommodation_mode text not null default 'none'
    check (accommodation_mode in ('none', 'add_mine', 'recommend', 'skip'));

create table if not exists public.trip_accommodations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  stop_id uuid not null references public.trip_stops (id) on delete cascade,
  night_date date not null,
  created_at timestamptz not null default now(),
  unique (trip_id, night_date)
);

alter table public.trip_accommodations enable row level security;

drop policy if exists "trip_accommodations_select_members" on public.trip_accommodations;
create policy "trip_accommodations_select_members" on public.trip_accommodations
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_accommodations_write_members" on public.trip_accommodations;
create policy "trip_accommodations_write_members" on public.trip_accommodations
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));
