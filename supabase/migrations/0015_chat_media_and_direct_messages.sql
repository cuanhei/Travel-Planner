-- Chat attachments + Direct Messages.
--
-- 1. group_messages gains optional attachment columns (photo/video/voice
--    note) — body becomes optional since a media-only message has
--    nothing to say in words.
-- 2. direct_messages: a private 1:1 conversation between two members of
--    the same trip, started from the Group Travel member list. Carries
--    the same attachment columns as group_messages.
-- 3. A shared "chat-media" storage bucket for both.

-- Not dropping the old `body`-not-empty check here: once `body` allows
-- NULL, that check evaluates to NULL (not FALSE) for a media-only
-- message, and Postgres treats a NULL check result as passing — so the
-- old constraint stays harmlessly in place instead of needing to be
-- found and dropped by name.
alter table public.group_messages
  alter column body drop not null,
  add constraint group_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0
  ),
  add column attachment_type text check (attachment_type in ('image', 'video', 'audio')),
  add column attachment_url text,
  add column attachment_duration_ms integer;

-- trip_id is denormalized (as with group_message_reads) so RLS and the
-- chat screen's realtime `.stream()` can both filter on it directly;
-- the client then narrows a trip's rows down to one conversation by
-- filtering the (sender_id, recipient_id) pair itself, since realtime
-- stream filters can't express the "either direction" OR this needs.
create table public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body text,
  attachment_type text check (attachment_type in ('image', 'video', 'audio')),
  attachment_url text,
  attachment_duration_ms integer,
  created_at timestamptz not null default now(),
  constraint direct_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0
  ),
  constraint direct_messages_not_self check (sender_id <> recipient_id)
);

alter table public.direct_messages enable row level security;

create policy "direct_messages_select_participant" on public.direct_messages
  for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());

-- Both sender and recipient must actually be members of the trip the
-- conversation is scoped to (the recipient-membership check runs as
-- the sender, whose own membership the first clause already
-- established — trip_members' own "members can see their trip's
-- roster" policy lets that select through).
create policy "direct_messages_insert_participant" on public.direct_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_trip_member(trip_id)
    and exists (
      select 1 from public.trip_members
      where trip_id = direct_messages.trip_id
        and user_id = direct_messages.recipient_id
    )
  );

alter publication supabase_realtime add table public.direct_messages;

-- Full replica identity so a trip_id-filtered `.stream()` sees DELETE
-- events too, matching every other per-trip table (migration 0008/
-- 0010/0013/0014's reasoning) — direct_messages has no delete flow
-- today, but this keeps a future one safe without another migration.
alter table public.direct_messages replica identity full;

-- ============================================================
-- Storage: chat photos/videos/voice notes. Public bucket (read
-- requires no auth header) but writes are gated by RLS below, keyed
-- "<trip_id>/<file>" exactly like expense-photos.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', true)
on conflict (id) do nothing;

create policy "chat_media_select_public" on storage.objects
  for select
  using (bucket_id = 'chat-media');

create policy "chat_media_insert_members" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );
