-- Personal expenses (is_shared = false) are meant to be private, but
-- expenses_select_members let any trip member read every expense row for
-- the trip regardless of is_shared — so a member's personal spending was
-- silently visible (and folded into totals/category breakdowns) for
-- every other member, organizer included. Tighten SELECT to: shared rows
-- stay visible to the whole trip, personal rows are visible only to the
-- member who logged them. Mirror the same is_shared check into
-- update/delete so the organizer's blanket access no longer reaches
-- another member's personal rows either.
drop policy "expenses_select_members" on public.expenses;
create policy "expenses_select_members" on public.expenses
  for select to authenticated
  using (
    public.is_trip_member(trip_id)
    and (is_shared or user_id = auth.uid())
  );

drop policy "expenses_update_owner_or_organizer" on public.expenses;
create policy "expenses_update_owner_or_organizer" on public.expenses
  for update to authenticated
  using (
    user_id = auth.uid()
    or (is_shared and public.is_trip_organizer(trip_id))
  );

drop policy "expenses_delete_owner_or_organizer" on public.expenses;
create policy "expenses_delete_owner_or_organizer" on public.expenses
  for delete to authenticated
  using (
    user_id = auth.uid()
    or (is_shared and public.is_trip_organizer(trip_id))
  );
