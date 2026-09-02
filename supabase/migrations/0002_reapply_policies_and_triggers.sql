-- Re-applies every function, trigger, RLS policy, and realtime
-- publication entry from schema.sql, without touching any `create
-- table` statement. Safe to run any number of times, and safe to run
-- even if only some of schema.sql applied the first time (e.g. it hit
-- an error partway through and silently skipped the rest) — every
-- statement here is idempotent (drop-if-exists / create-or-replace /
-- guarded), so it converges to the correct state regardless of what
-- was already there.
--
-- Run this if you're seeing RLS errors like:
--   PostgrestException(message: new row violates row-level security
--   policy for table "trips", code: 42501, ...)
-- which means the policy for that table never actually got created.

create extension if not exists pgcrypto;

-- ============================================================
-- Functions + triggers
-- ============================================================

create or replace function public.handle_new_user()
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_profiles_updated on public.profiles;
create trigger on_profiles_updated
  before update on public.profiles
  for each row execute function public.handle_profile_updated_at();

create or replace function public.handle_new_trip()
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

drop trigger if exists on_trip_created on public.trips;
create trigger on_trip_created
  after insert on public.trips
  for each row execute function public.handle_new_trip();

create or replace function public.is_trip_member(p_trip_id uuid)
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

create or replace function public.is_trip_organizer(p_trip_id uuid)
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

create or replace function public.request_to_join(p_code text)
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

create or replace function public.decide_join_request(p_request_id uuid, p_approve boolean)
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
      decided_at = now()
  where id = p_request_id;

  if p_approve then
    insert into public.trip_members (trip_id, user_id)
    values (v_trip_id, v_user_id)
    on conflict do nothing;
  end if;
end;
$$;

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

drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated" on public.profiles
  for select to authenticated using (true);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid());

drop policy if exists "trips_select_members" on public.trips;
create policy "trips_select_members" on public.trips
  for select to authenticated using (public.is_trip_member(id));
drop policy if exists "trips_insert_self" on public.trips;
create policy "trips_insert_self" on public.trips
  for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "trips_update_organizer" on public.trips;
create policy "trips_update_organizer" on public.trips
  for update to authenticated using (public.is_trip_organizer(id));
drop policy if exists "trips_delete_organizer" on public.trips;
create policy "trips_delete_organizer" on public.trips
  for delete to authenticated using (public.is_trip_organizer(id));

drop policy if exists "trip_members_select_members" on public.trip_members;
create policy "trip_members_select_members" on public.trip_members
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "trip_members_delete_self_or_organizer" on public.trip_members;
create policy "trip_members_delete_self_or_organizer" on public.trip_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

drop policy if exists "trip_invites_all_organizer" on public.trip_invites;
create policy "trip_invites_all_organizer" on public.trip_invites
  for all to authenticated
  using (public.is_trip_organizer(trip_id))
  with check (public.is_trip_organizer(trip_id) and created_by = auth.uid());

drop policy if exists "join_requests_select" on public.trip_join_requests;
create policy "join_requests_select" on public.trip_join_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

drop policy if exists "messages_select_members" on public.group_messages;
create policy "messages_select_members" on public.group_messages
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "messages_insert_members" on public.group_messages;
create policy "messages_insert_members" on public.group_messages
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
drop policy if exists "messages_delete_own" on public.group_messages;
create policy "messages_delete_own" on public.group_messages
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "polls_select_members" on public.polls;
create policy "polls_select_members" on public.polls
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "polls_insert_members" on public.polls;
create policy "polls_insert_members" on public.polls
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid());
drop policy if exists "polls_update_owner_or_organizer" on public.polls;
create policy "polls_update_owner_or_organizer" on public.polls
  for update to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));
drop policy if exists "polls_delete_owner_or_organizer" on public.polls;
create policy "polls_delete_owner_or_organizer" on public.polls
  for delete to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));

drop policy if exists "poll_options_select_members" on public.poll_options;
create policy "poll_options_select_members" on public.poll_options
  for select to authenticated
  using (public.is_trip_member((select trip_id from public.polls where id = poll_id)));
drop policy if exists "poll_options_write_owner_or_organizer" on public.poll_options;
create policy "poll_options_write_owner_or_organizer" on public.poll_options
  for all to authenticated
  using (
    exists (
      select 1 from public.polls p
      where p.id = poll_id
        and (p.created_by = auth.uid() or public.is_trip_organizer(p.trip_id))
    )
  );

drop policy if exists "poll_votes_select_members" on public.poll_votes;
create policy "poll_votes_select_members" on public.poll_votes
  for select to authenticated
  using (public.is_trip_member((select trip_id from public.polls where id = poll_id)));
drop policy if exists "poll_votes_upsert_own" on public.poll_votes;
create policy "poll_votes_upsert_own" on public.poll_votes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_trip_member((select trip_id from public.polls where id = poll_id))
  );
drop policy if exists "poll_votes_update_own" on public.poll_votes;
create policy "poll_votes_update_own" on public.poll_votes
  for update to authenticated using (user_id = auth.uid());
drop policy if exists "poll_votes_delete_own" on public.poll_votes;
create policy "poll_votes_delete_own" on public.poll_votes
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "categories_select_members" on public.budget_categories;
create policy "categories_select_members" on public.budget_categories
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "categories_write_members" on public.budget_categories;
create policy "categories_write_members" on public.budget_categories
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

drop policy if exists "expenses_select_members" on public.expenses;
create policy "expenses_select_members" on public.expenses
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "expenses_insert_members" on public.expenses;
create policy "expenses_insert_members" on public.expenses
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
drop policy if exists "expenses_update_owner_or_organizer" on public.expenses;
create policy "expenses_update_owner_or_organizer" on public.expenses
  for update to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));
drop policy if exists "expenses_delete_owner_or_organizer" on public.expenses;
create policy "expenses_delete_owner_or_organizer" on public.expenses
  for delete to authenticated
  using (user_id = auth.uid() or public.is_trip_organizer(trip_id));

drop policy if exists "balances_select_members" on public.trip_balances;
create policy "balances_select_members" on public.trip_balances
  for select to authenticated using (public.is_trip_member(trip_id));
drop policy if exists "balances_write_organizer" on public.trip_balances;
create policy "balances_write_organizer" on public.trip_balances
  for all to authenticated using (public.is_trip_organizer(trip_id))
  with check (public.is_trip_organizer(trip_id));

-- ============================================================
-- Realtime — guarded so it's safe even if some tables were already
-- added on a previous (partial) run.
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'group_messages', 'poll_votes', 'poll_options', 'polls',
    'trip_members', 'trip_join_requests', 'trips', 'expenses',
    'budget_categories'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
