-- Adds photo/video attachments to Community posts.
--
-- `posts` gets two new nullable columns (a post can still be text-only,
-- matching AddPostScreen's existing gradient-cover flow). Media bytes
-- themselves live in a new `post-media` Storage bucket, keyed by
-- `<author_id>/<...>` so the storage policies below can check ownership
-- from the path alone. Idempotent, like 0009, since this project's tables
-- are hand-provisioned on the dashboard rather than migrated from a clean
-- state.

alter table public.posts
  add column if not exists media_url text,
  add column if not exists media_type text
    check (media_type is null or media_type in ('image', 'video'));

insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do nothing;

drop policy if exists "post_media_select_public" on storage.objects;
create policy "post_media_select_public" on storage.objects
  for select to public using (bucket_id = 'post-media');

drop policy if exists "post_media_insert_own_folder" on storage.objects;
create policy "post_media_insert_own_folder" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "post_media_delete_own_folder" on storage.objects;
create policy "post_media_delete_own_folder" on storage.objects
  for delete to authenticated using (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
