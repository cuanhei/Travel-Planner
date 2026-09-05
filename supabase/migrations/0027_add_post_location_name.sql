-- The human-readable place name (e.g. "George Town, Bayan Lepas") shown
-- alongside the IP in PostCard's "IP: <address> (<location>)" line —
-- captured from the poster's GPS position at post time (reverse-geocoded
-- via Photon), the same way ip_address is (see 0026_post_ip_and_location_
-- sharing.sql and CommunityService.addPost). Gated by the same Location
-- Sharing setting as the IP itself.
--
-- Run once in the Supabase SQL Editor for this project.

alter table public.posts
  add column if not exists location_name text;
