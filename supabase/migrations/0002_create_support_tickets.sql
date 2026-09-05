-- Support tickets: backs the Help Center's "Contact Support" compose screen.
-- There's no real outbound email here — sending a message just inserts a
-- row, and a reply is a row too (added by whoever is on support duty, via
-- the Supabase Table Editor), so the customer sees it next time they open
-- the thread in the app. Run this once in the Supabase SQL Editor against
-- the shared project.

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  subject text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets (id) on delete cascade,
  sender text not null check (sender in ('customer', 'support')),
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;

-- Each user can only see and create their own tickets.
create policy "Users can view their own tickets"
  on public.support_tickets for select
  using (auth.uid() = user_id);

create policy "Users can create their own tickets"
  on public.support_tickets for insert
  with check (auth.uid() = user_id);

-- Each user can only see messages on tickets they own, and can only add
-- messages as the customer — a `sender = 'support'` reply can only be
-- inserted by the dashboard (using the service_role key, which bypasses
-- RLS), never by the app itself.
create policy "Users can view messages on their own tickets"
  on public.support_messages for select
  using (
    exists (
      select 1 from public.support_tickets t
      where t.id = ticket_id and t.user_id = auth.uid()
    )
  );

create policy "Users can send customer messages on their own tickets"
  on public.support_messages for insert
  with check (
    sender = 'customer'
    and exists (
      select 1 from public.support_tickets t
      where t.id = ticket_id and t.user_id = auth.uid()
    )
  );
