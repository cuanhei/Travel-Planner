-- Expense Tracker: an expense can now carry several receipt/reference
-- photos instead of just one. Replaces the single `photo_url` column
-- (added in migration 0011) with `photo_urls text[]`, carrying over any
-- photo already uploaded under the old column before dropping it.

alter table public.expenses
  add column if not exists photo_urls text[] not null default '{}';

update public.expenses
set photo_urls = array[photo_url]
where photo_url is not null
  and (photo_urls is null or array_length(photo_urls, 1) is null);

alter table public.expenses
  drop column if exists photo_url;
