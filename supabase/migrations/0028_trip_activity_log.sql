-- Group activity feed — currently just membership changes (joined /
-- left), shown as WhatsApp-style inline system messages in Group Chat
-- and listed in full from its "History" menu entry. Populated purely
-- by triggers on trip_members, never written to directly by the app,
-- so it can't drift from what actually happened to the roster.
create table public.trip_activity_log (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  event_type text not null check (event_type in ('joined', 'left')),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.trip_activity_log enable row level security;

create policy "trip_activity_log_select_members" on public.trip_activity_log
  for select to authenticated using (public.is_trip_member(trip_id));

-- Writes only ever come from the triggers below (security definer, so
-- they bypass RLS on this table entirely) — no insert/update/delete
-- policy is needed, or wanted, for direct client writes.

create function public.log_trip_member_joined()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.trip_activity_log (trip_id, event_type, user_id)
  values (new.trip_id, 'joined', new.user_id);
  return new;
end;
$$;

create trigger trip_members_log_joined
  after insert on public.trip_members
  for each row execute function public.log_trip_member_joined();

create function public.log_trip_member_left()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.trip_activity_log (trip_id, event_type, user_id)
  values (old.trip_id, 'left', old.user_id);
  return old;
end;
$$;

create trigger trip_members_log_left
  after delete on public.trip_members
  for each row execute function public.log_trip_member_left();

-- Required for GroupService.watchActivityLog()'s `.stream()` to ever
-- emit anything — every table read that way must be in this
-- publication (see the note next to it in schema.sql).
alter publication supabase_realtime add table public.trip_activity_log;
