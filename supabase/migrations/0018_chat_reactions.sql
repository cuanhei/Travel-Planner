-- Message reactions (WhatsApp-style emoji react) for both Group Chat
-- and Direct Messages. One reaction per user per message — reacting
-- again with a different emoji replaces it (upsert), reacting with the
-- same one again removes it (the app issues a delete for that case).

create table public.group_message_reactions (
  message_id uuid not null references public.group_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.group_message_reactions enable row level security;

create policy "group_message_reactions_select_members" on public.group_message_reactions
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "group_message_reactions_insert_own" on public.group_message_reactions
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
create policy "group_message_reactions_update_own" on public.group_message_reactions
  for update to authenticated using (user_id = auth.uid());
create policy "group_message_reactions_delete_own" on public.group_message_reactions
  for delete to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.group_message_reactions;
alter table public.group_message_reactions replica identity full;

-- direct_message_reactions has no trip_members roster to lean on for
-- its RLS boundary (a DM conversation is just two people, not "the
-- trip") — instead it checks that the reactor is a participant of the
-- specific message being reacted to, via direct_messages itself (whose
-- own select policy already restricts a lookup like this to rows the
-- current user sends or receives). trip_id is still carried here
-- (denormalized, as on direct_messages) purely so the client can
-- `.stream().eq('trip_id', ...)` instead of no filter at all.
create table public.direct_message_reactions (
  message_id uuid not null references public.direct_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.direct_message_reactions enable row level security;

create policy "direct_message_reactions_select_participant" on public.direct_message_reactions
  for select to authenticated
  using (
    exists (
      select 1 from public.direct_messages dm
      where dm.id = message_id
        and (dm.sender_id = auth.uid() or dm.recipient_id = auth.uid())
    )
  );
create policy "direct_message_reactions_insert_own" on public.direct_message_reactions
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.direct_messages dm
      where dm.id = message_id
        and (dm.sender_id = auth.uid() or dm.recipient_id = auth.uid())
    )
  );
create policy "direct_message_reactions_update_own" on public.direct_message_reactions
  for update to authenticated using (user_id = auth.uid());
create policy "direct_message_reactions_delete_own" on public.direct_message_reactions
  for delete to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.direct_message_reactions;
alter table public.direct_message_reactions replica identity full;
