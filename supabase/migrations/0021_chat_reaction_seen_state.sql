-- Tracks, per user and per conversation, the cutoff up to which the
-- "so-and-so reacted to your message" in-chat toast has already been
-- shown — so it fires exactly once per reaction (the moment it's first
-- seen) instead of replaying every existing reaction each time the
-- chat is reopened. Server-side (not local device storage) for the
-- same reason as chat_background_preferences: it needs to survive a
-- reinstall and follow the signed-in user to another device.
--
-- conversation_id is the same opaque key already used for
-- chat_background_preferences — a trip's id for Group Chat, or
-- "<tripId>/dm/<otherUserId>" for a Direct Message.
create table public.chat_reaction_seen_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  conversation_id text not null,
  last_seen_at timestamptz not null,
  primary key (user_id, conversation_id)
);

alter table public.chat_reaction_seen_state enable row level security;

-- Purely personal — never visible to, or writable by, anyone else.
create policy "chat_reaction_seen_state_own" on public.chat_reaction_seen_state
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
