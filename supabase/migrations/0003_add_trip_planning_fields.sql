-- Extends the already-live `public.trips` table (id, name, created_by,
-- total_budget, created_at — from schema.sql / the Budget+Group teammate's
-- migrations) with the fields the Trip Planner module's "My Trips" list
-- needs to show each trip's destination and dates, and to bucket trips
-- into Current / Upcoming / Past without any extra tables.
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql applied. On a brand-new project, just run schema.sql —
-- it already has this merged shape built in.

alter table public.trips
  add column if not exists destination text not null default '',
  add column if not exists start_date date,
  add column if not exists end_date date;
