-- Recent sign-in history (Privacy & Security > Login Activity) — lets a
-- user see when their account was last signed into and from what kind of
-- device, so they can notice unrecognized access. Recorded automatically
-- via the `auth.onAuthStateChange` listener in `main.dart` (fires on an
-- actual new sign-in — password or Google OAuth — not on a page reload
-- that merely restores an existing session), not called from the sign-in
-- screens directly.
--
-- Run once in the Supabase SQL Editor for this project.

create table if not exists public.login_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  signed_in_at timestamptz not null default now(),
  device_info text
);

alter table public.login_activity enable row level security;

create policy "Users can view their own login activity"
  on public.login_activity for select
  using (auth.uid() = user_id);

create policy "Users can record their own login activity"
  on public.login_activity for insert
  with check (auth.uid() = user_id);

-- No update/delete policy for the client — rows are pruned only via the
-- function below, which is scoped to auth.uid() regardless of what's
-- passed in, so one user can never delete another's history.
create or replace function public.prune_login_activity(p_keep int default 20)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.login_activity
  where user_id = auth.uid()
  and id not in (
    select id from public.login_activity
    where user_id = auth.uid()
    order by signed_in_at desc
    limit p_keep
  );
end;
$$;

grant execute on function public.prune_login_activity(int) to authenticated;
