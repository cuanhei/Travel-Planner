-- Split Expenses: lets a member record a real-world payment ("Jiaying
-- paid Esther RM50 in cash") that settles part of the auto-computed
-- even split. ExpenseSplitScreen nets these against each member's
-- (paid - fair share) balance before computing who-owes-who, so a
-- settled amount doesn't keep reappearing after new expenses reshuffle
-- the settle-up pairings.

create table public.trip_settlements (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  from_user_id uuid not null references auth.users (id),
  to_user_id uuid not null references auth.users (id),
  amount numeric(12, 2) not null check (amount > 0),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

alter table public.trip_settlements enable row level security;

create policy "settlements_select_members" on public.trip_settlements
  for select to authenticated using (public.is_trip_member(trip_id));
create policy "settlements_insert_members" on public.trip_settlements
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and created_by = auth.uid());
create policy "settlements_delete_owner_or_organizer" on public.trip_settlements
  for delete to authenticated
  using (created_by = auth.uid() or public.is_trip_organizer(trip_id));

alter publication supabase_realtime add table public.trip_settlements;

-- Full replica identity so a trip_id-filtered .stream() sees DELETE
-- events (undoing a settlement) — same reasoning as migration 0008/0010.
alter table public.trip_settlements replica identity full;
