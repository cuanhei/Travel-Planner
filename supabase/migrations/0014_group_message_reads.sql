-- Group Chat read receipts: records when each member has seen a
-- message, so the sender can see a WhatsApp-style single tick (sent)
-- vs. blue double tick (seen), and when. trip_id is denormalized here
-- (rather than joined through group_messages) so RLS and the chat
-- screen's realtime `.stream()` can both filter directly on it, same
-- as every other per-trip table.

create table public.group_message_reads (
  message_id uuid not null references public.group_messages (id) on delete cascade,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.group_message_reads enable row level security;

create policy "message_reads_select_members" on public.group_message_reads
  for select to authenticated using (public.is_trip_member(trip_id));
-- Each member can only ever record their own read receipt.
create policy "message_reads_insert_self" on public.group_message_reads
  for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());

alter publication supabase_realtime add table public.group_message_reads;

-- Full replica identity so the trip_id-filtered `.stream()` sees every
-- row's data on insert (matches migration 0008/0010/0013's reasoning).
alter table public.group_message_reads replica identity full;
