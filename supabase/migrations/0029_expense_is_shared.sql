-- Lets a traveler mark an expense as personal (not split with the
-- group) instead of every logged expense automatically counting toward
-- the equal-split settle-up plan. Personal expenses still show in the
-- Budget Planner's totals/category breakdown (it's still money spent on
-- the trip) — they're just excluded from BudgetService.getBalances()'s
-- paid/fair-share calculation.
alter table public.expenses
  add column is_shared boolean not null default true;
