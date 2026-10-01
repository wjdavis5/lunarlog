-- ===========================================================================
-- 20260921140000_day_entry_note_select_revoke.sql
-- Issue #1277 (P1, privacy(sharing)): authenticated's table-wide SELECT grant
-- on public.day_entries made #849's private-note masking bypassable -- the
-- note text was readable raw with an ordinary PostgREST select, skipping
-- mask_day_entry_note() entirely.
--
-- Background:
--   20260903014208_initial_sync_schema.sql granted `select, insert` on
--   day_entries to authenticated. 20260915160000_sync_push_sole_write_path.sql
--   (#201) later revoked insert/update to make sync_push the sole write path,
--   but SELECT stayed. 20260921130000_day_entry_note_private.sql (#849) then
--   built the per-note privacy control -- a subject's private day note -- on
--   the recorded assumption that sync_pull is "the only way any client reads
--   day_entries" and put the masking there (sync_pull, sync_push's declined
--   row handback, export_account_data), all SECURITY DEFINER. The grant made
--   that assumption false: any accepted guardian of the profile, any role,
--   could `select note from day_entries` with their own session (browser
--   devtools on the web client, or the REST API directly) and read the
--   private text raw. RLS cannot close this: the SELECT policies
--   (day_entries_select_own / day_entries_select_guardians) authorize every
--   accepted guardian for the whole row -- RLS filters rows, it cannot
--   transform a column, which is exactly why #849 masked in the RPCs.
--
-- The fix (the issue's column-grant option): REPLACE the table-wide SELECT
-- grant with a column-level grant covering every column EXCEPT `note`. A
-- column-level REVOKE alone cannot do this -- Postgres has no subtraction
-- from a table-wide ACL entry (verified against the local stack while
-- writing this migration: `revoke select (note)` left the table-wide grant
-- intact) -- so the table-wide grant is revoked and the per-column grant
-- re-issued in its place. After this migration:
--   - a direct `select note`, any projection naming note, and any whole-row
--     read (`select *`, to_jsonb(row)) fail 42501 at the privilege layer --
--     Postgres requires SELECT on every projected column -- so the RPCs'
--     masking becomes the only way to reach the note text, the read-path
--     mirror of #201 making sync_push the only way to write;
--   - direct reads of the non-note columns keep working for accepted
--     guardians, which is the product's own re-scoped posture (#849:
--     guardians see everything the subject logs EXCEPT the private note
--     text). The full-table revoke suggested by the issue was rejected
--     deliberately: nothing client-side needs it, and it would have
--     invalidated the pgTAP suite's authenticated fixture reads of non-note
--     columns wholesale (~250 assertions across ~25 files) to protect
--     columns that are not secret.
--
-- The column list is DERIVED from information_schema at migration time, not
-- hand-restated (#181's reasoning: a hand-kept list drifts the next time a
-- column is added). supabase/tests/day_entry_note_private_test.sql
-- re-derives it independently at test time and compares, so a future
-- day_entries column whose author forgets this grant fails the suite rather
-- than silently widening or narrowing the direct read surface. A new column
-- defaults to NOT directly readable (it must be added to this grant
-- deliberately) -- the safe direction, since the only sanctioned read path
-- (sync_pull, SECURITY DEFINER) is unaffected by grants.
--
-- Why nothing client-visible changes:
--   - The Flutter client never reads day_entries directly: every read goes
--     through sync_pull (lib/data/sync/), whose day_entries page is masked
--     by 20260921130000. The web client is the same (webapp/src/lib/day/
--     day-data.ts: "sync_pull ... the only read path that applies" masking;
--     its only direct .from() reads are profile_guardians /
--     guardian_invitations / ownership_transfers / guardian_notes /
--     care_notes).
--   - sync_pull / sync_push / export_account_data are SECURITY DEFINER
--     (20260921130000:220/2844/3022): they read as their owner, so a grant
--     on `authenticated` cannot touch them. day_entries is FORCE RLS, so
--     their reads keep passing through the (unchanged) SELECT policies.
--   - Realtime never carried the row anyway: day_entries is not a member of
--     supabase_realtime (20260905100000; reconcile_realtime_publication()
--     re-enforces that on every deploy) -- only sync_signals, which carries
--     no health content, is published. And as that migration's header
--     records, Realtime's real per-column filter is
--     has_column_privilege(<role>, <table>, <column>, 'SELECT') -- so this
--     revoke doubles as defence in depth: even a future misconfiguration
--     that published day_entries could no longer deliver note over the
--     websocket.
--   - service_role is untouched (it holds its own default grants): the Edge
--     Functions (delete-account's cleanup) and cron jobs are unaffected.
--   - day_entry_history keeps its SELECT grant: it carries field NAMES only,
--     never note text (20260918000000).
--
-- The SELECT policies are deliberately KEPT: FORCE RLS subjects the
-- SECURITY DEFINER RPCs' internal reads to RLS, and those policies are what
-- authorize them. Policies authorize rows; grants authorize columns. Only
-- the note column's grant moves.
-- ===========================================================================

do $$
declare
  v_grant_list text;
begin
  -- 1. Revoke the table-wide SELECT, then re-grant it column-scoped minus
  --    `note` (the issue's fallback shape, which the plain column REVOKE
  --    cannot express -- see the header).
  execute 'revoke select on table public.day_entries from authenticated';

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into v_grant_list
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'day_entries'
     and column_name <> 'note';

  if v_grant_list is null then
    raise exception 'issue #1277: derived an empty non-note column list for day_entries'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  execute format('grant select (%s) on table public.day_entries to authenticated', v_grant_list);

  -- 2. Migration-time assertion: for every column of day_entries, held
  --    SELECT must be exactly (column <> 'note'). Any drift -- a typo above,
  --    a column added mid-migration without re-deriving, a stray extra
  --    revoke -- fails the migration instead of shipping a wrong grant.
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'day_entries'
       and has_column_privilege('authenticated', 'public.day_entries', column_name, 'SELECT')
           is distinct from (column_name <> 'note')
  ) then
    raise exception 'issue #1277: authenticated''s SELECT on day_entries is not exactly every column except note'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 3. The role-level posture around the column grant: anon and PUBLIC hold
  --    nothing (as since the initial schema), and authenticated now holds no
  --    table-WIDE SELECT either (only the per-column grant).
  if has_table_privilege('anon', 'public.day_entries', 'SELECT')
     or has_table_privilege('public', 'public.day_entries', 'SELECT') then
    raise exception 'issue #1277: anon/public must hold no SELECT on day_entries'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if has_table_privilege('authenticated', 'public.day_entries', 'SELECT') then
    raise exception 'issue #1277: authenticated still holds a table-wide SELECT on day_entries'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
end;
$$;

comment on column public.day_entries.note is
  'The subject''s free-text day note (2000 chars). Privacy (#849): when the '
  'row''s note_private is true, the text is served in full only to the '
  'profile''s subject (via sync_pull/sync_push handbacks and their own '
  'export) -- every other accepted guardian membership receives note = NULL '
  'from those RPCs. Issue #1277: this column is also excluded from '
  'authenticated''s direct SELECT grant (a per-column grant replaces the '
  'table-wide one), so a raw PostgREST select can never read the text '
  'around the RPC masking; a direct read naming this column fails 42501.';
