-- Migration: 20260907010000_tags_element_length_check.sql
-- Fixes Issue #94: day-entry tag elements had no length bound - a single
-- element could be arbitrarily large, so 32 multi-megabyte tags could be
-- pushed through sync_push, persisted, and replicated to every co-guardian.
-- Extends 20260903170000_tags_string_array_check.sql (Issue #40), which
-- bounded only element type (string-only) and count (<= 32), with a
-- per-element char_length <= 64 bound - the same short-string bound as
-- day_entries_tz_length_check, and ~3.7x headroom over the longest curated
-- taxonomy code (`breast_tenderness`, 17 characters).
--
-- Order matters (the #40 migration is the template):
--   1. replace the function, so the pre-clean selects rows by the NEW rule;
--   2. pre-clean rows that violate it (Postgres does not re-validate an
--      existing CHECK constraint when a function it calls is redefined, and
--      the re-add below must not fail);
--   3. drop and re-add day_entries_tags_check, forcing a full re-scan of
--      stored rows under the tightened predicate.
--
-- The pre-clean drops offending elements rather than truncating them: an
-- over-length tag is payload, not a tag, and truncation would manufacture a
-- code matching nothing in the taxonomy. No offending rows are known to
-- exist (the CHECK makes it impossible to create one through any granted
-- path once this migration has run), so the branch is expected to be a
-- no-op in practice; it exists so the migration is unconditionally safe to
-- apply.

create or replace function public.is_valid_tags_array(p_tags jsonb)
returns boolean
language sql
immutable
parallel safe
as $$
  select case
    when jsonb_typeof(p_tags) <> 'array' then false
    else jsonb_array_length(p_tags) <= 32
      and not exists (
        select 1
          from jsonb_array_elements(p_tags) elem
         where jsonb_typeof(elem) <> 'string'
            or char_length(elem #>> '{}') > 64
      )
  end;
$$;

comment on function public.is_valid_tags_array(jsonb) is
  'Validates that a JSONB value is an array of at most 32 strings, each at most 64 characters (Issues #40, #94).';

-- Preserve every element that satisfies the tightened rule before replacing
-- the constraint so an upgrade cannot fail or discard the usable portion of
-- an existing row.
--
-- PR #145 review (P1): this UPDATE changes `tags`, which satisfies
-- day_entries_after_update_enqueue_alerts' WHEN clause, so left unbracketed
-- an upgrade against a database with historical offending rows would fan
-- real caregiver alerts out of notification_outbox for entries nobody just
-- logged - against that trigger's own documented intent (20260906220000, #7
-- review). Disable that one trigger for exactly this statement; migration
-- files run in a single transaction, so the trigger state and any partial
-- effect of the UPDATE roll back together on failure, and the re-enable
-- below restores the original state on success. The INSERT trigger needs no
-- bracket: this statement is UPDATE-only.
alter table public.day_entries
  disable trigger day_entries_after_update_enqueue_alerts;

update public.day_entries d
   set tags = (
     select coalesce(jsonb_agg(e.value order by e.ordinality), '[]'::jsonb)
       from jsonb_array_elements(d.tags) with ordinality as e(value, ordinality)
      where jsonb_typeof(e.value) = 'string'
        and char_length(e.value #>> '{}') <= 64
   )
 where not public.is_valid_tags_array(d.tags);

alter table public.day_entries
  enable trigger day_entries_after_update_enqueue_alerts;

alter table public.day_entries
  drop constraint if exists day_entries_tags_check,
  add constraint day_entries_tags_check
    check (public.is_valid_tags_array(tags));
