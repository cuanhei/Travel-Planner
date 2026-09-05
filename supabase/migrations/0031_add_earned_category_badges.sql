-- Stores which Achievement categories ('trip', 'budget', 'community') a
-- user has 100% completed, computed and written by their own session
-- (see AchievementService.syncCategoryBadges) whenever their stats are
-- loaded. Stored on the profile row — rather than recomputed live by
-- whoever is viewing it — because `profiles_select_authenticated` lets
-- any signed-in user read this, but the underlying trip/expense tables
-- are RLS-scoped to shared trips only, so a stranger's session could
-- never compute another user's full stats accurately. This column is
-- the one piece of achievement data safe to expose to other viewers
-- (Community profile view, Privacy & Security → Preview My Profile).
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists earned_category_badges text[] not null default '{}';
