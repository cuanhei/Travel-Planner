-- "Your Requests" (Join Trip screen) needs to show which trip a pending
-- or decided join request is for — name, destination, dates — but a
-- requester isn't a trip member yet, so trips_select_members alone
-- doesn't cover it. Add a policy letting a requester read the trip row
-- for any join request they've filed, regardless of status.
create policy "trips_select_requesters" on public.trips
  for select to authenticated
  using (
    exists (
      select 1 from public.trip_join_requests r
      where r.trip_id = trips.id and r.user_id = auth.uid()
    )
  );
