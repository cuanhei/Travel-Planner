-- Personal emergency contacts (family/friends the user adds themselves) —
-- distinct from the Utilities module's static official-numbers list
-- (police, ambulance, etc.), which needs no table. Run this once in the
-- Supabase SQL Editor against the shared project.

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  relationship text,
  phone text not null,
  created_at timestamptz not null default now()
);

alter table public.emergency_contacts enable row level security;

-- Each user can only see, add, edit, and remove their own contacts.
create policy "Users can view their own emergency contacts"
  on public.emergency_contacts for select
  using (auth.uid() = user_id);

create policy "Users can add their own emergency contacts"
  on public.emergency_contacts for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own emergency contacts"
  on public.emergency_contacts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own emergency contacts"
  on public.emergency_contacts for delete
  using (auth.uid() = user_id);
