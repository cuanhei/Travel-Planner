-- `trip_stops` is streamed by both TripService.watchTripStops (Emergency
-- Contacts) and BudgetService.watchStopNames, but was never added to the
-- `supabase_realtime` publication — neither here nor in schema.sql's own
-- baseline list of streamed tables. Confirmed live: subscribing throws
-- `RealtimeSubscribeException: Unable to subscribe to changes ... Please
-- check Realtime is enabled`, which StreamBuilder surfaces as `hasData:
-- false, hasError: true` — indistinguishable from "still loading" in
-- Emergency Contacts' UI, so the screen spins forever instead of ever
-- showing an error or the actual stops.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trip_stops'
  ) then
    alter publication supabase_realtime add table public.trip_stops;
  end if;
end $$;
