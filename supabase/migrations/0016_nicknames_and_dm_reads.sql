-- Per-trip nicknames (Group Chat's "Change Nickname" setting) and
-- direct-message last-read tracking (Personal Message unread badge).

alter table public.trip_members add column nickname text;

-- Lets a member set their own nickname for one trip without a raw
-- column-update RLS policy (which would otherwise also need to guard
-- against changing `role`) — security definer, touches only the
-- caller's own row.
create function public.set_my_trip_nickname(p_trip_id uuid, p_nickname text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.trip_members
  set nickname = nullif(trim(p_nickname), '')
  where trip_id = p_trip_id and user_id = auth.uid();
end;
$$;

-- Direct Messages have no per-message read receipts (unlike group
-- chat) — just a single "I've seen this conversation up to here"
-- marker per (trip, viewer, other member), enough to drive the
-- Personal Message unread-count badge without tracking every message
-- individually.
create table public.direct_message_reads (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  other_user_id uuid not null references auth.users (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (trip_id, user_id, other_user_id)
);

alter table public.direct_message_reads enable row level security;

create policy "direct_message_reads_select_own" on public.direct_message_reads
  for select to authenticated using (user_id = auth.uid());
create policy "direct_message_reads_insert_own" on public.direct_message_reads
  for insert to authenticated with check (user_id = auth.uid());
create policy "direct_message_reads_update_own" on public.direct_message_reads
  for update to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.direct_message_reads;
alter table public.direct_message_reads replica identity full;
