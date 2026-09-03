-- Adds `trip_favorite_stops`: per-trip "quick" stops a traveler saves for
-- fast directions — e.g. a nearby 7-Eleven or pharmacy they'll want to nip
-- to during the trip, not a must-visit itinerary stop. Same row shape as
-- `trip_stops` (name/address/coordinates/category) but a separate table:
-- these aren't itinerary stops and must never show up on the trip map or
-- schedule. Each trip has its own independent favourite-stop list.
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus prior migrations) applied. On a brand-new project,
-- just run schema.sql — it already has this merged shape built in.

create table if not exists public.trip_favorite_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  name text not null,
  address text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  osm_id text,
  category text not null default 'Other',
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

alter table public.trip_favorite_stops enable row level security;

drop policy if exists "trip_favorite_stops_select_members" on public.trip_favorite_stops;
create policy "trip_favorite_stops_select_members" on public.trip_favorite_stops
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_favorite_stops_write_members" on public.trip_favorite_stops;
create policy "trip_favorite_stops_write_members" on public.trip_favorite_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));
