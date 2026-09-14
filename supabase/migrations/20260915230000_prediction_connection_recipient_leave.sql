-- Migration: 20260915230000_prediction_connection_recipient_leave.sql
--
-- Issue #462: a prediction-only connection's RECIPIENT has no way to end
-- it themselves. `revoke_prediction_connection`
-- (20260909200000_prediction_connections.sql) authorises only the sharer
-- (`owner_user_id`) or the profile's current accepted `primary_guardian` --
-- the recipient, who holds neither, is refused with `insufficient_privilege`
-- and has to ask the sharer to revoke on their behalf. Guardians, by
-- contrast, can already remove themselves (`revoke_guardian`'s self-leave
-- branch).
--
-- Fix: a new RPC, `leave_prediction_connection(p_connection_id uuid)`,
-- rather than widening `revoke_prediction_connection` itself -- the two
-- authorization ladders are disjoint (sharer/primary-guardian vs.
-- recipient) and keeping them as separate functions means neither error
-- message has to describe two unrelated audiences ("you must be the
-- sharer, the primary guardian, OR the recipient" reads worse than two
-- targeted messages, and each function's authority check stays a single
-- `if`). `revoke_prediction_connection` itself is untouched by this
-- migration -- not re-emitted, not edited.
--
-- `leave_prediction_connection` reaches the identical terminal state as a
-- sharer revoke: `revoked_at` is stamped (idempotent -- a second call on an
-- already-revoked connection is a no-op success, never an error), and the
-- existing `prediction_connections_projection_gc` AFTER trigger (section 5
-- of the original migration, untouched here) fires on the UPDATE and
-- deletes the profile's published `prediction_projections` snapshot in the
-- same transaction -- so the sharer's device (and the ex-recipient's own
-- next fetch) already sees no live connection, exactly like a sharer-side
-- revoke.
--
-- Authority: only the connection's own accepted recipient
-- (`recipient_user_id = auth.uid()`) may call this successfully. A pending
-- (unaccepted) invite has `recipient_user_id is null` by the table's own
-- `prediction_connections_recipient_presence_check` constraint, so it can
-- never match and is refused the same as any other non-recipient caller --
-- there is nothing for an unredeemed code's target to "leave" yet. The
-- sharer, a guardian, and an unrelated account are refused identically to
-- each other (`insufficient_privilege`), mirroring
-- `revoke_prediction_connection`'s own not-found-vs-unauthorized shape
-- (existence is not hidden -- a real, non-matching connection id and a
-- caller who is not its recipient both raise the same authorization error,
-- but a genuinely unknown id still raises the distinct `no_data_found`
-- revoke_prediction_connection already uses).
--
-- No table, policy, or grant change: the existing
-- `prediction_connections_select` policy already lets an accepted recipient
-- read their own row (needed to discover the connection id to pass here in
-- the first place), and no new column or index is required.

create or replace function public.leave_prediction_connection(
  p_connection_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conn public.prediction_connections%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn
    from public.prediction_connections
   where id = p_connection_id
   for update;
  if not found then
    raise exception 'prediction connection not found' using errcode = 'no_data_found';
  end if;

  -- Only the connection's own accepted recipient may end it this way -- the
  -- mirror image of revoke_prediction_connection's sharer/primary-guardian
  -- gate. A pending (unaccepted) invite has recipient_user_id null (the
  -- table's own presence CHECK), so it can never match and falls through to
  -- the same refusal as the sharer, a guardian, or an unrelated account.
  if v_conn.recipient_user_id is distinct from v_uid then
    raise exception 'only the connection''s recipient can leave it'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent, terminal -- there is no un-leave, matching
  -- revoke_prediction_connection's own terminal-state handling exactly.
  if v_conn.revoked_at is null then
    update public.prediction_connections
       set revoked_at = clock_timestamp()
     where id = v_conn.id;
  end if;

  -- The projection GC trigger fires on the UPDATE above (or already fired
  -- on a prior call, for the idempotent no-op branch) and deletes the
  -- profile's published snapshot in this same transaction -- the sharer's
  -- device, and this recipient's own next fetch, already sees no live
  -- connection.
  return true;
end;
$$;

comment on function public.leave_prediction_connection(uuid) is
  'Issue #462: lets a prediction-only connection''s RECIPIENT end it '
  'themselves (recipient_user_id = auth.uid()), reaching the identical '
  'terminal state and projection GC as revoke_prediction_connection() (the '
  'sharer/primary-guardian path, untouched by this migration) -- '
  'idempotent, terminal, no un-leave. A caller who is not this '
  'connection''s accepted recipient (the sharer, a guardian, or an '
  'unrelated account) is refused with insufficient_privilege; an unknown '
  'connection id raises no_data_found.';

revoke all on function public.leave_prediction_connection(uuid) from public, anon;
grant execute on function public.leave_prediction_connection(uuid) to authenticated;
