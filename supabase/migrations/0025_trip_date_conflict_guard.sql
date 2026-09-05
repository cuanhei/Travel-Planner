-- Server-side guarantee that a trip's dates never overlap another trip
-- its creator already organizes or belongs to (inclusive on both ends).
-- The Create Trip date picker already prevents picking a clashing range
-- and re-checks right before submit, but this is the authoritative
-- backstop — it's what actually rejects the insert if that client-side
-- check is ever bypassed, buggy, or loses a race (two trips created back
-- to back).

create function public.check_trip_date_conflict()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_conflict record;
begin
  if new.start_date is null or new.end_date is null then
    return new;
  end if;

  select t.name into v_conflict
  from public.trips t
  join public.trip_members tm on tm.trip_id = t.id
  where tm.user_id = new.created_by
    and t.id <> new.id
    and t.start_date is not null
    and t.end_date is not null
    and t.start_date <= new.end_date
    and t.end_date >= new.start_date
  limit 1;

  if found then
    raise exception 'Trip dates clash with an existing trip: %', v_conflict.name;
  end if;

  return new;
end;
$$;

create trigger trips_check_date_conflict
  before insert or update of start_date, end_date on public.trips
  for each row execute function public.check_trip_date_conflict();
