-- Apply after 0011. All itinerary changes commit in one transaction. An
-- optimistic revision rejects a stale editor; operation IDs make retries safe.
alter table public.trips
  add column if not exists schedule_revision integer not null default 0;
alter table public.trip_schedule_stops
  add column if not exists scheduled_visit_start time;

create table if not exists public.trip_schedule_operations (
  trip_id uuid not null references public.trips(id) on delete cascade,
  operation_id uuid not null,
  revision integer not null,
  payload jsonb not null,
  primary key (trip_id, operation_id)
);
alter table public.trip_schedule_operations enable row level security;
-- Only the checked functions below can access operation receipts.

create table if not exists public.trip_schedule_days (
  trip_id uuid not null references public.trips(id) on delete cascade,
  day_number integer not null check (day_number > 0),
  start_stop_id uuid references public.trip_stops(id) on delete set null,
  end_stop_id uuid references public.trip_stops(id) on delete set null,
  daily_start time not null,
  daily_end time not null,
  return_travel_minutes integer,
  end_anchor_reachable boolean not null default true,
  primary key (trip_id, day_number)
);
alter table public.trip_schedule_days enable row level security;
drop policy if exists "trip_schedule_days_select_members" on public.trip_schedule_days;
create policy "trip_schedule_days_select_members" on public.trip_schedule_days
  for select to authenticated using (public.is_trip_member(trip_id));

create or replace function public.commit_trip_schedule(
  p_trip_id uuid, p_expected_revision integer, p_operation_id uuid,
  p_rows jsonb, p_new_stops jsonb default '[]',
  p_deleted_stop_ids uuid[] default '{}', p_recommendation boolean default false,
  p_days jsonb default '[]'
) returns integer language plpgsql security definer set search_path = public
as $$
declare
  v_revision integer;
  v_receipt public.trip_schedule_operations%rowtype;
  v_payload jsonb := jsonb_build_object('rows', p_rows, 'stops', p_new_stops,
    'deleted', p_deleted_stop_ids, 'recommendation', p_recommendation, 'days', p_days);
begin
  if auth.uid() is null or not public.is_trip_member(p_trip_id) then
    raise exception 'You do not have access to this trip.' using errcode = '42501';
  end if;
  select schedule_revision into strict v_revision from public.trips
    where id = p_trip_id for update;
  select * into v_receipt from public.trip_schedule_operations
    where trip_id = p_trip_id and operation_id = p_operation_id;
  if found then
    if v_receipt.payload <> v_payload then
      raise exception 'This save request has already been used for different changes.';
    end if;
    return v_receipt.revision;
  end if;
  if p_expected_revision is null or p_expected_revision <> v_revision then
    raise exception 'This itinerary changed elsewhere. Reopen it before saving.' using errcode = '40001';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_typeof(p_new_stops) <> 'array' then
    raise exception 'Invalid itinerary payload.';
  end if;
  if p_recommendation and exists (
    select 1 from jsonb_array_elements(p_new_stops) s
    join public.trip_stops t on t.trip_id = p_trip_id and (
      (nullif(s->>'place_id', '') is not null and t.place_id = s->>'place_id') or
      (nullif(s->>'place_id', '') is null and t.place_id is null and
       lower(trim(t.name)) = lower(trim(s->>'name')) and
       round(t.latitude::numeric, 5) = round((s->>'latitude')::numeric, 5) and
       round(t.longitude::numeric, 5) = round((s->>'longitude')::numeric, 5)))) then
    raise exception 'This place is already on your trip.' using errcode = '23505';
  end if;
  insert into public.trip_stops (id, trip_id, name, address, latitude, longitude,
    osm_id, category, place_id, visit_purpose, meal_type, environment_type,
    estimated_visit_duration_minutes, rating, user_rating_count, business_status, opening_periods)
  select s.id, p_trip_id, s.name, s.address, s.latitude, s.longitude,
    s.osm_id, s.category, s.place_id, s.visit_purpose, s.meal_type, s.environment_type,
    s.estimated_visit_duration_minutes, s.rating, s.user_rating_count, s.business_status, s.opening_periods
  from jsonb_to_recordset(p_new_stops) as s(id uuid, name text, address text,
    latitude double precision, longitude double precision, osm_id text,
    category text, place_id text, visit_purpose text, meal_type text,
    environment_type text, estimated_visit_duration_minutes integer,
    rating numeric, user_rating_count integer, business_status text, opening_periods jsonb);
  if exists (select 1 from jsonb_array_elements(p_rows) r
    where not exists (select 1 from public.trip_stops s
      where s.id = (r->>'stop_id')::uuid and s.trip_id = p_trip_id)
      or (r->>'stop_id')::uuid = any(p_deleted_stop_ids)) then
    raise exception 'A scheduled stop does not belong to this trip or was removed.';
  end if;
  if exists (select 1 from public.trips where id = p_trip_id and
      (start_location_stop_id = any(p_deleted_stop_ids) or end_location_stop_id = any(p_deleted_stop_ids)))
      or exists (select 1 from public.trip_accommodations where trip_id = p_trip_id
        and stop_id = any(p_deleted_stop_ids)) then
    raise exception 'Remove accommodation and location anchors through trip settings.';
  end if;
  delete from public.trip_schedule_stops where trip_id = p_trip_id;
  insert into public.trip_schedule_stops (trip_id, stop_id, day_number, sequence,
    is_hotel, scheduled_arrival, scheduled_visit_start, scheduled_departure, travel_mode, travel_minutes)
  select p_trip_id, r.stop_id, r.day_number, r.sequence, r.is_hotel,
    r.scheduled_arrival, r.scheduled_visit_start, r.scheduled_departure, r.travel_mode, r.travel_minutes
  from jsonb_to_recordset(p_rows) as r(stop_id uuid, day_number integer, sequence integer,
    is_hotel boolean, scheduled_arrival time, scheduled_visit_start time,
    scheduled_departure time, travel_mode text, travel_minutes integer);
  if exists (select 1 from jsonb_array_elements(p_days) d,
      lateral (values (d->>'start_stop_id'), (d->>'end_stop_id')) a(id)
      where a.id is not null and not exists (select 1 from public.trip_stops s
        where s.id = a.id::uuid and s.trip_id = p_trip_id)) then
    raise exception 'A day anchor does not belong to this trip.';
  end if;
  delete from public.trip_schedule_days where trip_id = p_trip_id;
  insert into public.trip_schedule_days (trip_id, day_number, start_stop_id,
    end_stop_id, daily_start, daily_end, return_travel_minutes, end_anchor_reachable)
  select p_trip_id, d.day_number, d.start_stop_id, d.end_stop_id,
    d.daily_start, d.daily_end, d.return_travel_minutes, d.end_anchor_reachable
  from jsonb_to_recordset(p_days) as d(day_number integer, start_stop_id uuid,
    end_stop_id uuid, daily_start time, daily_end time, return_travel_minutes integer,
    end_anchor_reachable boolean);
  delete from public.trip_stops where trip_id = p_trip_id and id = any(p_deleted_stop_ids);
  update public.trips set schedule_revision = schedule_revision + 1
    where id = p_trip_id returning schedule_revision into v_revision;
  insert into public.trip_schedule_operations values (p_trip_id, p_operation_id, v_revision, v_payload);
  return v_revision;
end;
$$;
revoke all on function public.commit_trip_schedule(uuid, integer, uuid, jsonb, jsonb, uuid[], boolean, jsonb) from public;
grant execute on function public.commit_trip_schedule(uuid, integer, uuid, jsonb, jsonb, uuid[], boolean, jsonb) to authenticated;

-- Generation is performed in memory before this RPC. A failure rolls back the
-- trip, membership trigger, stops, accommodation, interests and schedule together.
create or replace function public.create_planned_trip(
  p_trip_id uuid, p_trip jsonb, p_stops jsonb, p_rows jsonb,
  p_interests text[], p_accommodations jsonb, p_days jsonb
) returns uuid language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in to create a trip.' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_trip_id::text, 0));
  if exists (select 1 from public.trips where id = p_trip_id and created_by = auth.uid()) then
    return p_trip_id;
  end if;
  insert into public.trips (id, name, description, destination, start_city, end_city,
    start_date, end_date, start_time, end_time, total_budget, auto_recommend,
    transport_mode, accommodation_mode, created_by)
  values (p_trip_id, p_trip->>'name', p_trip->>'description', coalesce(p_trip->>'destination',''),
    p_trip->>'start_city', p_trip->>'end_city', (p_trip->>'start_date')::date,
    (p_trip->>'end_date')::date, (p_trip->>'start_time')::time, (p_trip->>'end_time')::time,
    (p_trip->>'total_budget')::numeric, (p_trip->>'auto_recommend')::boolean,
    p_trip->>'transport_mode', p_trip->>'accommodation_mode', auth.uid());
  perform public.commit_trip_schedule(p_trip_id, 0, p_trip_id, p_rows, p_stops, '{}', false, p_days);
  if exists (select 1 from jsonb_array_elements(p_accommodations) a where not exists
    (select 1 from public.trip_stops s where s.trip_id = p_trip_id and s.id = (a->>'stop_id')::uuid))
    or exists (select 1 from jsonb_each_text(jsonb_build_object(
      'start', p_trip->>'start_location_stop_id', 'end', p_trip->>'end_location_stop_id')) a
      where a.value is not null and not exists (select 1 from public.trip_stops s
        where s.trip_id = p_trip_id and s.id = a.value::uuid)) then
    raise exception 'Invalid accommodation or location anchor.';
  end if;
  update public.trips set start_location_stop_id = (p_trip->>'start_location_stop_id')::uuid,
    end_location_stop_id = (p_trip->>'end_location_stop_id')::uuid where id = p_trip_id;
  insert into public.trip_accommodations (trip_id, stop_id, night_date)
    select p_trip_id, (a->>'stop_id')::uuid, (a->>'night_date')::date
    from jsonb_array_elements(p_accommodations) a;
  insert into public.trip_interests (trip_id, category)
    select p_trip_id, unnest(p_interests);
  return p_trip_id;
end;
$$;
revoke all on function public.create_planned_trip(uuid, jsonb, jsonb, jsonb, text[], jsonb, jsonb) from public;
grant execute on function public.create_planned_trip(uuid, jsonb, jsonb, jsonb, text[], jsonb, jsonb) to authenticated;
