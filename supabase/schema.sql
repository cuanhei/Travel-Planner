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

create table public.group_messages (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
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
  spent_at date not null default current_date,
  created_at timestamptz not null default now()
);

-- Manually-editable "how much this member owes the organizer" — mirrors
-- ExpenseSplitScreen, which is an editable balance rather than an
-- automatic even split. What each member *paid* is derived from
-- `expenses` (sum by user_id), not stored here.
create table public.trip_balances (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  owes_amount numeric(12, 2) not null default 0 check (owes_amount >= 0),
  updated_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_invites enable row level security;
alter table public.trip_join_requests enable row level security;
alter table public.group_messages enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.budget_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.trip_balances enable row level security;
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

-- polls + options: any member can read/create; only the trip's organizer
-- can edit/delete a poll (matches Voting screen's edit/delete-poll
-- affordance, which is hidden from non-organizer members).
create policy "polls_select_members" on public.polls
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "polls_insert_members" on public.polls
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid());
create policy "polls_update_organizer" on public.polls
  for update to authenticated
  using (public.is_trip_organizer(trip_id));
create policy "polls_delete_organizer" on public.polls
  for delete to authenticated
  using (public.is_trip_organizer(trip_id));

create policy "poll_options_select_members" on public.poll_options
  for select to authenticated
  using (public.is_trip_member((select trip_id from public.polls where id = poll_id)));
create policy "poll_options_write_organizer" on public.poll_options
  for all to authenticated
  using (
    exists (
      select 1 from public.polls p
      where p.id = poll_id
        and public.is_trip_organizer(p.trip_id)
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

-- budget_categories: any member can read/manage.
create policy "categories_select_members" on public.budget_categories
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "categories_write_members" on public.budget_categories
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

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
  public.poll_votes,
  public.poll_options,
  public.polls,
  public.trip_members,
  public.trip_join_requests,
  public.trips,
  public.expenses,
  public.budget_categories;

-- A DELETE event's replication payload only carries the replica
-- identity's columns for the deleted row — by default just the primary
-- key. `.stream()` calls that filter by a non-primary-key column (every
-- one of these is filtered by `trip_id`, not `id`) can't evaluate that
-- filter against a payload that's missing `trip_id`, so the delete
-- event is silently dropped and the row lingers in the UI until the
-- stream re-subscribes (e.g. leaving and reopening the screen). FULL
-- replica identity includes every column, fixing that for tables whose
-- rows actually get deleted through the app (expenses, polls, members).
alter table public.expenses replica identity full;
alter table public.polls replica identity full;
alter table public.trip_members replica identity full;
