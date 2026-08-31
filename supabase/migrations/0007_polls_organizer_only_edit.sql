-- Voting screen: only the trip organizer may edit/delete a poll — a
-- non-organizer member who created a poll could previously still edit or
-- delete it themselves. Tighten the RLS policies to match.

drop policy if exists "polls_update_owner_or_organizer" on public.polls;
drop policy if exists "polls_update_organizer" on public.polls;
create policy "polls_update_organizer" on public.polls
  for update to authenticated
  using (public.is_trip_organizer(trip_id));

drop policy if exists "polls_delete_owner_or_organizer" on public.polls;
drop policy if exists "polls_delete_organizer" on public.polls;
create policy "polls_delete_organizer" on public.polls
  for delete to authenticated
  using (public.is_trip_organizer(trip_id));

drop policy if exists "poll_options_write_owner_or_organizer" on public.poll_options;
drop policy if exists "poll_options_write_organizer" on public.poll_options;
create policy "poll_options_write_organizer" on public.poll_options
  for all to authenticated
  using (
    exists (
      select 1 from public.polls p
      where p.id = poll_id
        and public.is_trip_organizer(p.trip_id)
    )
  );
