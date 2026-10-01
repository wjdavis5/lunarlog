-- ===========================================================================
-- 20260921150000_sync_pull_day_entries_masked_page.sql
-- Issue #1277, part 2: the client-side half of closing the direct-read
-- bypass. 20260921140000 made day_entries.note readable only through the
-- masking RPCs -- which surfaced (in CI's live-stack round-trip test,
-- issue #102's harness) that the Flutter transport's own pull FALLBACK read
-- day_entries with a raw whole-row PostgREST select: SupabaseSyncTransport's
-- per-table select is the baseline path whenever its sync_pull cache cannot
-- answer (priming failed, or the table had more pending rows than the
-- sync_pull page cap -- i.e. every multi-page initial sync), and a whole-row
-- select requires SELECT on every column. Under the new grant that path
-- fails 42501 for everyone, the subject included; on a pre-migration server
-- it was itself the leak (a non-subject guardian's device received the
-- private note text over the wire on every cache-miss page). The issue's
-- recorded premise -- "sync_pull, the only way any client reads
-- day_entries" -- did not hold for this fallback.
--
-- The fix mirrors the schema's established shape (issue #521's
-- sync_watermark(): a small single-purpose companion RPC with a graceful
-- client fallback): sync_pull's day_entries branch, as a callable page.
--
--   public.sync_pull_day_entries(p_after_version bigint default 0,
--                                p_limit integer default 500)
--
--   * SECURITY DEFINER, same tenant predicate as sync_pull (#525: the
--     caller's accepted guardianships, computed once), same #849 masking
--     via mask_day_entry_note -- a non-subject accepted guardian receives
--     note = NULL, the subject the text in full.
--   * p_limit is capped at sync_pull's own c_page_size (500): this RPC
--     serves exactly the page the transport could not answer from its
--     sync_pull cache, never a bigger one.
--   * EXECUTE: revoked from public/anon, granted to authenticated -- the
--     sync_pull(jsonb) grant posture verbatim.
--
-- The transport (lib/data/sync/supabase_sync_transport.dart) routes its
-- day_entries fallback here, and falls back further to the legacy raw
-- select ONLY on PostgREST "function not found" (PGRST202) -- a server
-- predating this release still holds the old table-wide grant and has no
-- masked page to offer, so the legacy read is the correct upgrade-skew
-- behavior there (and is unmasked exactly to the degree that server
-- already was). Every other failure maps through the ordinary transport
-- error kinds.
--
-- pgTAP coverage: supabase/tests/day_entry_note_private_test.sql, section 9.
-- ===========================================================================

create or replace function public.sync_pull_day_entries(
  p_after_version bigint default 0,
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- sync_pull's own per-table page cap (20260913014000): this RPC must
  -- never serve a bigger page than the cycle prime it complements.
  c_page_size constant integer := 500;
  v_uid uuid := (select auth.uid());
  v_profile_ids text[];
begin
  if v_uid is null then
    raise exception 'sync_pull_day_entries requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > c_page_size then
    raise exception 'p_limit must be between 1 and %', c_page_size
      using errcode = 'invalid_parameter_value';
  end if;

  -- The tenant predicate, computed once -- verbatim sync_pull's (#525):
  -- every page below reuses this same array rather than invoking a
  -- per-row guardian-membership check.
  select coalesce(array_agg(profile_id), '{}') into v_profile_ids
    from public.profile_guardians
   where user_id = v_uid
     and status = 'accepted';

  -- sync_pull's day_entries branch verbatim, including Issue #849's
  -- masking: a private note is masked to NULL for every non-subject
  -- accepted guardian; the subject receives it in full.
  return coalesce(
    jsonb_agg(public.mask_day_entry_note(to_jsonb(t), v_uid)),
    '[]'::jsonb
  ) from (
    select * from public.day_entries
     where profile_id = any(v_profile_ids)
       and server_version > p_after_version
     order by server_version
     limit p_limit
  ) t;
end;
$$;

comment on function public.sync_pull_day_entries(bigint, integer) is
  'Issue #1277: sync_pull''s day_entries branch as a callable single-table '
  'page (<= 500 rows past p_after_version, ordered by server_version), '
  'masked exactly like sync_pull (#849: note = NULL for every non-subject '
  'accepted guardian, the full text for the subject). Exists so the sync '
  'transport''s per-table pull fallback can serve day_entries without a raw '
  'whole-row select -- 20260921140000 removed authenticated''s SELECT on '
  'the note column, and the fallback must never read around the masking '
  'the way the raw select did. SECURITY DEFINER; the same tenant predicate '
  'and grant posture as sync_pull(jsonb).';

revoke all on function public.sync_pull_day_entries(bigint, integer) from public, anon;
grant execute on function public.sync_pull_day_entries(bigint, integer) to authenticated;
