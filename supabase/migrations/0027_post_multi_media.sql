-- Lets a post carry up to 3 photos/videos instead of just one.
--
-- `posts` gets two new parallel array columns; the old single `media_url`/
-- `media_type` columns are left in place (still readable) but the app
-- stops writing to them — existing single-media posts are backfilled into
-- the new arrays so they keep showing their photo/video.
alter table public.posts
  add column if not exists media_urls text[],
  add column if not exists media_types text[];

update public.posts
set media_urls = array[media_url], media_types = array[media_type]
where media_url is not null and media_urls is null;

-- 0021_add_post_updated_at.sql's trigger checked the old singular
-- media_url/media_type columns for "did the post's content change" — now
-- that the app writes media_urls/media_types instead, it needs to check
-- those instead, or editing a post's photos/videos would silently stop
-- marking it "Edited".
create or replace function public.handle_post_content_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.place_name is distinct from old.place_name
     or new.caption is distinct from old.caption
     or new.category is distinct from old.category
     or new.media_urls is distinct from old.media_urls
     or new.media_types is distinct from old.media_types then
    new.updated_at = now();
  end if;
  return new;
end;
$$;
