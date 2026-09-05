-- Direct Message read receipts (sender-side blue tick): the sender of
-- a DM needs to see the *recipient's* direct_message_reads row (to know
-- whether/when they've read up to that message), but the original
-- policy only let a user see their own row (user_id = auth.uid()) —
-- which is exactly backwards for this. Widen it to both participants.

drop policy "direct_message_reads_select_own" on public.direct_message_reads;

create policy "direct_message_reads_select_participant" on public.direct_message_reads
  for select to authenticated
  using (user_id = auth.uid() or other_user_id = auth.uid());
