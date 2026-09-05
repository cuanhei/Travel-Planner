-- Saved Places module: previously a UI-only screen showing a fixed
-- subset of a dummy destination catalog (reset to the same 3 places
-- every app restart, disconnected from the real Explore tab's Google
-- Places data entirely). Bookmarking is per-user (not trip-scoped —
-- Saved Places lives under the Profile/Saved module, not a specific
-- trip), keyed by Google's own place id so re-saving the same place
-- from two different searches doesn't create a duplicate row.
--
-- Only the fields the Saved Places grid + place details screen need
-- are persisted (name/address/coords/type/photo) — enough to render
-- both without a fresh Places API call, matching how `trip_stops`
-- persists picked-place identity instead of re-fetching it.

create table public.saved_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  place_id text not null,
  name text not null,
  address text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  primary_type text,
  photo_url text,
  created_at timestamptz not null default now(),
  unique (user_id, place_id)
);

alter table public.saved_places enable row level security;

-- Personal bookmarks — only the saver can see or manage their own.
create policy "saved_places_select_own" on public.saved_places
  for select to authenticated using (user_id = auth.uid());
create policy "saved_places_write_own" on public.saved_places
  for all to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Required for SavedPlacesService.watchSavedPlaces()'s `.stream()` to
-- ever emit anything (see the same note in schema.sql).
alter publication supabase_realtime add table public.saved_places;

-- watchSavedPlaces() filters by user_id, not the primary key, so a
-- DELETE's default (primary-key-only) replication payload can't
-- satisfy that filter and the event is silently dropped (see
-- schema.sql's note next to `expenses replica identity full`). FULL
-- replica identity fixes it.
alter table public.saved_places replica identity full;
