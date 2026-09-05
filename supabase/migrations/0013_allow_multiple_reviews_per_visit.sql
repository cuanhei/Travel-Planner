-- Reviews used to be capped at one per (place_name, author_id) forever.
-- Product change: a user should get one review per *visit*, so visiting
-- the same place again on a later trip unlocks another review of it —
-- see TripService.visitCount / CommunityService.myReviewCount /
-- addReview, which now gate and always insert rather than upsert.
-- The old uniqueness (added in 0009) would reject that second insert
-- outright, so it has to go.

alter table public.reviews
  drop constraint if exists reviews_place_author_unique;
