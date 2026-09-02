-- Adds the phone/bio columns the Edit Profile screen needs. full_name,
-- email, and avatar_url already exist (0001/0002).
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists phone text,
  add column if not exists bio text;
