-- Lets Emergency Contact match a contact's phone number against a signed-up
-- TravelPlanner account, so the contact list can show that user's live
-- profile photo/name (and link to their "Preview My Profile" page) instead
-- of just the manually-typed name — re-checked every time the list loads,
-- so a contact who signs up *after* being added picks up the link
-- automatically, with no need to re-add them.
--
-- `profiles` is already readable by any authenticated user (see
-- `profiles_select_authenticated` in schema.sql), so this doesn't expose
-- anything new — it's purely a convenience for matching many phone numbers
-- at once without pulling every row to the client to normalize there.
--
-- Run once in the Supabase SQL Editor for this project.

create or replace function public.find_profiles_by_phone(p_phones text[])
returns table (matched_phone text, id uuid)+
language sql
security definer
set search_path = public
stable
as $$
  select input.phone as matched_phone, p.id
  from unnest(p_phones) as input(phone)
  join public.profiles p
    on p.phone is not null
    and regexp_replace(p.phone, '\D', '', 'g') = regexp_replace(input.phone, '\D', '', 'g');
$$;

grant execute on function public.find_profiles_by_phone(text[]) to authenticated;
