-- Packing List module: previously UI-only mock data with no persistence
-- (reset every time the screen reopened) and not scoped to any trip.
-- One row per checklist item; `quantity` and `note` support entries like
-- "3x socks" with a reminder, not just a bare label + checkbox.

create table public.packing_items (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  label text not null,
  category text not null,
  quantity integer not null default 1 check (quantity > 0),
  note text,
  packed boolean not null default false,
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.packing_items enable row level security;

-- Any trip member can read/manage the shared list, not just whoever
-- added a given item — mirrors trip_stops/budget_categories (anyone
-- planning the trip can pack for it).
create policy "packing_items_select_members" on public.packing_items
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "packing_items_write_members" on public.packing_items
  for all to authenticated using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

-- Required for PackingListService.watchItems()'s `.stream()` to ever
-- emit anything (see the same note in schema.sql).
alter publication supabase_realtime add table public.packing_items;

-- watchItems() filters by trip_id, not the primary key, so a DELETE's
-- default (primary-key-only) replication payload can't satisfy that
-- filter and the event is silently dropped (see schema.sql's note next
-- to `expenses replica identity full`). FULL replica identity fixes it.
alter table public.packing_items replica identity full;
