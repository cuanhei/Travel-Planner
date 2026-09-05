-- Adds richer personal-information fields to the Edit Profile screen:
-- date of birth, gender, nationality, and home address. All optional.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists date_of_birth date,
  add column if not exists gender text,
  add column if not exists nationality text,
  add column if not exists address text;
