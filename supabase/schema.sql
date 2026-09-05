-- TravelPlanner: Budget + Group module schema
-- Run this once against a fresh Supabase project (SQL Editor, or `supabase db push`).
-- Depends only on Supabase's built-in `auth.users` — safe to run before the
-- Trip Planner / Auth teammates add their own tables. If a `trips` table
-- already exists with a different shape, drop the minimal one below and
-- point the foreign keys at theirs instead.

create extension if not exists pgcrypto;

-- ============================================================
-- Identity + trips (minimal, so Budget/Group have something to hang off)
-- ============================================================

-- display_name/avatar_color are read by the Group module (member names,
-- chat senders, join requests); full_name/email/avatar_url are owned by
-- the Authentication module. One table, one trigger, both populated —
-- see supabase/migrations/0001_add_auth_profile_fields.sql if you already
-- ran an earlier version of this schema against a live project.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_color integer not null default -6543440, -- 0xFF9C4870, arbitrary default
  full_name text,
  email text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create a profile row whenever a new auth user signs up. Re-run
-- (via `AuthService.signUp`'s `data: {'full_name': ...}`) also keeps
-- full_name/email current without ever touching display_name/avatar_color.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, full_name, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'display_name',
      split_part(new.email, '@', 1)
    ),
    new.raw_user_meta_data ->> 'full_name',
    new.email
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        updated_at = now();
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep `updated_at` current on every edit (e.g. AuthService.updatePassword
-- doesn't touch this table, but future profile-edit features will).
create function public.handle_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger on_profiles_updated
  before update on public.profiles
  for each row execute function public.handle_profile_updated_at();

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  destination text not null default '',
  start_city text,
  start_state text,
  end_city text,
  end_state text,
  start_date date,
  end_date date,
  start_time time,
  end_time time,
  created_by uuid not null references auth.users (id),
  total_budget numeric(12, 2) not null default 0,
  auto_recommend boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.trip_members (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('organizer', 'member')),
  -- Per-trip display alias for Group Chat, set via
  -- set_my_trip_nickname() below — null means "show my profile name".
  nickname text,
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- Creating a trip makes you its organizer.
create function public.handle_new_trip()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.trip_members (trip_id, user_id, role)
  values (new.id, new.created_by, 'organizer');
  return new;
end;
$$;

create trigger on_trip_created
  after insert on public.trips

  for each row execute function public.handle_new_trip();

-- Membership check used by every trip-scoped RLS policy below.
-- security definer + a fixed search_path avoids recursive-RLS lookups.
create function public.is_trip_member(p_trip_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.trip_members
    where trip_id = p_trip_id and user_id = auth.uid()
  );
$$;

create function public.is_trip_organizer(p_trip_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.trip_members
    where trip_id = p_trip_id and user_id = auth.uid() and role = 'organizer'
  );
$$;

-- Group activity feed — currently just membership changes (joined /
-- left), shown as WhatsApp-style inline system messages in Group Chat
-- and listed in full from its "History" menu entry. Populated purely
-- by triggers below, never written to directly by the app, so it can't
-- drift from what actually happened to the roster.
create table public.trip_activity_log (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  event_type text not null check (event_type in ('joined', 'left')),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

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

-- ============================================================
-- Trip Planner module: stops and interests captured by Create Trip
-- ============================================================

-- One row per stop picked via the real map/search (Stop Selection).
create table public.trip_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  name text not null,
  address text not null,
  latitude double precision not null,
  longitude double precision not null,
  osm_id text,
  category text not null default 'Other',
  created_at timestamptz not null default now()
);

-- One row per selected "auto-recommend" interest category.
create table public.trip_interests (
  trip_id uuid not null references public.trips (id) on delete cascade,
  category text not null,
  primary key (trip_id, category)
);

-- The day-by-day, timed schedule computed from the optimized route. Kept
-- separate from `trip_stops` because the same physical stop (e.g. one
-- hotel used as the base for every day) can appear in more than one
-- day's schedule — this is the join between "which stop", "which day, in
-- what order", and "at what time".
create table public.trip_schedule_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  stop_id uuid not null references public.trip_stops (id) on delete cascade,
  day_number integer not null,
  sequence integer not null,
  is_hotel boolean not null default false,
  scheduled_arrival time,
  scheduled_departure time,
  travel_mode text,
  travel_minutes integer,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Group module: invites, join requests, chat, polls
-- ============================================================

create table public.trip_invites (
  code text primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  created_by uuid not null references auth.users (id),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.trip_join_requests (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  -- Organizer's note on why a request was rejected, shown back to the
  -- requester (who can read their own row — see join_requests_select).
  reason text,
  unique (trip_id, user_id)
);

-- Requester calls this with the code they were given; validates it and
-- files a join request without needing direct SELECT on trip_invites
-- (which would otherwise leak every trip's active codes). Also enforces
-- the same two date guards check_trip_date_conflict() enforces for trip
-- *creation*, but for *joining* instead: the invited trip must not have
-- already ended, and its dates must not clash with a trip the requester
-- is already in (organizer or member) that hasn't ended yet.
create function public.request_to_join(p_code text)
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

-- Resolves an invite code to a trip_id, but only when the caller is
-- already a member of that trip — used by the Join Trip screen to send
-- someone straight to Trip Details when they enter a code for a trip
-- they're already in, instead of leaving them stuck on a raw error.
-- Returns null (never raises) for anyone else, so it can't be used to
-- probe which trip a code belongs to.
create function public.find_my_trip_by_code(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_trip_id uuid;
begin
  select trip_id into v_trip_id
  from public.trip_invites
  where code = upper(p_code);

  if v_trip_id is null or not public.is_trip_member(v_trip_id) then
    return null;
  end if;

  return v_trip_id;
end;
$$;

-- Lets the Join Trip screen preview which trip an invite code points to
-- (name, destination, dates) *before* actually filing a join request —
-- needed to warn about a joined trip that's already over, or one whose
-- dates overlap a trip the requester is already in. Read-only sibling
-- of request_to_join(): same code/expiry lookup, but never inserts a
-- join request and never raises for an unknown/expired code — it just
-- returns no rows.
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

-- Organizer-only: approve or reject a pending request. [p_reason] is the
-- organizer's note shown to the requester when rejecting; ignored (and
-- not stored) on approval.
create function public.decide_join_request(
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

-- body is nullable: a media-only message (photo/video/voice note) has
-- nothing to say in words, so it's the content-check below — not a
-- not-null constraint — that guarantees a message is never truly empty.
create table public.group_messages (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text,
  attachment_type text check (attachment_type in ('image', 'video', 'audio')),
  attachment_url text,
  attachment_duration_ms integer,
  created_at timestamptz not null default now(),
  -- Reply/quote — the quoted message's own snippet (body/sender) is
  -- resolved client-side from its id, same as sender profiles are.
  reply_to_id uuid references public.group_messages (id) on delete set null,
  edited_at timestamptz,
  -- Soft delete ("delete for everyone"): body/attachment are cleared
  -- and deleted_at set, rather than removing the row outright, so the
  -- chat can still show a "This message was deleted" placeholder in
  -- its place instead of the message just vanishing.
  deleted_at timestamptz,
  mentioned_user_ids uuid[] not null default '{}',
  pinned_at timestamptz,
  constraint group_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0 or deleted_at is not null
  )
);

-- Read receipts for group_messages — trip_id is denormalized (rather
-- than joined through group_messages) so RLS and the chat screen's
-- realtime `.stream()` can both filter directly on it, same as every
-- other per-trip table.
create table public.group_message_reads (
  message_id uuid not null references public.group_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Direct Messages: a private 1:1 conversation between two members of
-- the same trip, started from the Group Travel member list. trip_id is
-- denormalized (as with group_message_reads) so RLS and `.stream()`
-- can both filter on it directly; the client narrows a trip's rows
-- down to one conversation by filtering the (sender_id, recipient_id)
-- pair itself, since realtime stream filters can't express the
-- "either direction" OR that would otherwise take.
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
  reply_to_id uuid references public.direct_messages (id) on delete set null,
  edited_at timestamptz,
  deleted_at timestamptz,
  pinned_at timestamptz,
  constraint direct_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0 or deleted_at is not null
  ),
  constraint direct_messages_not_self check (sender_id <> recipient_id)
);

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

-- Pinning is the one message action any trip member can take on a
-- message that isn't theirs, so it can't go through the "own row"
-- update policies (messages_update_own / direct_messages_update_own)
-- below — routed through these instead. Passing a null p_message_id
-- just unpins whatever's currently pinned; passing one pins it and
-- unpins whatever was pinned before (only one pin per conversation at
-- a time).
create function public.set_pinned_group_message(p_trip_id uuid, p_message_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_trip_member(p_trip_id) then
    raise exception 'Not a member of this trip';
  end if;
  if p_message_id is not null and not exists (
    select 1 from public.group_messages
    where id = p_message_id and trip_id = p_trip_id and deleted_at is null
  ) then
    raise exception 'Message not found in this trip';
  end if;

  update public.group_messages
  set pinned_at = null
  where trip_id = p_trip_id and pinned_at is not null;

  if p_message_id is not null then
    update public.group_messages
    set pinned_at = now()
    where id = p_message_id;
  end if;
end;
$$;

-- Same idea for a DM: p_message_id null unpins; otherwise pins it
-- (unpinning whatever was pinned in that same conversation before) —
-- the conversation is identified by the message's own sender/recipient
-- once resolved, so the caller only ever needs to be one of the two
-- participants of whichever message is involved.
create function public.set_pinned_direct_message(
  p_trip_id uuid,
  p_other_user_id uuid,
  p_message_id uuid
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_sender uuid;
  v_recipient uuid;
begin
  if p_message_id is not null then
    select sender_id, recipient_id into v_sender, v_recipient
    from public.direct_messages
    where id = p_message_id and deleted_at is null;

    if v_sender is null then
      raise exception 'Message not found';
    end if;
    if auth.uid() not in (v_sender, v_recipient) then
      raise exception 'Not a participant of this conversation';
    end if;
  end if;

  update public.direct_messages
  set pinned_at = null
  where trip_id = p_trip_id
    and pinned_at is not null
    and ((sender_id = auth.uid() and recipient_id = p_other_user_id)
      or (sender_id = p_other_user_id and recipient_id = auth.uid()));

  if p_message_id is not null then
    update public.direct_messages
    set pinned_at = now()
    where id = p_message_id;
  end if;
end;
$$;

-- Message reactions (WhatsApp-style emoji react). One reaction per
-- user per message — reacting again with a different emoji replaces
-- it (upsert); the same emoji again removes it (the app issues a
-- delete for that case).
create table public.group_message_reactions (
  message_id uuid not null references public.group_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- direct_message_reactions has no trip_members roster to lean on for
-- its RLS boundary (a DM conversation is just two people, not "the
-- trip") — its select/insert policies instead check the reactor is a
-- participant of the specific message via direct_messages itself.
-- trip_id is still carried here (denormalized, as on direct_messages)
-- purely so the client can `.stream().eq('trip_id', ...)`.
create table public.direct_message_reactions (
  message_id uuid not null references public.direct_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Chat background choice ("Change Background" in Group Chat / Personal
-- Message settings). conversation_id is an opaque per-conversation key
-- (a trip's id for Group Chat, or "<tripId>/dm/<otherUserId>" for a
-- Direct Message) — not a real foreign key to any single table.
create table public.chat_background_preferences (
  user_id uuid not null references auth.users (id) on delete cascade,
  conversation_id text not null,
  background_key text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

-- Tracks, per user and per conversation, the cutoff up to which the
-- "so-and-so reacted to your message" in-chat toast has already been
-- shown — so it fires exactly once per reaction instead of replaying
-- every existing reaction each time the chat is reopened. Same opaque
-- conversation_id scheme as chat_background_preferences.
create table public.chat_reaction_seen_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  conversation_id text not null,
  last_seen_at timestamptz not null,
  primary key (user_id, conversation_id)
);

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  question text not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls (id) on delete cascade,
  label text not null,
  position integer not null default 0
);

create table public.poll_votes (
  poll_id uuid not null references public.polls (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  option_id uuid not null references public.poll_options (id) on delete cascade,
  voted_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);

-- ============================================================
-- Budget module: categories, expenses, balances
-- ============================================================

create table public.budget_categories (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  label text not null,
  planned_amount numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  unique (trip_id, label)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id),
  title text not null,
  category text not null,
  amount numeric(12, 2) not null check (amount > 0),
  stop_place text,
  -- Optional receipt/reference photos — public URLs into the
  -- expense-photos storage bucket (see the "Storage" section below),
  -- set client-side after uploading each one. Empty array, not null,
  -- when there are none.
  photo_urls text[] not null default '{}',
  spent_at date not null default current_date,
  created_at timestamptz not null default now(),
  -- Off means "counts as my own spending only" — excluded from
  -- BudgetService.getBalances()'s paid/fair-share calculation, but
  -- still included in the Budget Planner's overall totals/category
  -- breakdown (it's still money spent on the trip).
  is_shared boolean not null default true
);

-- Organizer-only: permanently delete a spending category and every
-- expense logged under it (matched by label) in one atomic statement,
-- so "RM 200 spent in Accommodation" can't survive its own category
-- being deleted. The organizer check happens here (not just client-side)
-- since categories_write_members otherwise lets any member touch this
-- table — see categories_delete_organizer below, which blocks a direct
-- non-RPC delete from anyone else.
create function public.delete_budget_category(p_trip_id uuid, p_label text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_trip_organizer(p_trip_id) then
    raise exception 'Only the organizer can delete a budget category';
  end if;

  delete from public.expenses
  where trip_id = p_trip_id and category = p_label;

  delete from public.budget_categories
  where trip_id = p_trip_id and label = p_label;
end;
$$;

-- Superseded by trip_settlements below — ExpenseSplitScreen now computes
-- an automatic even split from `expenses` rather than a manually-edited
-- "owes the organizer" amount. Left in place (unused) rather than
-- dropped, since dropping a table is irreversible and nothing currently
-- depends on removing it.
create table public.trip_balances (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  owes_amount numeric(12, 2) not null default 0 check (owes_amount >= 0),
  updated_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- A recorded real-world payment between two trip members that settles
-- part of the auto-computed even split — e.g. "Jiaying paid Esther RM
-- 50 in cash". ExpenseSplitScreen nets these against each member's
-- (paid - fair share) balance before computing who-owes-who, so a
-- settled amount doesn't keep reappearing in the settle-up plan after
-- new expenses reshuffle the pairings. Rows are immutable facts, not
-- edited — to fix a mistake, delete and re-record.
create table public.trip_settlements (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  from_user_id uuid not null references auth.users (id),
  to_user_id uuid not null references auth.users (id),
  amount numeric(12, 2) not null check (amount > 0),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_activity_log enable row level security;
alter table public.trip_invites enable row level security;
alter table public.trip_join_requests enable row level security;
alter table public.group_messages enable row level security;
alter table public.group_message_reads enable row level security;
alter table public.direct_messages enable row level security;
alter table public.direct_message_reads enable row level security;
alter table public.group_message_reactions enable row level security;
alter table public.direct_message_reactions enable row level security;
alter table public.chat_background_preferences enable row level security;
alter table public.chat_reaction_seen_state enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.budget_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.trip_balances enable row level security;
alter table public.trip_settlements enable row level security;
alter table public.trip_stops enable row level security;
alter table public.trip_interests enable row level security;
alter table public.trip_schedule_stops enable row level security;

-- profiles: names/avatars are visible to any signed-in user (needed to
-- render trip-mates' names); everyone can only edit their own row.
create policy "profiles_select_authenticated" on public.profiles
  for select to authenticated using (true);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid());

-- trips: members can read; any authenticated user can create one
-- (the on_trip_created trigger makes them organizer); only the
-- organizer can update/delete.
create policy "trips_select_members" on public.trips
  for select to authenticated using (public.is_trip_member(id));
-- A requester isn't a member yet, but once they've filed a join request
-- (pending, approved, or rejected) they can see that trip's name/dates so
-- "Your Requests" can show what they actually applied to join.
create policy "trips_select_requesters" on public.trips
  for select to authenticated
  using (
    exists (
      select 1 from public.trip_join_requests r
      where r.trip_id = trips.id and r.user_id = auth.uid()
    )
  );
create policy "trips_insert_self" on public.trips
  for insert to authenticated with check (created_by = auth.uid());
create policy "trips_update_organizer" on public.trips
  for update to authenticated using (public.is_trip_organizer(id));
create policy "trips_delete_organizer" on public.trips
  for delete to authenticated using (public.is_trip_organizer(id));

-- trip_members: members can see their trip's roster. No direct insert
-- policy — membership is only granted via the trip-creation trigger or
-- decide_join_request(), both security definer.
create policy "trip_members_select_members" on public.trip_members
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_members_delete_self_or_organizer" on public.trip_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

-- trip_activity_log: any trip member can read it; writes only ever
-- come from the log_trip_member_joined()/log_trip_member_left()
-- triggers (security definer, bypassing RLS), so no insert policy.
create policy "trip_activity_log_select_members" on public.trip_activity_log
  for select to authenticated using (public.is_trip_member(trip_id));

-- trip_invites: only the organizer can create/view codes. Requesters
-- never query this table directly — they go through request_to_join().
create policy "trip_invites_all_organizer" on public.trip_invites
  for all to authenticated
  using (public.is_trip_organizer(trip_id))
  with check (public.is_trip_organizer(trip_id) and created_by = auth.uid());

-- trip_join_requests: organizer sees/manages all requests for their
-- trip; a requester can see their own. Inserts/decisions go through
-- the RPC functions above, not direct table access.
create policy "join_requests_select" on public.trip_join_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

-- group_messages: any trip member can read/post; only the author can
-- edit/delete their own message.
create policy "messages_select_members" on public.group_messages
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "messages_insert_members" on public.group_messages
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
create policy "messages_delete_own" on public.group_messages
  for delete to authenticated using (user_id = auth.uid());
create policy "messages_update_own" on public.group_messages
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- group_message_reads: any trip member can see who's read what; each
-- member can only ever record their own read receipt.
create policy "message_reads_select_members" on public.group_message_reads
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "message_reads_insert_self" on public.group_message_reads
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());

-- direct_messages: only the two participants can see a conversation.
-- Both sender and recipient must actually be trip members (the
-- recipient-membership check runs as the sender, whose own membership
-- the first clause already established — trip_members' own "members
-- can see their trip's roster" policy lets that select through).
create policy "direct_messages_select_participant" on public.direct_messages
  for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());
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
create policy "direct_messages_update_own" on public.direct_messages
  for update to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- direct_message_reads: each member only ever writes their own
-- last-read marker, but both participants in a conversation can read
-- it — the sender needs the recipient's marker to know whether/when
-- their messages have been seen (the DM blue tick).
create policy "direct_message_reads_select_participant" on public.direct_message_reads
  for select to authenticated
  using (user_id = auth.uid() or other_user_id = auth.uid());
create policy "direct_message_reads_insert_own" on public.direct_message_reads
  for insert to authenticated with check (user_id = auth.uid());
create policy "direct_message_reads_update_own" on public.direct_message_reads
  for update to authenticated using (user_id = auth.uid());

-- group_message_reactions: same shape as group_message_reads.
create policy "group_message_reactions_select_members" on public.group_message_reactions
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "group_message_reactions_insert_own" on public.group_message_reactions
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
create policy "group_message_reactions_update_own" on public.group_message_reactions
  for update to authenticated using (user_id = auth.uid());
create policy "group_message_reactions_delete_own" on public.group_message_reactions
  for delete to authenticated using (user_id = auth.uid());

-- direct_message_reactions: only participants of the reacted-to
-- message's conversation can see/react to it.
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

-- chat_background_preferences: purely personal, never visible to or
-- writable by anyone else.
create policy "chat_background_preferences_own" on public.chat_background_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- chat_reaction_seen_state: purely personal, never visible to or
-- writable by anyone else.
create policy "chat_reaction_seen_state_own" on public.chat_reaction_seen_state
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- polls + options: any member can read/create; a poll can only be
-- edited/deleted by whoever created it, or by the trip's organizer
-- (who can touch any poll regardless of who made it).
create policy "polls_select_members" on public.polls
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "polls_insert_members" on public.polls
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid());
create policy "polls_update_owner_or_organizer" on public.polls
  for update to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));
create policy "polls_delete_owner_or_organizer" on public.polls
  for delete to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));

create policy "poll_options_select_members" on public.poll_options
  for select to authenticated
  using (public.is_trip_member((select trip_id from public.polls where id = poll_id)));
-- PollService.updatePoll() writes poll_options directly (insert/update/
-- delete rows to match the edited option list) rather than relying on
-- cascade, so this needs the same own-poll-or-organizer allowance as
-- the polls table itself.
create policy "poll_options_write_owner_or_organizer" on public.poll_options
  for all to authenticated
  using (
    exists (
      select 1 from public.polls p
      where p.id = poll_id
        and (p.created_by = auth.uid() or public.is_trip_organizer(p.trip_id))
    )
  );

-- poll_votes: any member can read tallies and cast/change their own vote.
create policy "poll_votes_select_members" on public.poll_votes
  for select to authenticated
  using (public.is_trip_member((select trip_id from public.polls where id = poll_id)));
create policy "poll_votes_upsert_own" on public.poll_votes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_trip_member((select trip_id from public.polls where id = poll_id))
  );
create policy "poll_votes_update_own" on public.poll_votes
  for update to authenticated using (user_id = auth.uid());
create policy "poll_votes_delete_own" on public.poll_votes
  for delete to authenticated using (user_id = auth.uid());

-- budget_categories: any member can read/plan; only the organizer can
-- delete a category (they lose their own expenses too — see
-- delete_budget_category — so this isn't a call every member should get
-- to make unilaterally).
create policy "categories_select_members" on public.budget_categories
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "categories_upsert_members" on public.budget_categories
  for insert to authenticated with check (public.is_trip_member(trip_id));
create policy "categories_update_members" on public.budget_categories
  for update to authenticated using (public.is_trip_member(trip_id));
create policy "categories_delete_organizer" on public.budget_categories
  for delete to authenticated using (public.is_trip_organizer(trip_id));

-- expenses: any member can read; the logger or the organizer can
-- edit/delete.
create policy "expenses_select_members" on public.expenses
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "expenses_insert_members" on public.expenses
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
create policy "expenses_update_owner_or_organizer" on public.expenses
  for update to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));
create policy "expenses_delete_owner_or_organizer" on public.expenses
  for delete to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

-- trip_balances: any member can read; only the organizer edits who
-- owes what (they're the one collecting).
create policy "balances_select_members" on public.trip_balances
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "balances_write_organizer" on public.trip_balances
  for all to authenticated using (public.is_trip_organizer(trip_id))
  with check (public.is_trip_organizer(trip_id));

-- trip_settlements: any member can read and record one (self-reported —
-- "we settled up in cash", no bank integration to verify it) as long as
-- it's tagged with themselves as created_by; only the recorder or the
-- organizer can delete one (undo a mistake).
create policy "settlements_select_members" on public.trip_settlements
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "settlements_insert_members" on public.trip_settlements
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid());
create policy "settlements_delete_owner_or_organizer" on public.trip_settlements
  for delete to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));

-- trip_stops / trip_interests: any member can read/manage — mirrors
-- budget_categories (anyone planning the trip can add a stop or tweak
-- the interest list, not just the organizer).
create policy "trip_stops_select_members" on public.trip_stops
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_stops_write_members" on public.trip_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_interests_select_members" on public.trip_interests
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_interests_write_members" on public.trip_interests
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_schedule_stops_select_members" on public.trip_schedule_stops
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_schedule_stops_write_members" on public.trip_schedule_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

-- ============================================================
-- Realtime: every table the Flutter services read via `.stream()`
-- must be in this publication, or those streams silently never emit.
-- ============================================================

alter publication supabase_realtime add table
  public.group_messages,
  public.group_message_reads,
  public.direct_messages,
  public.direct_message_reads,
  public.group_message_reactions,
  public.direct_message_reactions,
  public.poll_votes,
  public.poll_options,
  public.polls,
  public.trip_members,
  public.trip_join_requests,
  public.trips,
  public.expenses,
  public.budget_categories,
  public.trip_settlements,
  public.trip_activity_log;

-- A DELETE event's replication payload only carries the replica
-- identity's columns for the deleted row — by default just the primary
-- key. `.stream()` calls that filter by a non-primary-key column (every
-- one of these is filtered by `trip_id`, not `id`) can't evaluate that
-- filter against a payload that's missing `trip_id`, so the delete
-- event is silently dropped and the row lingers in the UI until the
-- stream re-subscribes (e.g. leaving and reopening the screen). FULL
-- replica identity includes every column, fixing that for tables whose
-- rows actually get deleted through the app (expenses, polls, members,
-- and now budget_categories via delete_budget_category()).
alter table public.expenses replica identity full;
alter table public.polls replica identity full;
alter table public.trip_members replica identity full;
alter table public.budget_categories replica identity full;
alter table public.trip_settlements replica identity full;
alter table public.group_message_reads replica identity full;
alter table public.direct_messages replica identity full;
alter table public.direct_message_reads replica identity full;
alter table public.group_message_reactions replica identity full;
alter table public.direct_message_reactions replica identity full;

-- ============================================================
-- Storage: expense receipt photos. Public bucket (read requires no
-- auth header, so a stored `expenses.photo_url` from getPublicUrl()
-- just works in an Image.network) but writes are still gated by RLS on
-- storage.objects below. Objects are keyed "<trip_id>/<file>", so a
-- policy can recover the trip id from the first path segment without
-- needing to know which expense a photo belongs to (a new expense
-- doesn't have an id yet at upload time).
-- ============================================================

insert into storage.buckets (id, name, public)
values ('expense-photos', 'expense-photos', true)
on conflict (id) do nothing;

create policy "expense_photos_select_public" on storage.objects
  for select
  using (bucket_id = 'expense-photos');

create policy "expense_photos_insert_members" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );

create policy "expense_photos_update_owner_or_organizer" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
    and (
      owner_id = (auth.uid())::text
      or public.is_trip_organizer(((storage.foldername(name))[1])::uuid)
    )
  );

create policy "expense_photos_delete_owner_or_organizer" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
    and (
      owner_id = (auth.uid())::text
      or public.is_trip_organizer(((storage.foldername(name))[1])::uuid)
    )
  );

-- Storage: chat photos/videos/voice notes, shared by group chat and
-- direct messages. Same public-bucket-plus-RLS shape as expense-photos
-- above; no update/delete policy since chat attachments aren't edited.
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
