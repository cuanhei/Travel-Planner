-- Lets a signed-in user delete their own account (Privacy & Security >
-- Delete Account). Two parts:
--
-- 1. A few `auth.users` foreign keys weren't cascading (trips/polls/
--    invites "created_by", expenses "user_id"), so deleting a user who
--    owns any of those rows would fail with a foreign-key violation.
--    Deleting your account should take your owned trips (and everything
--    hanging off them) with it, so these are switched to ON DELETE
--    CASCADE. Every other `auth.users` reference in schema.sql already
--    cascades (profiles, trip_members, expenses via trips, etc).
--
-- 2. `delete_own_account()` is a SECURITY DEFINER function (same pattern
--    as `email_exists` in 0003_add_email_exists_check.sql) that deletes
--    the caller's own row from `auth.users` — the client can't do this
--    directly since authenticated/anon aren't granted DELETE on the auth
--    schema. Deleting the auth.users row cascades through `profiles` and
--    every table above.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.trips
  drop constraint trips_created_by_fkey,
  add constraint trips_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete cascade;

alter table public.trip_invites
  drop constraint trip_invites_created_by_fkey,
  add constraint trip_invites_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete cascade;

alter table public.polls
  drop constraint polls_created_by_fkey,
  add constraint polls_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete cascade;

alter table public.expenses
  drop constraint expenses_user_id_fkey,
  add constraint expenses_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
