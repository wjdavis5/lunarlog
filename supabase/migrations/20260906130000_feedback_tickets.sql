-- Migration: 20260906130000_feedback_tickets.sql
-- Renamed from an original 20260905120000_ prefix (PR #105 review, item 3):
-- main already carries 20260906120000_account_deletion_final_rehome.sql
-- (merged via PR #106) by the time this PR's feedback migrations landed, so
-- this file (and the two after it) is renamed to sort after it rather than
-- before - see AGENTS.md's Migration Flow section for the full rationale
-- and what was/wasn't verifiable about the remote project's actual state.
--
-- Implements Issue #6 (U1): in-app feedback tickets and admin replies.
-- 1. Create public.feedback_tickets with content, diagnostics, and status
--    columns, an allowlist check on device_info, and length/shape checks.
-- 2. Add public.is_allowed_device_info(jsonb): the server-side diagnostics
--    allowlist (KTD3) so a future client bug cannot widen the payload.
-- 3. Create public.feedback_replies, threaded off feedback_tickets.
-- 4. Indexes for the two common access paths.
-- 5. Enable and force RLS on both tables.
-- 6. Policies: select/insert on tickets (plus an owner-scoped update so U5
--    can attach a screenshot after insert), select/insert on replies via
--    the owns_feedback_ticket() helper. No delete anywhere; no update on
--    replies (a posted reply is immutable); no policy admits an
--    author_type='admin' insert via the authenticated role - admin replies
--    are written only by service_role, which bypasses RLS entirely.
-- 7. Column-list grants: status is never granted for direct write, so it
--    moves only through the feedback_replies-insert trigger below.
-- 8. Rate-limit trigger (5 tickets/hour/caller) and the reply-driven status
--    trigger (admin reply -> replied; user reply on a replied ticket ->
--    triage).

-- ---------------------------------------------------------------------------
-- 1. feedback_tickets
-- ---------------------------------------------------------------------------

create table public.feedback_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references auth.users (id) on delete cascade,
  reply_email text not null
    constraint feedback_tickets_reply_email_check
    check (
      char_length(reply_email) <= 254
      and reply_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    ),
  category text not null
    constraint feedback_tickets_category_check
    check (category in ('bug', 'feature_request', 'support', 'other')),
  message text not null
    constraint feedback_tickets_message_check
    check (char_length(message) between 1 and 4000),
  device_info jsonb not null default '{}'::jsonb,
  attachment_paths text[] not null default '{}'
    constraint feedback_tickets_attachment_paths_check
    check (array_length(attachment_paths, 1) is null or array_length(attachment_paths, 1) <= 3),
  status text not null default 'new'
    constraint feedback_tickets_status_check
    check (status in ('new', 'triage', 'replied', 'resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.feedback_tickets is
  'In-app feedback/bug/support tickets submitted by a signed-in operator (Issue #6). status is server-owned and moves only via the feedback_replies insert trigger.';
comment on column public.feedback_tickets.device_info is
  'Diagnostics payload; every key must be in the KTD3 allowlist (see is_allowed_device_info) so a client bug can never widen this beyond app/OS metadata and breadcrumbs.';
comment on column public.feedback_tickets.attachment_paths is
  'Object paths (not URLs) in the private feedback-attachments bucket, shaped <uid>/<ticket_id>/<uuid>.<ext>. A private bucket has no durable URL; reads mint a signed URL on demand.';
comment on column public.feedback_tickets.status is
  'new -> triage -> replied -> resolved. Not writable by authenticated (see grants below); it moves only through the feedback_replies_touch_ticket trigger.';

-- ---------------------------------------------------------------------------
-- 2. is_allowed_device_info: the KTD3 server-side diagnostics allowlist
-- ---------------------------------------------------------------------------

create or replace function public.is_allowed_device_info(p_device_info jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select
    jsonb_typeof(p_device_info) = 'object'
    and (
      select bool_and(
        key in ('os', 'os_version', 'model', 'app_version', 'build_number', 'locale', 'breadcrumbs')
      )
      from jsonb_object_keys(p_device_info) as key
    ) is not false;
$$;

comment on function public.is_allowed_device_info(jsonb) is
  'KTD3: true only when every top-level key of the value is in the fixed diagnostics allowlist. Used as feedback_tickets_device_info_check so the server enforces R9 independently of the client.';

alter table public.feedback_tickets
  add constraint feedback_tickets_device_info_check
  check (public.is_allowed_device_info(device_info));

grant execute on function public.is_allowed_device_info(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. feedback_replies
-- ---------------------------------------------------------------------------

create table public.feedback_replies (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null
    references public.feedback_tickets (id) on delete cascade,
  author_type text not null
    constraint feedback_replies_author_type_check
    check (author_type in ('user', 'admin')),
  message text not null
    constraint feedback_replies_message_check
    check (char_length(message) between 1 and 4000),
  created_at timestamptz not null default now()
);

comment on table public.feedback_replies is
  'Thread on a feedback_tickets row. An admin reply is written only by service_role (bypasses RLS); a user reply is written by the ticket owner. Replies are immutable once posted - no update policy.';

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------

create index feedback_tickets_user_created_idx
  on public.feedback_tickets (user_id, created_at desc);

create index feedback_replies_ticket_created_idx
  on public.feedback_replies (ticket_id, created_at);

-- ---------------------------------------------------------------------------
-- 5. Row-Level Security
-- ---------------------------------------------------------------------------

alter table public.feedback_tickets enable row level security;
alter table public.feedback_tickets force row level security;
alter table public.feedback_replies enable row level security;
alter table public.feedback_replies force row level security;

-- ---------------------------------------------------------------------------
-- 6. Policies
-- ---------------------------------------------------------------------------

create policy "feedback_tickets_select" on public.feedback_tickets
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "feedback_tickets_insert" on public.feedback_tickets
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Owner-scoped update, restricted in practice to the granted column list
-- below (attachment_paths, updated_at) so U5 can attach a screenshot after
-- the initial insert. status and every content column stay read-only after
-- creation because they are simply not in that grant.
create policy "feedback_tickets_update" on public.feedback_tickets
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Deliberately absent: no delete policy on feedback_tickets. A submitted
-- ticket is a record the operator team may need for the thread; deletion
-- (and attachment purge) is a manual dashboard action, not a client path.

create or replace function public.owns_feedback_ticket(p_ticket_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.feedback_tickets
     where id = p_ticket_id
       and user_id = p_user_id
  );
$$;

comment on function public.owns_feedback_ticket(uuid, uuid) is
  'RLS helper (security definer to avoid recursive feedback_tickets policy evaluation): true when p_user_id owns the ticket p_ticket_id.';

grant execute on function public.owns_feedback_ticket(uuid, uuid) to authenticated;

create policy "feedback_replies_select" on public.feedback_replies
  for select to authenticated
  using (public.owns_feedback_ticket(ticket_id, (select auth.uid())));

-- author_type = 'user' is required here (not just by the column grant,
-- which does not exist for author_type client-side control - see below):
-- this is the one place that keeps an authenticated caller from ever
-- inserting an 'admin' row through PostgREST. Admin replies are written
-- exclusively by service_role, which bypasses RLS and this policy entirely.
create policy "feedback_replies_insert" on public.feedback_replies
  for insert to authenticated
  with check (
    author_type = 'user'
    and public.owns_feedback_ticket(ticket_id, (select auth.uid()))
  );

-- Deliberately absent: no update policy on feedback_replies (a posted
-- reply, from either side, is immutable) and no delete policy on either
-- table (see feedback_tickets_update's comment above).

-- ---------------------------------------------------------------------------
-- 7. Privileges
-- ---------------------------------------------------------------------------

revoke all on table public.feedback_tickets from public, anon, authenticated;
grant select on table public.feedback_tickets to authenticated;
grant insert (user_id, reply_email, category, message, device_info) on table public.feedback_tickets to authenticated;
grant update (attachment_paths, updated_at) on table public.feedback_tickets to authenticated;

revoke all on table public.feedback_replies from public, anon, authenticated;
grant select on table public.feedback_replies to authenticated;
grant insert (ticket_id, author_type, message) on table public.feedback_replies to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Triggers
-- ---------------------------------------------------------------------------

create or replace function public.feedback_tickets_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recent_count integer;
begin
  select count(*) into v_recent_count
    from public.feedback_tickets
   where user_id = new.user_id
     and created_at > clock_timestamp() - interval '1 hour';

  if v_recent_count >= 5 then
    raise exception 'feedback rate limit exceeded' using errcode = '55000';
  end if;

  return new;
end;
$$;

comment on function public.feedback_tickets_rate_limit() is
  'R17: refuses a 6th feedback_tickets insert by the same caller within a trailing hour. A trigger (not a policy) so it is directly assertable with throws_ok.';

create trigger feedback_tickets_rate_limit
  before insert on public.feedback_tickets
  for each row execute function public.feedback_tickets_rate_limit();

create or replace function public.feedback_replies_touch_ticket()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.author_type = 'admin' then
    update public.feedback_tickets
       set status = 'replied',
           updated_at = clock_timestamp()
     where id = new.ticket_id;
  elsif new.author_type = 'user' then
    update public.feedback_tickets
       set status = 'triage',
           updated_at = clock_timestamp()
     where id = new.ticket_id
       and status = 'replied';
  end if;
  return new;
end;
$$;

comment on function public.feedback_replies_touch_ticket() is
  'R18: an admin reply moves its ticket to replied; a user reply on a replied ticket moves it back to triage. The only path status ever changes through.';

create trigger feedback_replies_touch_ticket
  after insert on public.feedback_replies
  for each row execute function public.feedback_replies_touch_ticket();

revoke execute on function public.feedback_tickets_rate_limit() from public, anon, authenticated;
revoke execute on function public.feedback_replies_touch_ticket() from public, anon, authenticated;
