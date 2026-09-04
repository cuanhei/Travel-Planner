-- Adds real, geocoded Starting-From/Ending-At anchors to `trips` (see
-- trip_planning_and_stop_scheduling_flow.md §2.1/§16 — "Starting
-- location"). Previously Create Trip only collected start_city/end_city
-- as plain display strings with no coordinates, so the scheduling engine
-- had nothing to anchor Day 1's start / the last day's end to when no
-- accommodation covered that side of the trip.
--
-- Modeled as two nullable references into `trip_stops` (not a jsonb blob
-- or bare lat/lng columns) so the picked place goes through the exact
-- same save path as every other stop (`TripService.addStops` /
-- `TripStopLocation.toInsertMap`) and carries the same scheduling-
-- relevant fields (opening hours, category, etc.) — the same shape
-- `trip_accommodations.stop_id` already uses, just as direct columns
-- since there's no per-night dimension here (one start, one end, for the
-- whole trip).
--
-- Run this once in the Supabase SQL Editor against a project that already
-- has schema.sql (plus prior migrations) applied. On a brand-new project,
-- just run schema.sql — it already has this merged shape built in.

alter table public.trips
  add column if not exists start_location_stop_id uuid
    references public.trip_stops (id) on delete set null,
  add column if not exists end_location_stop_id uuid
    references public.trip_stops (id) on delete set null;
