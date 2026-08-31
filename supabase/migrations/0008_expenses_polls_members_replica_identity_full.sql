-- Deletes on expenses/polls/trip_members weren't reflected live (Budget
-- Planner's "By Category"/total-spent, the Expense Tracker list, Voting,
-- and the Group member roster all needed a full leave-and-reopen to
-- show a deletion) because a DELETE event's replication payload only
-- carries the deleted row's replica-identity columns — by default just
-- the primary key. Each of these tables' `.stream()` calls filters by
-- `trip_id`, which a primary-key-only payload doesn't include, so
-- Realtime can't evaluate the filter and drops the event. FULL replica
-- identity includes every column, so the filter can match again.
alter table public.expenses replica identity full;
alter table public.polls replica identity full;
alter table public.trip_members replica identity full;
