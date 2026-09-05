-- Adds columns/policies backing five chat features: reply/quote,
-- @mention (group only), edit + delete-for-everyone, pin, and (no
-- schema needed) the typing indicator, which rides purely on Realtime
-- Broadcast.

alter table public.group_messages
  add column reply_to_id uuid references public.group_messages (id) on delete set null,
  add column edited_at timestamptz,
  add column deleted_at timestamptz,
  add column mentioned_user_ids uuid[] not null default '{}',
  add column pinned_at timestamptz;

-- The original content check ("must have a body or an attachment")
-- would otherwise reject the soft-delete update below, which clears
-- both.
alter table public.group_messages
  drop constraint group_messages_content_check,
  add constraint group_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0 or deleted_at is not null
  );

alter table public.direct_messages
  add column reply_to_id uuid references public.direct_messages (id) on delete set null,
  add column edited_at timestamptz,
  add column deleted_at timestamptz,
  add column pinned_at timestamptz;

alter table public.direct_messages
  drop constraint direct_messages_content_check,
  add constraint direct_messages_content_check check (
    attachment_url is not null or char_length(trim(body)) > 0 or deleted_at is not null
  );

-- Was missing entirely before (comment on messages_select_members said
-- "only the author can edit ... their own message", but no UPDATE
-- policy actually existed) — needed now for both editing a message's
-- body and soft-deleting it for everyone (clearing body/attachment,
-- setting deleted_at, done via the same "own row" update rather than
-- the existing hard DELETE policy, so the message can still show a
-- "This message was deleted" placeholder instead of just vanishing).
create policy "messages_update_own" on public.group_messages
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "direct_messages_update_own" on public.direct_messages
  for update to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- Pinning is the one message action any trip member can take on a
-- message that isn't theirs, so it can't go through the "own row"
-- update policies above — routed through these instead. Passing a null
-- p_message_id just unpins whatever's currently pinned; passing one
-- pins it and unpins whatever was pinned before (only one pin per
-- conversation at a time).
create function public.set_pinned_group_message(p_trip_id uuid, p_message_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_trip_member(p_trip_id) then
    raise exception 'Not a member of this trip';
  end if;
  if p_message_id is not null and not exists (
    select 1 from public.group_messages
    where id = p_message_id and trip_id = p_trip_id and deleted_at is null
  ) then
    raise exception 'Message not found in this trip';
  end if;

  update public.group_messages
  set pinned_at = null
  where trip_id = p_trip_id and pinned_at is not null;

  if p_message_id is not null then
    update public.group_messages
    set pinned_at = now()
    where id = p_message_id;
  end if;
end;
$$;

-- Same idea for a DM: p_message_id null unpins; otherwise pins it
-- (unpinning whatever was pinned in that same conversation before) —
-- the conversation is identified by the message's own trip_id/sender/
-- recipient once resolved, so the caller only ever needs to be one of
-- the two participants of whichever message is involved.
create function public.set_pinned_direct_message(
  p_trip_id uuid,
  p_other_user_id uuid,
  p_message_id uuid
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_sender uuid;
  v_recipient uuid;
begin
  if p_message_id is not null then
    select sender_id, recipient_id into v_sender, v_recipient
    from public.direct_messages
    where id = p_message_id and deleted_at is null;

    if v_sender is null then
      raise exception 'Message not found';
    end if;
    if auth.uid() not in (v_sender, v_recipient) then
      raise exception 'Not a participant of this conversation';
    end if;
  end if;

  update public.direct_messages
  set pinned_at = null
  where trip_id = p_trip_id
    and pinned_at is not null
    and ((sender_id = auth.uid() and recipient_id = p_other_user_id)
      or (sender_id = p_other_user_id and recipient_id = auth.uid()));

  if p_message_id is not null then
    update public.direct_messages
    set pinned_at = now()
    where id = p_message_id;
  end if;
end;
$$;
