-- Extends the team's existing `public.profiles` table (id, display_name,
-- avatar_color, created_at — built for the Community/Profile screens) with
-- the columns the Authentication module needs. Does not touch
-- display_name/avatar_color or any data already in the table.
--
-- Safe to run even if another trigger already creates a profiles row on
-- sign-up: the trigger below uses ON CONFLICT DO UPDATE, so it only ever
-- adds/refreshes the auth-owned columns and never clobbers display_name or
-- avatar_color.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists full_name text,
  add column if not exists email text,
  add column if not exists avatar_url text,
  add column if not exists updated_at timestamptz not null default now();

-- display_name/avatar_color are NOT NULL with no default on this table.
-- Our trigger doesn't set them (that's owned by whoever built the
-- Community/Profile feature), so they must be allowed to start out empty
-- for a row created purely by sign-up.
alter table public.profiles
  alter column display_name drop not null,
  alter column avatar_color drop not null;

alter table public.profiles enable row level security;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create/refresh the auth-owned columns of a profile row the moment a
-- new auth user is created (i.e. right when sign-up succeeds, before email
-- verification). `full_name` comes from `data: {'full_name': ...}` passed
-- to `AuthService.signUp`.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.email)
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

-- Keep `updated_at` current on every edit.
create or replace function public.handle_updated_at()
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
  for each row execute function public.handle_updated_at();
