-- Extends request_to_join() with the same two date guards
-- check_trip_date_conflict() already enforces for trip *creation*, but
-- for *joining* an existing trip via invite code instead:
--   1. The invited trip must not have already ended.
--   2. The invited trip's dates must not clash with a trip the
--      requester is already in (organizer or member) that hasn't
--      ended yet — a trip of theirs that's already over doesn't count
--      as a conflict.
-- Enforced here (server-side, authoritative) rather than only in the
-- Join Trip screen, so it can't be bypassed by a stale or buggy client.
create or replace function public.request_to_join(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_trip_id uuid;
  v_request_id uuid;
  v_start date;
  v_end date;
  v_conflict record;
begin
  select trip_id into v_trip_id
  from public.trip_invites
  where code = upper(p_code) and expires_at > now();

  if v_trip_id is null then
    raise exception 'Invalid or expired invite code';
  end if;

  if public.is_trip_member(v_trip_id) then
    raise exception 'Already a member of this trip';
  end if;

  select start_date, end_date into v_start, v_end
  from public.trips
  where id = v_trip_id;

  if v_end is not null and v_end < current_date then
    raise exception 'This trip has already ended';
  end if;

  if v_start is not null and v_end is not null then
    select t.name into v_conflict
    from public.trips t
    join public.trip_members tm on tm.trip_id = t.id
    where tm.user_id = auth.uid()
      and t.start_date is not null
      and t.end_date is not null
      and t.end_date >= current_date
      and t.start_date <= v_end
      and t.end_date >= v_start
    limit 1;

    if found then
      raise exception 'Trip dates clash with an existing trip: %', v_conflict.name;
    end if;
  end if;

  insert into public.trip_join_requests (trip_id, user_id)
  values (v_trip_id, auth.uid())
  on conflict (trip_id, user_id)
    do update set status = 'pending', created_at = now(), decided_at = null
  returning id into v_request_id;

  return v_request_id;
end;
$$;
