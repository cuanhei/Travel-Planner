-- Expense Tracker: optional receipt photo on an expense, shown in the
-- expense's detail view. Photos live in a public storage bucket (reads
-- need no auth header, so `photo_url` from getPublicUrl() just works in
-- an Image.network) with writes gated by RLS below.

alter table public.expenses
  add column if not exists photo_url text;

insert into storage.buckets (id, name, public)
values ('expense-photos', 'expense-photos', true)
on conflict (id) do nothing;

-- Objects are keyed "<trip_id>/<file>" so a policy can recover the trip
-- id from the first path segment without needing to know which expense
-- a photo belongs to (a new expense doesn't have an id yet at upload
-- time).
create policy "expense_photos_select_public" on storage.objects
  for select
  using (bucket_id = 'expense-photos');

create policy "expense_photos_insert_members" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );

create policy "expense_photos_update_owner_or_organizer" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
    and (
      owner_id = (auth.uid())::text
      or public.is_trip_organizer(((storage.foldername(name))[1])::uuid)
    )
  );

create policy "expense_photos_delete_owner_or_organizer" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'expense-photos'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
    and (
      owner_id = (auth.uid())::text
      or public.is_trip_organizer(((storage.foldername(name))[1])::uuid)
    )
  );
