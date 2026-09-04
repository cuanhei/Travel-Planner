-- Community module repair script.
--
-- `posts`, `comments`, `reviews`, and `post_likes` already exist on the
-- shared project this app runs against — they were created by hand
-- directly in the Supabase dashboard, not from any SQL file in this repo,
-- so there was no guarantee they had RLS, the like/comment-count
-- triggers, or Realtime wired up correctly. This script is idempotent
-- (safe to run more than once, and safe whether a given piece below
-- already exists or not) so it can be used both to finish setting up the
-- existing tables and, on a brand-new project, to create them from
-- scratch matching the same shape as supabase/schema.sql's Community
-- section.

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  place_name text not null,
  caption text not null check (char_length(trim(caption)) > 0),
  category text not null,
  cover_gradient text not null default 'horizon',
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  place_name text not null,
  author_id uuid not null references auth.users (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  body text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);

-- post_likes and reviews may have been created without the constraints
-- CommunityService relies on for correctness (no double-like, one review
-- per user per place) — add them if missing rather than assume either way.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.post_likes'::regclass and contype = 'p'
  ) then
    alter table public.post_likes add primary key (post_id, user_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reviews'::regclass and contype = 'u'
  ) then
    alter table public.reviews add constraint reviews_place_author_unique
      unique (place_name, author_id);
  end if;
end $$;

-- Keep posts.likes_count/comments_count in sync so the feed (which only
-- streams `posts`, not post_likes/comments) can show accurate counts
-- without a join on every row.
create or replace function public.handle_post_like_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
    return new;
  else
    update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
    return old;
  end if;
end;
$$;

drop trigger if exists on_post_like_change on public.post_likes;
create trigger on_post_like_change
  after insert or delete on public.post_likes
  for each row execute function public.handle_post_like_change();

create or replace function public.handle_post_comment_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
    return new;
  else
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    return old;
  end if;
end;
$$;

drop trigger if exists on_post_comment_change on public.comments;
create trigger on_post_comment_change
  after insert or delete on public.comments
  for each row execute function public.handle_post_comment_change();

alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.reviews enable row level security;

drop policy if exists "posts_select_authenticated" on public.posts;
create policy "posts_select_authenticated" on public.posts
  for select to authenticated using (true);
drop policy if exists "posts_insert_self" on public.posts;
create policy "posts_insert_self" on public.posts
  for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own" on public.posts
  for update to authenticated using (author_id = auth.uid());
drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own" on public.posts
  for delete to authenticated using (author_id = auth.uid());

drop policy if exists "post_likes_select_authenticated" on public.post_likes;
create policy "post_likes_select_authenticated" on public.post_likes
  for select to authenticated using (true);
drop policy if exists "post_likes_insert_self" on public.post_likes;
create policy "post_likes_insert_self" on public.post_likes
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "post_likes_delete_self" on public.post_likes;
create policy "post_likes_delete_self" on public.post_likes
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "comments_select_authenticated" on public.comments;
create policy "comments_select_authenticated" on public.comments
  for select to authenticated using (true);
drop policy if exists "comments_insert_self" on public.comments;
create policy "comments_insert_self" on public.comments
  for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own" on public.comments
  for delete to authenticated using (author_id = auth.uid());

drop policy if exists "reviews_select_authenticated" on public.reviews;
create policy "reviews_select_authenticated" on public.reviews
  for select to authenticated using (true);
drop policy if exists "reviews_insert_self" on public.reviews;
create policy "reviews_insert_self" on public.reviews
  for insert to authenticated with check (author_id = auth.uid());
drop policy if exists "reviews_update_own" on public.reviews;
create policy "reviews_update_own" on public.reviews
  for update to authenticated using (author_id = auth.uid());
drop policy if exists "reviews_delete_own" on public.reviews;
create policy "reviews_delete_own" on public.reviews
  for delete to authenticated using (author_id = auth.uid());

-- Realtime: add each table only if it isn't already published (adding a
-- table that's already a publication member errors instead of no-op-ing).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'posts'
  ) then
    alter publication supabase_realtime add table public.posts;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'comments'
  ) then
    alter publication supabase_realtime add table public.comments;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reviews'
  ) then
    alter publication supabase_realtime add table public.reviews;
  end if;
end $$;

-- comments (watched filtered by post_id) and reviews (watched filtered by
-- place_name) both support deleting your own row through the app — a
-- DELETE event's replication payload only carries the replica identity's
-- columns by default (just the primary key), so a filter on a non-PK
-- column can't be evaluated and the delete is silently dropped. FULL
-- replica identity includes every column, fixing that.
alter table public.comments replica identity full;
alter table public.reviews replica identity full;
