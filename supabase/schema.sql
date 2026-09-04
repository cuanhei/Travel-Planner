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
  start_location_name text,
  start_address text,
  start_latitude double precision,
  start_longitude double precision,
  end_location_name text,
  end_address text,
  end_latitude double precision,
  end_longitude double precision,
  start_date date,
  end_date date,
  start_time time,
  end_time time,
  created_by uuid not null references auth.users (id),
  total_budget numeric(12, 2) not null default 0,
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

-- Per-trip "quick" stops a traveler saves for fast directions — e.g. a
-- nearby 7-Eleven or pharmacy they'll want to nip to, not a must-visit
-- itinerary stop. Same row shape as `trip_stops` but deliberately a
-- separate table: these must never show up on the trip map or schedule.
create table public.trip_favorite_stops (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  name text not null,
  address text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  osm_id text,
  category text not null default 'Other',
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
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

-- Where the traveler(s) stay each night of the trip, captured on Create
-- Trip right after picking travel dates. One row per night — an N-day
-- trip has nights 1..N-1 (night_number is 1-indexed), so a single-day
-- trip has none. Deliberately separate from trip_schedule_stops (which
-- needs a real trip_stops row + a full day-by-day schedule, neither of
-- which exists yet at trip-creation time).
create table public.trip_accommodations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  night_number integer not null check (night_number > 0),
  name text not null,
  address text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  unique (trip_id, night_number)
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
-- (which would otherwise leak every trip's active codes).
create function public.request_to_join(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_trip_id uuid;
  v_request_id uuid;
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
  constraint group_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0
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
  constraint direct_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0
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
  created_at timestamptz not null default now()
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
-- Community module: travel-experience feed, comments, place reviews
-- ============================================================
--
-- NOTE: on the shared project this app actually runs against, these four
-- tables were provisioned by hand directly in the Supabase dashboard
-- rather than from a committed SQL file, so this definition was
-- reverse-engineered against the live schema (via the PostgREST API —
-- there was no SQL source of truth to read from) rather than designed
-- from scratch. It's what CommunityService (lib/services/
-- community_service.dart) expects. If you're bootstrapping a brand-new
-- project, this section creates it correctly from scratch; if you're
-- pointing at the existing shared project (tables already exist, may be
-- missing RLS/triggers/realtime), run
-- supabase/migrations/0009_community_module.sql instead — it's an
-- idempotent repair script safe to run against what's already there.
-- 0010 and 0011 layer on post media and reactions respectively, same
-- idempotent-migration approach.

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  place_name text not null,
  caption text not null check (char_length(trim(caption)) > 0),
  category text not null,
  cover_gradient text not null default 'horizon'
    check (cover_gradient in ('horizon', 'dusk', 'sunset', 'lagoon')),
  media_url text,
  media_type text check (media_type is null or media_type in ('image', 'video')),
  likes_count integer not null default 0,
  -- `{reaction_type: count}` breakdown, e.g. `{"like": 3, "love": 1}` — lets
  -- the feed render small per-emoji counts without a join/count query on
  -- every row. Kept in sync by handle_post_like_change().
  reaction_counts jsonb not null default '{}'::jsonb,
  comments_count integer not null default 0,
  created_at timestamptz not null default now()
);

-- One row per (post, user) — a user has at most one reaction per post;
-- picking a different one updates reaction_type in place rather than
-- adding a second row (see CommunityService.setReaction).
create table public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reaction_type text not null default 'like'
    check (reaction_type in ('like', 'love', 'wow')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);

-- Keyed by place name (this app has no canonical `places` table — Explore's
-- place cards and Community posts both just carry a free-text place name),
-- so reviews attach to that same string. One review per *visit*, not per
-- user-per-place — TripService.visitCount vs CommunityService
-- .myReviewCount gates how many a user may add, and addReview always
-- inserts a fresh row rather than upserting (see
-- 0013_allow_multiple_reviews_per_visit.sql for the migration that
-- dropped the old one-per-place uniqueness).
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  place_name text not null,
  author_id uuid not null references auth.users (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);

-- Keep posts.likes_count/comments_count in sync so the feed (which only
-- streams `posts`, not post_likes/comments) can show accurate counts
-- without a join on every row.
create function public.handle_post_like_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
    set likes_count = likes_count + 1,
        reaction_counts = jsonb_set(
          reaction_counts,
          array[new.reaction_type],
          to_jsonb(coalesce((reaction_counts ->> new.reaction_type)::int, 0) + 1)
        )
    where id = new.post_id;
    return new;
  elsif tg_op = 'UPDATE' then
    if new.reaction_type is distinct from old.reaction_type then
      update public.posts
      set reaction_counts = jsonb_set(
            jsonb_set(
              reaction_counts,
              array[old.reaction_type],
              to_jsonb(greatest(coalesce((reaction_counts ->> old.reaction_type)::int, 0) - 1, 0))
            ),
            array[new.reaction_type],
            to_jsonb(coalesce((reaction_counts ->> new.reaction_type)::int, 0) + 1)
          )
      where id = new.post_id;
    end if;
    return new;
  else
    update public.posts
    set likes_count = greatest(likes_count - 1, 0),
        reaction_counts = jsonb_set(
          reaction_counts,
          array[old.reaction_type],
          to_jsonb(greatest(coalesce((reaction_counts ->> old.reaction_type)::int, 0) - 1, 0))
        )
    where id = old.post_id;
    return old;
  end if;
end;
$$;

create trigger on_post_like_change
  after insert or update or delete on public.post_likes
  for each row execute function public.handle_post_like_change();

create function public.handle_post_comment_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
    return new;
  else
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    return old;
  end if;
end;
$$;

create trigger on_post_comment_change
  after insert or delete on public.comments
  for each row execute function public.handle_post_comment_change();

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_invites enable row level security;
alter table public.trip_join_requests enable row level security;
alter table public.group_messages enable row level security;
alter table public.group_message_reads enable row level security;
alter table public.direct_messages enable row level security;
alter table public.direct_message_reads enable row level security;
alter table public.group_message_reactions enable row level security;
alter table public.direct_message_reactions enable row level security;
alter table public.chat_background_preferences enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.budget_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.trip_balances enable row level security;
alter table public.trip_settlements enable row level security;
alter table public.trip_stops enable row level security;
alter table public.trip_favorite_stops enable row level security;
alter table public.trip_schedule_stops enable row level security;
alter table public.trip_accommodations enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.reviews enable row level security;

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

-- trip_stops: any member can read/manage — mirrors budget_categories
-- (anyone planning the trip can add a stop, not just the organizer).
create policy "trip_stops_select_members" on public.trip_stops
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_stops_write_members" on public.trip_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_favorite_stops_select_members" on public.trip_favorite_stops
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_favorite_stops_write_members" on public.trip_favorite_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_schedule_stops_select_members" on public.trip_schedule_stops
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_schedule_stops_write_members" on public.trip_schedule_stops
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy "trip_accommodations_select_members" on public.trip_accommodations
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "trip_accommodations_write_members" on public.trip_accommodations
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

-- posts: feed is visible to any signed-in user; only the author can
-- edit/delete their own post.
create policy "posts_select_authenticated" on public.posts
  for select to authenticated using (true);
create policy "posts_insert_self" on public.posts
  for insert to authenticated with check (author_id = auth.uid());
create policy "posts_update_own" on public.posts
  for update to authenticated using (author_id = auth.uid());
create policy "posts_delete_own" on public.posts
  for delete to authenticated using (author_id = auth.uid());

-- post_likes: anyone can see who reacted with what; you can only
-- add/change/remove your own row (insert on first react, update when
-- switching reaction types, delete to clear it — see
-- CommunityService.setReaction).
create policy "post_likes_select_authenticated" on public.post_likes
  for select to authenticated using (true);
create policy "post_likes_insert_self" on public.post_likes
  for insert to authenticated with check (user_id = auth.uid());
create policy "post_likes_update_own" on public.post_likes
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy "post_likes_delete_self" on public.post_likes
  for delete to authenticated using (user_id = auth.uid());

-- comments: any signed-in user can read/comment; only the author can
-- delete their own comment (mirrors group_messages).
create policy "comments_select_authenticated" on public.comments
  for select to authenticated using (true);
create policy "comments_insert_self" on public.comments
  for insert to authenticated with check (author_id = auth.uid());
create policy "comments_delete_own" on public.comments
  for delete to authenticated using (author_id = auth.uid());

-- reviews: any signed-in user can read; only the author can
-- write/update/delete their own review.
create policy "reviews_select_authenticated" on public.reviews
  for select to authenticated using (true);
create policy "reviews_insert_self" on public.reviews
  for insert to authenticated with check (author_id = auth.uid());
create policy "reviews_update_own" on public.reviews
  for update to authenticated using (author_id = auth.uid());
create policy "reviews_delete_own" on public.reviews
  for delete to authenticated using (author_id = auth.uid());

-- Storage: `post-media` holds the photo/video a post can optionally attach
-- (AddPostScreen). Public bucket (feed images load unauthenticated via a
-- plain URL); write access is restricted by folder — every object is
-- uploaded under `<author_id>/...`, so ownership is just the first path
-- segment.
insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do nothing;

create policy "post_media_select_public" on storage.objects
  for select to public using (bucket_id = 'post-media');
create policy "post_media_insert_own_folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "post_media_delete_own_folder" on storage.objects
  for delete to authenticated using (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

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
  public.posts,
  public.comments,
  public.reviews;

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

-- comments (watched filtered by post_id) and reviews (watched filtered by
-- place_name) both support deleting your own row through the app — same
-- DELETE-payload gotcha as above.
alter table public.comments replica identity full;
alter table public.reviews replica identity full;
