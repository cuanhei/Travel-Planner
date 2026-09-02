-- Extends the already-live `public.trips` table with the remaining fields
-- captured by the Create Trip form (description, start/end city, start/end
-- time, and whether auto-recommend is on), and adds two new trip-scoped
-- tables: one row per stop picked via the real map/search
-- (`trip_stops`), and one row per selected interest category
-- (`trip_interests`).
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus 0003) applied. On a brand-new project, just run
-- schema.sql — it already has this merged shape built in.

alter table public.trips
  add column if not exists description text,
  add column if not exists start_city text,
  add column if not exists start_state text,
  add column if not exists end_city text,
  add column if not exists end_state text,
  add column if not exists start_time time,
  add column if not exists end_time time,
  add column if not exists auto_recommend boolean not null default true;

create table if not exists public.trip_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  name text not null,
  address text not null,
  latitude double precision not null,
  longitude double precision not null,
  osm_id text,
  category text not null default 'Other',
  created_at timestamptz not null default now()
);

create table if not exists public.trip_interests (
  trip_id uuid not null references public.trips (id) on delete cascade,
  category text not null,
  primary key (trip_id, category)
);

alter table public.trip_stops enable row level security;
alter table public.trip_interests enable row level security;

drop policy if exists "trip_stops_select_members" on public.trip_stops;
create policy "trip_stops_select_members" on public.trip_stops
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_stops_write_members" on public.trip_stops;
create policy "trip_stops_write_members" on public.trip_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

drop policy if exists "trip_interests_select_members" on public.trip_interests;
create policy "trip_interests_select_members" on public.trip_interests
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_interests_write_members" on public.trip_interests;
create policy "trip_interests_write_members" on public.trip_interests
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));
