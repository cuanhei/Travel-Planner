-- Lets the Join Trip screen preview which trip an invite code points to
-- (name, destination, dates) *before* actually filing a join request —
-- needed so the client can warn about a joined trip that's already
-- over, or one whose dates overlap a trip the requester is already in,
-- without needing direct SELECT on `trips`/`trip_invites` (which would
-- otherwise leak every trip's details/active codes). Read-only sibling
-- of request_to_join(): same code/expiry lookup, but never inserts a
-- join request and never raises for an unknown/expired code — it just
-- returns no rows, so a bad code can't be distinguished from an expired
-- one by probing this function alone.
create function public.get_trip_preview_by_code(p_code text)
returns table (
  trip_id uuid,
  name text,
  destination text,
  start_date date,
  end_date date
)
language sql
security definer set search_path = public
as $$
  select t.id, t.name, t.destination, t.start_date, t.end_date
  from public.trip_invites i
  join public.trips t on t.id = i.trip_id
  where i.code = upper(p_code) and i.expires_at > now();
$$;
