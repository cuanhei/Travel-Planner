-- Adds `posts.updated_at` so the feed/detail screen can show an "Edited"
-- label once a post's own author changes it — nothing before this tracked
-- edits at all (posts only had `created_at`, which never moves).
--
-- Existing rows are backfilled to `created_at` (not `now()`) so a post that
-- has never actually been edited doesn't retroactively show as "Edited"
-- the moment this migration runs.
alter table public.posts add column if not exists updated_at timestamptz;
update public.posts set updated_at = created_at where updated_at is null;
alter table public.posts alter column updated_at set default now();
alter table public.posts alter column updated_at set not null;

-- Bump `updated_at` only when the post's own content changes — not when
-- `likes_count`/`comments_count` are updated by the like/comment triggers
-- in 0009_community_module.sql, which would otherwise mark a post
-- "Edited" just because someone reacted to or commented on it.
create or replace function public.handle_post_content_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.place_name is distinct from old.place_name
     or new.caption is distinct from old.caption
     or new.category is distinct from old.category
     or new.media_url is distinct from old.media_url
     or new.media_type is distinct from old.media_type then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists on_posts_content_updated on public.posts;
create trigger on_posts_content_updated
  before update on public.posts
  for each row execute function public.handle_post_content_updated_at();
