-- 0009 gave `post_likes` select/insert/delete RLS policies but no UPDATE
-- one. That was invisible while a "like" was just add/remove (delete +
-- insert), but CommunityService.setReaction does a real UPDATE when
-- switching an existing reaction to a different type (e.g. like -> love),
-- and RLS silently drops writes with no matching policy — the row just
-- doesn't change, no error. Idempotent, like the others.

drop policy if exists "post_likes_update_own" on public.post_likes;
create policy "post_likes_update_own" on public.post_likes
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
