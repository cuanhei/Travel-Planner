-- Lets a comment be a reply to another comment on the same post, for
-- threaded replies under a top-level comment. `on delete cascade` means
-- deleting a top-level comment also removes every reply under it.
alter table public.comments
  add column if not exists parent_comment_id uuid
    references public.comments (id) on delete cascade;

create index if not exists comments_parent_comment_id_idx
  on public.comments (parent_comment_id);
