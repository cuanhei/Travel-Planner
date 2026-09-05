-- Upgrades the single like on a Community post into a small set of emoji
-- reactions (like/love/wow — see `_reactionEmojis` in
-- lib/screens/community/post_card.dart). `post_likes` already gives us one
-- row per (post_id, user_id); this just tags each row with which reaction
-- it is, so a user still has at most one reaction per post (picking a new
-- one replaces the old one, same as toggling a plain like used to).
--
-- `posts.reaction_counts` is a `{type: count}` breakdown maintained by the
-- trigger below, so the feed can render "👍 3 ❤️ 1" without a join/count
-- query on every row. `posts.likes_count` is kept as the all-types total
-- (existing callers/analytics that just want "how many reactions" still
-- work unchanged).
--
-- Idempotent, like 0009/0010, since this project's tables are
-- hand-provisioned rather than migrated from a clean state.

alter table public.posts
  add column if not exists reaction_counts jsonb not null default '{}'::jsonb;

alter table public.post_likes
  add column if not exists reaction_type text not null default 'like';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.post_likes'::regclass
      and conname = 'post_likes_reaction_type_check'
  ) then
    alter table public.post_likes
      add constraint post_likes_reaction_type_check
      check (reaction_type in ('like', 'love', 'wow'));
  end if;
end $$;

-- Recompute every post's breakdown from the actual post_likes rows —
-- covers both a fresh install (nothing to do) and upgrading a project
-- that already had plain likes (which just became `reaction_type = 'like'`
-- via the column default above).
update public.posts p
set reaction_counts = coalesce(
  (
    select jsonb_object_agg(t.reaction_type, t.cnt)
    from (
      select reaction_type, count(*) as cnt
      from public.post_likes
      where post_id = p.id
      group by reaction_type
    ) t
  ),
  '{}'::jsonb
);

-- Replaces the insert/delete-only trigger from 0009 with one that also
-- handles UPDATE, since changing your reaction (like -> love) updates the
-- existing row in place instead of delete-then-insert.
create or replace function public.handle_post_like_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
    set likes_count = likes_count + 1,
        reaction_counts = jsonb_set(
          reaction_counts,
          array[new.reaction_type],
          to_jsonb(coalesce((reaction_counts ->> new.reaction_type)::int, 0) + 1)
        )
    where id = new.post_id;
    return new;
  elsif tg_op = 'UPDATE' then
    if new.reaction_type is distinct from old.reaction_type then
      update public.posts
      set reaction_counts = jsonb_set(
            jsonb_set(
              reaction_counts,
              array[old.reaction_type],
              to_jsonb(greatest(coalesce((reaction_counts ->> old.reaction_type)::int, 0) - 1, 0))
            ),
            array[new.reaction_type],
            to_jsonb(coalesce((reaction_counts ->> new.reaction_type)::int, 0) + 1)
          )
      where id = new.post_id;
    end if;
    return new;
  else
    update public.posts
    set likes_count = greatest(likes_count - 1, 0),
        reaction_counts = jsonb_set(
          reaction_counts,
          array[old.reaction_type],
          to_jsonb(greatest(coalesce((reaction_counts ->> old.reaction_type)::int, 0) - 1, 0))
        )
    where id = old.post_id;
    return old;
  end if;
end;
$$;

drop trigger if exists on_post_like_change on public.post_likes;
create trigger on_post_like_change
  after insert or update or delete on public.post_likes
  for each row execute function public.handle_post_like_change();
