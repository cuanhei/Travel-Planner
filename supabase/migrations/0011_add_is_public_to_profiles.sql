-- Public/private profile toggle (Settings → Privacy & Security →
-- "Public Profile") — an Instagram-style switch: public shows a viewer
-- everything, private limits them to just name/bio (see
-- `view_profile_screen.dart`). Defaults to public so existing accounts
-- don't suddenly look "private" to trip-mates.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists is_public boolean not null default true;
