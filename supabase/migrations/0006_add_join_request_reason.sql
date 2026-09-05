-- Lets the organizer attach a reason when rejecting a join request, so
-- the requester (who can already read their own `trip_join_requests`
-- row via the existing `join_requests_select` policy) can see why.
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus 0003/0004/0005) applied. On a brand-new project,
-- just run schema.sql — it already has this merged shape built in.

alter table public.trip_join_requests
  add column if not exists reason text;

create or replace function public.decide_join_request(
  p_request_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_trip_id uuid;
  v_user_id uuid;
begin
  select trip_id, user_id into v_trip_id, v_user_id
  from public.trip_join_requests
  where id = p_request_id and status = 'pending';

  if v_trip_id is null then
    raise exception 'Request not found or already decided';
  end if;
  if not public.is_trip_organizer(v_trip_id) then
    raise exception 'Only the organizer can decide join requests';
  end if;

  update public.trip_join_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      decided_at = now(),
      reason = case when p_approve then null else p_reason end
  where id = p_request_id;

  if p_approve then
    insert into public.trip_members (trip_id, user_id)
    values (v_trip_id, v_user_id)
    on conflict do nothing;
  end if;
end;
$$;
