-- The live `trips` table is missing its `name` column entirely (drifted
-- from schema.sql at some point outside migration history) — every trip
-- row currently fails to load in the app because `name` is required.
-- Backfill existing rows with a placeholder before re-adding the NOT NULL
-- constraint, since a plain `add column ... not null` would fail outright
-- on a table that already has rows.

alter table public.trips add column if not exists name text;

update public.trips set name = 'Untitled Trip' where name is null;

alter table public.trips alter column name set not null;
