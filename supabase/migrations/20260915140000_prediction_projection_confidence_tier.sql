-- Migration: 20260915140000_prediction_projection_confidence_tier.sql
--
-- Issue #593 (P2, related: #529): #580 added `confidenceTier` to the
-- client's `PredictionProjection` model (`lib/domain/sharing/
-- prediction_projection.dart`) and the sharer's own calendar already
-- renders it -- but `prediction_projections_payload_keys_check` and
-- `enforce_prediction_projection_payload()`
-- (`supabase/migrations/20260909200000_prediction_connections.sql`)
-- allowlist only the five original derived-phase keys, so
-- `SupabasePredictionConnectionService.publishProjection` has had to strip
-- `confidence_tier` off every outgoing payload since #529 -- a recipient
-- never sees the sharer's tier at all. This migration widens the
-- allowlist so the key can round-trip end to end; the client-side strip
-- comes out in the same PR.
--
-- Fix, mirroring `is_valid_tracking_preferences`/`profiles_mode_check`'s
-- shape: `confidence_tier` joins the structural CHECK's key allowlist as
-- an OPTIONAL, NULLABLE key (a document may omit it entirely, exactly
-- like every snapshot published before this field existed -- no backfill,
-- no default), and the payload trigger enum-checks its value against the
-- client's own [CycleConfidence] names (`lib/domain/prediction/
-- prediction.dart`): 'high', 'learning', 'irregular', 'provisional'. An
-- explicit JSON null is also accepted (the same "nullable" contract), so
-- a future client that always emits the key rather than omitting it when
-- absent is not forced to invent a tier.
--
-- Both functions touched here (`enforce_prediction_projection_payload`,
-- the CHECK) are re-created/re-added from their current bodies on main --
-- neither has been redefined since 20260909200000_prediction_connections.sql
-- (confirmed by grep across every migration in between, #671's
-- 20260915030000 retraction RPCs included), so the trigger body below is
-- that file's version with only the `confidence_tier` branch spliced in,
-- and the CHECK is dropped and re-added with the widened array literal (a
-- CHECK constraint cannot be altered in place).
--
-- Older rows are unaffected either way: a snapshot published before this
-- migration simply has no `confidence_tier` key, and the CHECK's
-- allowlist subtraction (`projection - array[...]) = '{}'`) does not
-- require every allowed key to be present, only that no OTHER key exists
-- -- so a pre-#593 row keeps validating (and keeps reading back with the
-- key absent, which the client's own `PredictionProjection.fromJson`
-- already treats as "no tier" per #529's doc comment) with no migration
-- of existing data needed.
--
-- Coverage: supabase/tests/prediction_connection_test.sql section 5 (the
-- projection boundary) gains a rejection case (an out-of-enum tier) and
-- an acceptance/round-trip case, alongside the existing re-publish of the
-- original 5-key payload proving an older-shaped document still
-- validates and reads back with the key simply absent.

begin;

-- ---------------------------------------------------------------------------
-- 1. Structural key allowlist: drop and re-add with `confidence_tier`
--    joining the set (a CHECK constraint has no ALTER-in-place form).
-- ---------------------------------------------------------------------------

alter table public.prediction_projections
  drop constraint prediction_projections_payload_keys_check;

alter table public.prediction_projections
  add constraint prediction_projections_payload_keys_check
  check (
    (projection - array[
      'generated_at', 'period_days', 'fertile_days',
      'ovulation_days', 'pms_days', 'confidence_tier'
    ]) = '{}'::jsonb
  );

comment on table public.prediction_projections is
  'Client-published snapshot of derived cycle phases (Issue #151): period '
  'days, fertile days, ovulation days, PMS window -- dates only, never '
  'note/tags/flow, never a raw day_entries/observations row -- plus an '
  'OPTIONAL confidence_tier (Issue #593/#529: the sharer''s own '
  '[CycleConfidence] tier name, nullable, absent on any snapshot '
  'published before this field existed). One row per profile, and only '
  'while an active prediction connection exists '
  '(prediction_connections_projection_gc keeps that invariant). The '
  'prediction algorithm itself is never recomputed server-side -- the '
  'sharer''s device publishes what lib/domain/prediction already computes. '
  'NO policies and no grants: clients reach this through '
  'get_prediction_projection() only, which serves the allowlisted payload '
  'to the active recipient and to the profile''s own guardians (who '
  'already hold full raw access and gain nothing new here).';

-- ---------------------------------------------------------------------------
-- 2. Payload validation trigger: re-created verbatim from its current body
--    (20260909200000_prediction_connections.sql, never redefined since)
--    with one new branch -- `confidence_tier` is checked and skipped
--    before the "known derived-phase field" rejection every other key
--    still goes through unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_prediction_projection_payload()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_array jsonb;
  v_item jsonb;
begin
  -- generated_at: required, an ISO yyyy-mm-dd civil date string.
  if jsonb_typeof(new.projection -> 'generated_at')
       is distinct from 'string'
     or (new.projection ->> 'generated_at')
       !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'projection.generated_at must be an ISO yyyy-mm-dd date string'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Every other key must be an array of at most 100 ISO date strings,
  -- except confidence_tier (Issue #593), an optional, nullable enum value.
  for v_key in
    select k from jsonb_object_keys(new.projection) as t(k)
  loop
    if v_key = 'generated_at' then
      continue;
    end if;
    -- Issue #593: nullable text, enum-checked against the client's own
    -- CycleConfidence names (lib/domain/prediction/prediction.dart) --
    -- an explicit JSON null is accepted too (the same "nullable" contract
    -- as an absent key), so this never forces a tier the sharer's device
    -- did not actually compute.
    if v_key = 'confidence_tier' then
      if jsonb_typeof(new.projection -> 'confidence_tier') not in ('string', 'null')
         or (jsonb_typeof(new.projection -> 'confidence_tier') = 'string'
             and (new.projection ->> 'confidence_tier')
               not in ('high', 'learning', 'irregular', 'provisional')) then
        raise exception 'projection.confidence_tier must be a known confidence tier or null'
          using errcode = 'invalid_parameter_value';
      end if;
      continue;
    end if;
    if v_key not in ('period_days', 'fertile_days', 'ovulation_days', 'pms_days') then
      raise exception 'projection key % is not a derived-phase field', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    v_array := new.projection -> v_key;
    if jsonb_typeof(v_array) is distinct from 'array' then
      raise exception 'projection.% must be an array of date strings', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    if jsonb_array_length(v_array) > 100 then
      raise exception 'projection.% may hold at most 100 dates', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    for v_item in select * from jsonb_array_elements(v_array)
    loop
      if jsonb_typeof(v_item) is distinct from 'string'
         or v_item #>> '{}' !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'projection.% must hold only ISO yyyy-mm-dd date strings', v_key
          using errcode = 'invalid_parameter_value';
      end if;
    end loop;
  end loop;

  return new;
end;
$$;

comment on function public.enforce_prediction_projection_payload() is
  'BEFORE INSERT/UPDATE guard on prediction_projections: the payload may '
  'carry only derived-phase keys (generated_at plus period_days / '
  'fertile_days / ovulation_days / pms_days), each an array of at most '
  '100 ISO date strings, plus an optional, nullable confidence_tier '
  '(Issue #593/#529) enum-checked against the client''s CycleConfidence '
  'names. No free-text key can ever be stored, so the recipient-facing '
  'RPC cannot leak note/tags/flow even by server bug -- the data is not '
  'there.';

-- The trigger and its execute-revoke already exist from
-- 20260909200000_prediction_connections.sql and are untouched by this
-- migration (create or replace on the function body above is enough --
-- no re-create/re-grant needed for either).

commit;
