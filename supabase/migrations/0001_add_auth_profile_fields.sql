-- Extends the already-live `public.profiles` table (id, display_name,
-- avatar_color, created_at — from the original schema.sql) with the
-- columns the Authentication module needs, and reconciles the
-- sign-up trigger so it populates BOTH sets of columns instead of one
-- replacing the other.
--
-- Run this once in the Supabase SQL Editor against a project that
-- already has the original schema.sql applied. On a brand-new project,
-- just run schema.sql — it already has this merged shape built in.

alter table public.profiles
  add column if not exists full_name text,
  add column if not exists email text,
  add column if not exists avatar_url text,
  add column if not exists updated_at timestamptz not null default now();

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

-- Backfill email for any accounts that signed up before this migration.
update public.profiles p
set email = u.email
from auth.users u
where p.id = u.id and p.email is null;
