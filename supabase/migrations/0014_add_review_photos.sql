-- Adds photo attachments to place reviews (CLAUDE.md's "Add Review: Submit
-- rating and photos" — only the rating/body were wired up before).
--
-- `reviews` gets a nullable `photo_urls text[]` column (a review can still
-- be text-only). Photo bytes live in a new `review-media` Storage bucket,
-- keyed by `<author_id>/<...>` so the storage policies below can check
-- ownership from the path alone — same shape as `post-media` in
-- 0010_add_post_media.sql. Idempotent, like the other migrations here,
-- since this project's tables are hand-provisioned on the dashboard rather
-- than migrated from a clean state.

alter table public.reviews
  add column if not exists photo_urls text[];

insert into storage.buckets (id, name, public)
values ('review-media', 'review-media', true)
on conflict (id) do nothing;

drop policy if exists "review_media_select_public" on storage.objects;
create policy "review_media_select_public" on storage.objects
  for select to public using (bucket_id = 'review-media');

drop policy if exists "review_media_insert_own_folder" on storage.objects;
create policy "review_media_insert_own_folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'review-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "review_media_delete_own_folder" on storage.objects;
create policy "review_media_delete_own_folder" on storage.objects
  for delete to authenticated using (
    bucket_id = 'review-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
