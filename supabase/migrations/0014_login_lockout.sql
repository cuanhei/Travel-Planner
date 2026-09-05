-- Account lockout after repeated failed sign-in attempts (Sign In screen):
-- 5 failed attempts locks that email out, with an escalating duration —
-- 5 minutes the first time, 10 the next, 15 the one after, and so on
-- (+5 min per lockout) — that only resets back to 5 minutes once the
-- account signs in successfully. Tracked server-side, keyed by email (a
-- failed attempt happens before Supabase knows which user it is) — not
-- just client-side — so it can't be bypassed by clearing local storage or
-- switching devices.
--
-- Only ever touched through the SECURITY DEFINER functions below (same
-- pattern as `email_exists` in 0003_add_email_exists_check.sql and
-- `delete_own_account` in 0012_delete_own_account.sql) — RLS is enabled
-- with no policies, so the client can't read or write this table directly.
--
-- Run once in the Supabase SQL Editor for this project.

create table if not exists public.login_lockouts (
  email text primary key,
  failed_count int not null default 0,
  -- How many times this email has been locked out since its last
  -- successful sign-in — drives the escalating duration below. Reset to 0
  -- only by `clear_login_lockout` (i.e. a successful sign-in), never by
  -- time passing, so the escalation persists across attempts.
  lockout_count int not null default 0,
  locked_until timestamptz,
  last_attempt_at timestamptz not null default now()
);

alter table public.login_lockouts enable row level security;

-- Records one failed attempt for `p_email`, locking it out once the count
-- (within a rolling 15-minute window) reaches 5. Each successive lockout
-- for the same email is 5 minutes longer than the last (5, 10, 15, ...)
-- until a successful sign-in resets the escalation. Returns whether this
-- attempt just triggered a lockout, and until when.
create or replace function public.record_failed_login(p_email text)
returns table (locked boolean, locked_until timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
  v_row public.login_lockouts%rowtype;
  v_new_count int;
  v_new_lockout_count int;
  v_locked_until timestamptz;
begin
  select * into v_row from public.login_lockouts where email = v_email for update;

  if v_row is null or v_row.last_attempt_at < now() - interval '15 minutes' then
    -- No prior streak, or the previous one aged out — a fresh run of
    -- wrong-password attempts, but note this does NOT touch
    -- lockout_count, which only resets on a successful sign-in.
    v_new_count := 1;
  else
    v_new_count := v_row.failed_count + 1;
  end if;

  v_new_lockout_count := coalesce(v_row.lockout_count, 0);

  if v_new_count >= 5 then
    v_new_lockout_count := v_new_lockout_count + 1;
    v_locked_until := now() + make_interval(mins => 5 * v_new_lockout_count);
    v_new_count := 0;
  else
    v_locked_until := null;
  end if;

  insert into public.login_lockouts
    (email, failed_count, lockout_count, locked_until, last_attempt_at)
  values (v_email, v_new_count, v_new_lockout_count, v_locked_until, now())
  on conflict (email) do update
    set failed_count = excluded.failed_count,
        lockout_count = excluded.lockout_count,
        locked_until = excluded.locked_until,
        last_attempt_at = excluded.last_attempt_at;

  return query select (v_locked_until is not null), v_locked_until;
end;
$$;

grant execute on function public.record_failed_login(text) to anon, authenticated;

-- Checked before attempting sign-in, so a locked-out account never even
-- reaches Supabase's own rate limiter. Returns null if not locked.
create or replace function public.check_login_lockout(p_email text)
returns timestamptz
language sql
security definer
set search_path = public
as $$
  select locked_until from public.login_lockouts
  where email = lower(trim(p_email)) and locked_until is not null and locked_until > now();
$$;

grant execute on function public.check_login_lockout(text) to anon, authenticated;

-- Called automatically after a successful sign-in (see the
-- `onAuthStateChange` listener in `main.dart`) to reset the streak,
-- including the escalation level (`lockout_count`) — the next lockout for
-- this email, if any, starts back at 5 minutes.
create or replace function public.clear_login_lockout(p_email text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.login_lockouts where email = lower(trim(p_email));
$$;

grant execute on function public.clear_login_lockout(text) to anon, authenticated;
