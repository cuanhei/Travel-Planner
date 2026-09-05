-- Chat background choice ("Change Background" in Group Chat / Personal
-- Message settings) — moved from local device storage to the database:
-- a purely local (SharedPreferences) preference doesn't survive a
-- reinstall and isn't guaranteed to persist reliably on every platform
-- (e.g. a plugin that isn't wired in without a full rebuild after being
-- added), and doesn't follow the user to a second device either.
--
-- conversation_id is the same string the app already used as its local
-- storage key — a trip's id for Group Chat, or "<tripId>/dm/<otherUserId>"
-- for a Direct Message — so it's still just an opaque per-conversation
-- key, not a real foreign key to any single table.
create table public.chat_background_preferences (
  user_id uuid not null references auth.users (id) on delete cascade,
  conversation_id text not null,
  background_key text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.chat_background_preferences enable row level security;

-- Purely personal — never visible to, or writable by, anyone else.
create policy "chat_background_preferences_own" on public.chat_background_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
