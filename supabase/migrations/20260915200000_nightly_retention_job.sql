-- Migration: 20260915200000_nightly_retention_job.sql
--
-- Issue #263 (P2, epic: Privacy & Compliance): nothing on the server ever
-- ages out today. `notification_outbox` has `sent_at`
-- (20260906220000_notification_outbox.sql:29) but no delete path --
-- `sweep_notification_outbox()` (20260906230000_reminder_windows_and_cron.sql)
-- only *releases* a stuck claim, it never deletes. Tombstoned `day_entries`
-- are never removed. `feedback_tickets` have no expiry. This migration adds
-- a third cron job, `lunarlog-nightly-retention`, calling a new
-- `public.enforce_retention()` that hard-deletes rows past their window for
-- four tables: `notification_outbox`, `day_entries` (tombstones),
-- `day_entry_history`, and `feedback_tickets`.
--
-- =============================================================================
-- Retention windows chosen, and the sync-safety reasoning behind each
-- =============================================================================
--
--   notification_outbox: sent_at < now() - 30 days. A delivered (or
--   permanently-failed-and-abandoned) notification carries no ongoing
--   purpose once sent -- it is a content-free delivery record
--   (public.notification_outbox's own comment: "no column here can ever
--   hold entry content"), not a sync-visible row (it is never pulled by any
--   client -- no `authenticated` policy exists on it at all). 30 days is
--   generous relative to `sweep_notification_outbox()`'s own 15-minute
--   stuck-claim recovery window and purely a "don't keep it forever"
--   backstop; there is no sync-correctness constraint on this window at
--   all, since the row is never part of the incremental-pull contract.
--   `public.notification_outbox_deliveries` (one row per device a purged
--   outbox row was actually sent to, `20260914104000_notification_push_correctness.sql`)
--   carries `outbox_id references notification_outbox(id) on delete
--   cascade`, so purging an outbox row here also removes its per-device
--   delivery log in the same statement -- the delivery log is exactly as
--   ephemeral as the delivery record it describes, so this is the intended,
--   not an incidental, effect.
--
--   day_entries tombstones: deleted_at < now() - 180 days. THIS is the
--   window with a real sync-correctness constraint, and it is the same
--   constraint Issue #522's tombstone-then-purge design already flagged as
--   this job's job (20260913013000_deleted_profiles_tombstone_purge.sql's
--   header: "The physical DELETE that finally reclaims the row storage is
--   out of scope for this migration and left to the retention sweep #263
--   already contemplated for this purpose"). The client pull contract is
--   `server_version > cursor`, strictly increasing and never revisited
--   (lib/data/sync/supabase_sync_engine.dart) -- once a tombstone is
--   physically removed, a client whose cursor never reached that
--   `server_version` (e.g. offline the whole time) can never learn the row
--   was deleted and can resurrect a "phantom" copy of it on its next
--   full-reconcile pull, since that pull only reflects what the server
--   currently has, not what it once had. `kSyncFullPullInterval` (the app's
--   own full-reconcile cadence, `lib/data/sync/supabase_sync_engine.dart:69`)
--   is `Duration(hours: 24)`: an ordinary client -- online at least once a
--   day -- always reconciles its cursor well inside that window. 180 days
--   is a wide, deliberate multiple of that 24h interval (180x), not merely
--   "bigger than 24h": it comfortably covers a device left offline for
--   several months (a shared/borrowed device, a guardian's long trip, an
--   app left uninstalled-but-not-yet-reinstalled) while still bounding
--   server-side growth to a fixed-size trailing window rather than
--   unbounded history. `public.sync_watermark()`
--   (20260913015000_sync_watermark.sql) is the *other* sync-correctness
--   mechanism in this schema and is deliberately NOT what this window is
--   tied to: sync_watermark bounds a *commit-ordering* race measured in
--   the width of a single transaction (a client must not advance its
--   cursor past a `server_version` some other, still-in-flight transaction
--   might still claim a lower one for) -- an entirely different, much
--   smaller timescale than "how long can a client plausibly stay offline".
--   Nothing about sync_watermark's commit-visibility guarantee is affected
--   by purging an old tombstone; the two are orthogonal safety properties
--   of the same `server_version` sequence, not alternatives for the same
--   job. If `kSyncFullPullInterval` is ever changed, this 180-day window
--   must be reviewed against the new value -- see the regression test
--   below that pins the multiple.
--
--   day_entry_history: changed_at < now() - 90 days, exactly as Issue #170
--   (the table this purges) itself proposes -- see that issue's "Bound
--   retention at 90 days via a nightly cron job -- this is the same
--   retention job as #263 ... do not build a second job." Issue #170 is
--   NOT yet landed as of this migration (no `public.day_entry_history`
--   table exists in this schema) and this migration does not create it --
--   only #170 does that. Rather than block this job on #170's landing
--   order, or duplicate a second retention job later when #170 ships, this
--   purge step is *guarded* (`to_regclass('public.day_entry_history')`) and
--   silently no-ops today; the moment #170's migration creates that table,
--   this job starts enforcing its 90-day window automatically, with no
--   further migration required. This mirrors the exact
--   pg_cron/pg_net-availability guard style this schema already uses
--   below, applied to a table's existence instead of an extension's.
--
--   feedback_tickets: status = 'resolved' and updated_at < now() - 1 year
--   AND cardinality(attachment_paths) = 0 (the last clause added by
--   Coordinator review of PR #705, blocking finding 2 -- see below). A
--   resolved ticket has no sync-pull contract at all (feedback_tickets is
--   read via `export_account_data()`/the app's own Support history query,
--   never an incremental `server_version` cursor pull), so there is no
--   analogous "a client might miss the deletion" risk here -- the 1-year
--   window is purely a retention-minimization choice, matching
--   PRIVACY.md's "Support Ticket Retention" language ("retained to support
--   ongoing conversations and app improvement") while still bounding how
--   long a resolved, closed-out ticket (and PRIVACY.md's Section 2.C
--   diagnostics payload it carries) persists. Only `resolved` tickets are
--   ever in scope -- `new`/`triage`/`replied` tickets are still an open
--   conversation regardless of `updated_at` age and are never touched here.
--   `feedback_replies` cascades from `feedback_tickets` (`on delete
--   cascade`, 20260906130000_feedback_tickets.sql), so a purged ticket's
--   reply thread goes with it in the same statement -- matching
--   `delete_account_data()`'s own "feedback_replies cascades from
--   feedback_tickets" precedent.
--
--   The `cardinality(attachment_paths) = 0` clause is NOT optional -- it
--   closes a blocking privacy bug review caught in this migration's first
--   draft. A ticket's `attachment_paths` point at objects in the private
--   `feedback-attachments` Storage bucket, and SQL cannot remove a Storage
--   object: `storage.protect_delete()` rejects any raw SQL `DELETE` against
--   `storage.objects` regardless of caller or role (the same fact
--   `feedback_attachments_rls_test.sql`'s own header documents), which is
--   exactly why `delete-account` (`supabase/functions/delete-account/index.ts`)
--   removes attachments through the Storage API before ever touching a row.
--   Hard-deleting a `feedback_tickets` row here while it still references
--   attachments would silently orphan those screenshot objects forever --
--   unreachable by any surviving row, but never actually removed from the
--   bucket, worse than simply leaving the ticket in place. A resolved,
--   year-old ticket that still carries one or more attachments is therefore
--   left untouched by this job, indefinitely, until one of two things
--   removes it: the user deletes their account (`delete-account` already
--   removes the attachment objects first, fail-closed, then the row), or a
--   future Storage-API-capable cleanup path is built specifically for this
--   narrower case -- tracked as a follow-up, not attempted here, matching
--   PRIVACY.md's own precedent of documenting a real, narrow gap rather
--   than silently working around it (its "Support Ticket Retention" bullet
--   already documents an analogous single-ticket gap for the same bucket).
--   PRIVACY.md's "Server-Side Retention Windows" bullet states this exact
--   scoping in plain language.
--
-- =============================================================================
-- Purge-function shape, matching every other SECURITY DEFINER purge/cron
-- function already in this schema
-- =============================================================================
--
-- `public.enforce_retention()`: SECURITY DEFINER, `set search_path = ''`,
-- every reference fully qualified, EXECUTE revoked from public/anon/
-- authenticated (only cron -- which runs as the function owner -- or a
-- service_role caller can invoke it; matching `sweep_notification_outbox()`/
-- `run_nightly_caregiver_alerts_job()`'s exact posture). Each table's purge
-- runs in its own `begin/exception` sub-block (the `run_nightly_caregiver_
-- alerts_job()` #15-review precedent: one table's failure must never
-- silently stop the others from running for every tenant until the next
-- deploy) and deletes in bounded batches (LIMIT 500 per statement, up to 50
-- iterations = 25,000 rows/table/run) rather than one unbounded DELETE, so
-- a nightly run cannot hold a table lock for the duration of an
-- arbitrarily large backlog scan; a backlog bigger than one run's cap is
-- idempotently finished by the next night's run. The function itself has
-- no pg_cron/pg_net dependency and is always created and independently
-- callable (by cron, by a pgTAP test running as table owner/superuser, or
-- by a future manual service_role call) regardless of whether the nightly
-- schedule below actually registers.
--
-- The cron job registration is guarded exactly like the existing two jobs
-- (20260906230000_reminder_windows_and_cron.sql's `pg_available_extensions`
-- check): a local stack started with `-x ... pg_cron ...` (or any
-- environment where the extension is unavailable) sees this whole block
-- no-op with a `raise notice` rather than failing `db reset`. Unlike that
-- migration's jobs, this one needs no `pg_net` (it makes no HTTP call), so
-- only `pg_cron`'s availability is checked and only `pg_cron` is created --
-- no new `create extension ... pg_net` is added here, per this task's
-- instructions. Unschedule-then-schedule makes re-applying this migration
-- idempotent, matching the existing two jobs' own pattern. Scheduled at
-- 03:30 UTC -- comfortably clear of `lunarlog-nightly-caregiver-alerts`'
-- 09:00 UTC run and the 15-minute `lunarlog-caregiver-alert-drain` job, so
-- a large retention batch never contends with either for the same tables.
--
-- Deliberately NOT purged by this migration, per issue #263's own scope
-- (its "Proposed change" table lists exactly these four): the sibling
-- content tables `observations`/`care_notes`/`visit_prep_items`/
-- `cycle_overrides` tombstoned alongside a full profile purge, the
-- `profiles` row's own tombstone, and the `public.deleted_profiles` log
-- row. `20260913013000_deleted_profiles_tombstone_purge.sql`'s header notes
-- these as a plausible future extension of "the retention sweep #263
-- already contemplated" -- left for a follow-up rather than folded in here
-- silently, since widening scope beyond what #263 specifies was not asked
-- for by this task.
--
-- Coverage: supabase/tests/nightly_retention_job_test.sql.

-- ---------------------------------------------------------------------------
-- 1. Supporting partial indexes -- one per purge predicate, so a nightly
--    batch scan never falls back to a sequential scan as each table grows.
-- ---------------------------------------------------------------------------

create index notification_outbox_sent_at_idx
  on public.notification_outbox (sent_at)
  where sent_at is not null;

create index day_entries_deleted_at_idx
  on public.day_entries (deleted_at)
  where deleted_at is not null;

-- Coordinator review of PR #705, blocking finding 2: the predicate now
-- matches enforce_retention()'s actual purge condition exactly (including
-- cardinality(attachment_paths) = 0 -- see that function's own comment and
-- this migration's header), so the partial index stays fully usable by the
-- purge scan rather than only partially selective.
create index feedback_tickets_resolved_updated_at_idx
  on public.feedback_tickets (updated_at)
  where status = 'resolved' and cardinality(attachment_paths) = 0;

-- ---------------------------------------------------------------------------
-- 2. public.enforce_retention()
-- ---------------------------------------------------------------------------

create or replace function public.enforce_retention() returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Per-statement row cap and per-table iteration cap (see this migration's
  -- header): bounds a single run to at most 25,000 deleted rows per table,
  -- so a large backlog is worked off over several nightly runs instead of
  -- one run holding a table lock for an unbounded scan.
  v_batch_size constant integer := 500;
  v_max_iterations constant integer := 50;
  v_iterations integer;
  v_rows bigint;
  v_notification_outbox_deleted bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_day_entry_history_deleted bigint := 0;
  v_feedback_tickets_deleted bigint := 0;
  -- Coordinator review of PR #705, blocking finding 3: a table's purge
  -- failing every night used to be invisible (a NOTICE server logs
  -- typically discard). Every exception handler below now also raises a
  -- WARNING (surfaces in cron job run history/logs) and records the
  -- failure here, keyed by table -- surfaced in the returned jsonb only
  -- when at least one table actually failed (see the `return` statement),
  -- so a healthy run's result carries no `errors` key at all.
  v_errors jsonb := '{}'::jsonb;
begin
  -- notification_outbox: sent_at older than 30 days (see header -- no
  -- sync-pull contract at all, this table is never read by any client).
  begin
    v_iterations := 0;
    loop
      delete from public.notification_outbox
       where id in (
         select id from public.notification_outbox
          where sent_at is not null
            and sent_at < now() - interval '30 days'
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_notification_outbox_deleted := v_notification_outbox_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: notification_outbox purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('notification_outbox', sqlerrm);
  end;

  -- day_entries tombstones: deleted_at older than 180 days (see header --
  -- tied to kSyncFullPullInterval, a wide multiple of the 24h full-reconcile
  -- cadence so no realistically-offline client can miss the deletion).
  begin
    v_iterations := 0;
    loop
      delete from public.day_entries
       where id in (
         select id from public.day_entries
          where deleted_at is not null
            and deleted_at < now() - interval '180 days'
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_day_entries_deleted := v_day_entries_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: day_entries tombstone purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('day_entries_tombstones', sqlerrm);
  end;

  -- day_entry_history: changed_at older than 90 days, per Issue #170's own
  -- proposal -- guarded because #170 has not landed as of this migration
  -- (no public.day_entry_history table exists yet). Silently no-ops until
  -- that table exists, then enforces automatically with no further
  -- migration (see header).
  begin
    if to_regclass('public.day_entry_history') is not null then
      v_iterations := 0;
      loop
        execute format(
          'delete from public.day_entry_history where id in ('
          || 'select id from public.day_entry_history'
          || ' where changed_at < now() - interval ''90 days'''
          || ' limit %s)',
          v_batch_size
        );
        get diagnostics v_rows = row_count;
        v_day_entry_history_deleted := v_day_entry_history_deleted + v_rows;
        v_iterations := v_iterations + 1;
        exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
      end loop;
    end if;
  exception
    when others then
      raise warning 'enforce_retention: day_entry_history purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('day_entry_history', sqlerrm);
  end;

  -- feedback_tickets: resolved, updated_at older than 1 year, AND no
  -- attachments (Coordinator review of PR #705, blocking finding 2 -- see
  -- this migration's header: SQL cannot remove the Storage objects
  -- attachment_paths point at, so a ticket that still references one is
  -- left untouched rather than orphaning that object forever).
  -- feedback_replies cascades from feedback_tickets (on delete cascade).
  begin
    v_iterations := 0;
    loop
      delete from public.feedback_tickets
       where id in (
         select id from public.feedback_tickets
          where status = 'resolved'
            and updated_at < now() - interval '1 year'
            and cardinality(attachment_paths) = 0
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_feedback_tickets_deleted := v_feedback_tickets_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: feedback_tickets purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('feedback_tickets', sqlerrm);
  end;

  -- Coordinator review of PR #705, blocking finding 3: `errors` is included
  -- only when v_errors actually holds at least one entry, so a healthy
  -- run's result carries no `errors` key at all (pinned by a pgTAP
  -- assertion) and cron job history still shows the WARNING either way.
  return jsonb_build_object(
    'notification_outbox', v_notification_outbox_deleted,
    'day_entries_tombstones', v_day_entries_deleted,
    'day_entry_history', v_day_entry_history_deleted,
    'feedback_tickets', v_feedback_tickets_deleted
  ) || case when v_errors = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('errors', v_errors) end;
end;
$$;

comment on function public.enforce_retention() is
  'Issue #263: nightly retention purge for notification_outbox (sent_at > '
  '30 days), day_entries tombstones (deleted_at > 180 days -- tied to '
  'kSyncFullPullInterval, see this migration''s header), day_entry_history '
  '(changed_at > 90 days, guarded no-op until Issue #170 lands), and '
  'resolved feedback_tickets with no attachments (updated_at > 1 year and '
  'cardinality(attachment_paths) = 0 -- Coordinator review of PR #705: a '
  'ticket still referencing a Storage object is left alone, since SQL '
  'cannot remove that object and a hard delete here would orphan it '
  'forever). Each table purges in its own exception-isolated sub-block, in '
  'bounded batches (500 rows/statement, up to 50 iterations), so one '
  'table''s failure or an oversized backlog can never block the others or '
  'hold a lock indefinitely. A failed sub-block raises a WARNING (not a '
  'NOTICE) and is recorded in the returned jsonb under an `errors` key '
  '(table -> sqlerrm), present only when at least one table actually '
  'failed, so a failing purge is visible in cron job history instead of '
  'silent. SECURITY DEFINER; callable only by cron or service_role.';

revoke all on function public.enforce_retention() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Nightly pg_cron job (guarded exactly like the existing two jobs; see
--    this migration's header for why only pg_cron, not pg_net, is checked
--    and created here).
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'nightly_retention_job: pg_cron not available, skipping cron schedule (see docs/ops/supabase-go-live.md)';
    return;
  end if;

  create extension if not exists pg_cron;

  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'lunarlog-nightly-retention';

  perform cron.schedule(
    'lunarlog-nightly-retention',
    '30 3 * * *', -- 03:30 UTC nightly, clear of the 09:00 UTC alerts job
    $cron$select public.enforce_retention();$cron$
  );
end;
$$;
