-- Starting From / Ending At now pick a real, geocoded location (Photon
-- search, same as the Locations picker) instead of a city from a fixed
-- Malaysian city list — replaces the city/state text columns with a
-- name/address/coordinates shape matching trip_stops.

alter table public.trips
  add column if not exists start_location_name text,
  add column if not exists start_address text,
  add column if not exists start_latitude double precision,
  add column if not exists start_longitude double precision,
  add column if not exists end_location_name text,
  add column if not exists end_address text,
  add column if not exists end_latitude double precision,
  add column if not exists end_longitude double precision;

update public.trips set start_location_name = start_city where start_city is not null;
update public.trips set end_location_name = end_city where end_city is not null;

alter table public.trips
  drop column if exists start_city,
  drop column if exists start_state,
  drop column if exists end_city,
  drop column if exists end_state;
