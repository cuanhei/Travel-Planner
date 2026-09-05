-- Lets the Sign Up screen show "An account with this email already exists"
-- immediately, instead of relying on Supabase's signUp() response (which
-- deliberately returns an indistinguishable fake success for an
-- already-confirmed email, to prevent account enumeration).
--
-- This function only ever returns true/false — it never exposes any user
-- data — so it's safe to expose to anonymous callers. It's a deliberate,
-- small trade-off of Supabase's default anti-enumeration protection for
-- better sign-up UX.
--
-- Only checks CONFIRMED accounts: an existing but unconfirmed signup should
-- keep going through the normal "resend confirmation" path, not be blocked
-- here.
--
-- Run once in the Supabase SQL Editor for this project.

create or replace function public.email_exists(check_email text)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users
    where email = check_email
    and email_confirmed_at is not null
  );
$$;

grant execute on function public.email_exists(text) to anon, authenticated;
