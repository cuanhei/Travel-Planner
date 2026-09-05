-- Community post "IP" line (Settings → Privacy & Security → "Location
-- Sharing"). The poster's IP is always captured on every post (see
-- CommunityService.addPost) regardless of this setting — it only controls
-- whether PostCard *displays* it (the real address) or hides it (shows
-- "Unknown"), and it's read live from the author's current preference
-- rather than frozen at post time, so flipping the switch immediately
-- changes what already-published posts show. Defaults to true so existing
-- accounts keep today's behavior until they turn it off.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.profiles
  add column if not exists location_sharing_enabled boolean not null default true;

alter table public.posts
  add column if not exists ip_address text;
