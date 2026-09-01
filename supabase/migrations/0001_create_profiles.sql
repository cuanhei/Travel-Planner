-- Profiles table: the app-facing record of each user, kept in sync with
-- Supabase's built-in auth.users table (which the app never queries
-- directly). Run this once in the Supabase SQL Editor (or via `supabase db
-- push` if you're using the CLI) against the shared project.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  email text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Each user can only see and edit their own row.
create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create a profile row the moment a new auth user is created (i.e.
-- right when sign-up succeeds, before email verification). `full_name`
-- comes from the `data: {'full_name': ...}` passed to `AuthService.signUp`.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.email);
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
