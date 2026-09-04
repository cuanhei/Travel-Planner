-- Removes the "Auto-recommend more places" preference from Create Trip:
-- the trips.auto_recommend toggle and the trip_interests table it drove.

drop policy if exists "trip_interests_select_members" on public.trip_interests;
drop policy if exists "trip_interests_write_members" on public.trip_interests;

drop table if exists public.trip_interests;

alter table public.trips drop column if exists auto_recommend;
