-- Accommodation is picked per night (after Create Trip's date picker),
-- not once for the whole trip — a trip spanning N days needs an
-- accommodation for nights 1..N-1 (none for a single-day trip).

create table public.trip_accommodations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  night_number integer not null check (night_number > 0),
  name text not null,
  address text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  unique (trip_id, night_number)
);

alter table public.trip_accommodations enable row level security;

create policy "trip_accommodations_select_members" on public.trip_accommodations
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_accommodations_write_members" on public.trip_accommodations
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));
