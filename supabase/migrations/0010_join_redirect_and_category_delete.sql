-- 1. Join Trip: resolve an invite code to a trip_id when the caller is
-- already a member, so the app can redirect them to Trip Details instead
-- of just showing a raw "already a member" error with nowhere to go.
create function public.find_my_trip_by_code(p_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_trip_id uuid;
begin
  select trip_id into v_trip_id
  from public.trip_invites
  where code = upper(p_code);

  if v_trip_id is null or not public.is_trip_member(v_trip_id) then
    return null;
  end if;

  return v_trip_id;
end;
$$;

-- 2. Budget Planner: organizer-only "delete category", which also wipes
-- every expense logged under it (so total spent updates correctly).
create function public.delete_budget_category(p_trip_id uuid, p_label text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_trip_organizer(p_trip_id) then
    raise exception 'Only the organizer can delete a budget category';
  end if;

  delete from public.expenses
  where trip_id = p_trip_id and category = p_label;

  delete from public.budget_categories
  where trip_id = p_trip_id and label = p_label;
end;
$$;

-- Lock down direct table access to match: planning (insert/update) stays
-- open to any member, but only the organizer can delete a category —
-- delete_budget_category() above is the only supported delete path.
drop policy if exists "categories_write_members" on public.budget_categories;
create policy "categories_upsert_members" on public.budget_categories
  for insert to authenticated with check (public.is_trip_member(trip_id));
create policy "categories_update_members" on public.budget_categories
  for update to authenticated using (public.is_trip_member(trip_id));
create policy "categories_delete_organizer" on public.budget_categories
  for delete to authenticated using (public.is_trip_organizer(trip_id));

-- budget_categories rows are now actually deleted through the app for
-- the first time — needs full replica identity so watchCategories'
-- trip_id-filtered stream sees the DELETE event (same issue fixed for
-- expenses/polls/trip_members in migration 0008).
alter table public.budget_categories replica identity full;
