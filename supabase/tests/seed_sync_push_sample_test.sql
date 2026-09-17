-- GENERATED FILE -- DO NOT EDIT.
--
-- Issue #710's seeder fixture: a small, deterministic sync_push payload
-- (single adult profile, ~2 months) produced by the same generator the
-- operator tool uses (tool/seed_test_accounts/payload_generator.dart),
-- replayed against the real public.sync_push so CI (db-tests) proves the
-- seeder's payload shapes survive the live function with zero rejections.
--
-- Regenerate with:
--   dart run tool/seed_test_accounts/main.dart --emit-pgtap \
--     supabase/tests/seed_sync_push_sample_test.sql
--
-- updated_at values are relative to now() so this file never ages past
-- sync_push's 180-day tombstone-resurrection window.
begin;
select plan(20);

select tests.create_supabase_user('seed_sample_user');
select tests.authenticate_as('seed_sample_user');

create temp table seed_result_0 (v jsonb);
insert into seed_result_0 select public.sync_push(
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'display_name', 'Maya', 'is_minor', false, 'sort_order', 0, 'created_at', '2026-09-14T12:00:00.000Z', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'birth_year', 1988, 'relationship', 'self', 'mode', 'standard', 'last_period_start', '2026-08-29', 'typical_cycle_length_days', 28, 'typical_period_length_days', 5, 'bbt_unit', 'celsius', 'weight_unit', 'kg')),
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_0), 0,
  'sync_push call 0 (p_profiles, 1 rows): rejected is empty');

create temp table seed_result_1 (v jsonb);
insert into seed_result_1 select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y2', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-15', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y4', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-16', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y6', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-17', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y8', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-18', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-19', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YG', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-20', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YJ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-21', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YN', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-22', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YS', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-23', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YV', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-24', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-25', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z0', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-26', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z2', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-27', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z5', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-28', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z7', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-29', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'tags', jsonb_build_array('sensitive', 'mood_swings'), 'note', 'Mild cramps in the morning, gone by noon.', 'pms', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z9', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-30', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'tags', jsonb_build_array('sensitive', 'irritable'), 'pms', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZB', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-31', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'tags', jsonb_build_array('sad', 'irritable'), 'pms', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-01', 'tz', 'America/New_York', 'flow', 'light', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZH', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-02', 'tz', 'America/New_York', 'flow', 'heavy', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZM', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-03', 'tz', 'America/New_York', 'flow', 'medium', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZQ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-04', 'tz', 'America/New_York', 'flow', 'light', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZT', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-05', 'tz', 'America/New_York', 'flow', 'light', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-06', 'tz', 'America/New_York', 'flow', 'light', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM300', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-07', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM303', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-08', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM308', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-09', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-10', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-11', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-12', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30M', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-13', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-14', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-15', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30X', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-16', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM310', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-17', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM314', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-18', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM316', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-19', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM318', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-20', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31B', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-21', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31D', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-22', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31G', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-23', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-24', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31N', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-25', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-26', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31V', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-27', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'tags', jsonb_build_array('sensitive', 'sad', 'irritable'), 'pms', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31Z', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-28', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'tags', jsonb_build_array('sad', 'irritable', 'anxious'), 'pms', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM321', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-29', 'tz', 'America/New_York', 'flow', 'medium', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM324', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-30', 'tz', 'America/New_York', 'flow', 'super_heavy', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM328', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-31', 'tz', 'America/New_York', 'flow', 'medium', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-01', 'tz', 'America/New_York', 'flow', 'light', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32D', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-02', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'note', 'Traveled today; routine was off schedule.', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
||jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32F', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-03', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32H', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-04', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32K', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-05', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-06', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32R', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-07', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32W', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-08', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32Y', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-09', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM330', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-10', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM334', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-11', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM337', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-12', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33C', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-13', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-14', 'tz', 'America/New_York', 'flow', 'not_bleeding', 'pms', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_1), 0,
  'sync_push call 1 (p_day_entries, 62 rows): rejected is empty');

create temp table seed_result_2 (v jsonb);
insert into seed_result_2 select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y3', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y2', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-15', 'observed_at', '2026-07-15T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.33'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y5', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y4', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-16', 'observed_at', '2026-07-16T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.39'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y7', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y6', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-17', 'observed_at', '2026-07-17T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.48'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y9', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y8', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-18', 'observed_at', '2026-07-18T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.33'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YA', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y8', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-18', 'observed_at', '2026-07-18T12:00:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.5'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YB', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y8', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-18', 'tz', 'America/New_York', 'category', 'mind', 'code', 'distracted', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YC', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Y8', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-18', 'tz', 'America/New_York', 'category', 'digestion', 'code', 'bloating', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YE', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-19', 'observed_at', '2026-07-19T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.5'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YF', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-19', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YH', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YG', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-20', 'observed_at', '2026-07-20T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.56'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YK', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YJ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-21', 'observed_at', '2026-07-21T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.37'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YM', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YJ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-21', 'tz', 'America/New_York', 'category', 'digestion', 'code', 'bloating', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YP', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YN', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-22', 'observed_at', '2026-07-22T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.45'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YQ', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YN', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-22', 'tz', 'America/New_York', 'category', 'mind', 'code', 'stressed', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YR', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YN', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-22', 'tz', 'America/New_York', 'category', 'energy', 'code', 'fatigue', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YT', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YS', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-23', 'observed_at', '2026-07-23T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.48'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YW', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YV', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-24', 'observed_at', '2026-07-24T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.49'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YY', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-25', 'observed_at', '2026-07-25T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.44'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2YZ', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2YX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-25', 'observed_at', '2026-07-25T12:30:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.5'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z1', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z0', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-26', 'observed_at', '2026-07-26T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.52'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z3', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z2', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-27', 'observed_at', '2026-07-27T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.51'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z4', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z2', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-27', 'tz', 'America/New_York', 'category', 'cravings', 'code', 'chocolate', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z6', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z5', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-28', 'observed_at', '2026-07-28T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.34'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Z8', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z7', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-29', 'observed_at', '2026-07-29T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.54'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZA', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2Z9', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-30', 'observed_at', '2026-07-30T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.38'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZC', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZB', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-07-31', 'observed_at', '2026-07-31T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.36'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZE', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-01', 'observed_at', '2026-08-01T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.35'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZF', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-01', 'observed_at', '2026-08-01T12:00:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.4'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZG', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZD', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-01', 'tz', 'America/New_York', 'category', 'pain', 'code', 'back_pain', 'intensity', 3, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZJ', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZH', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-02', 'observed_at', '2026-08-02T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.4'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZK', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZH', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-02', 'tz', 'America/New_York', 'category', 'pain', 'code', 'back_pain', 'intensity', 1, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZN', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZM', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-03', 'observed_at', '2026-08-03T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.54'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZP', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZM', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-03', 'tz', 'America/New_York', 'category', 'pain', 'code', 'cramps', 'intensity', 3, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZR', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZQ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-04', 'observed_at', '2026-08-04T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.51'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZS', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZQ', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-04', 'tz', 'America/New_York', 'category', 'pain', 'code', 'headache', 'intensity', 3, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZV', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZT', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-05', 'observed_at', '2026-08-05T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.41'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZW', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZT', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-05', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZY', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-06', 'observed_at', '2026-08-06T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.44'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2ZZ', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM2ZX', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-06', 'tz', 'America/New_York', 'category', 'pain', 'code', 'cramps', 'intensity', 2, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM301', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM300', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-07', 'observed_at', '2026-08-07T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.41'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM302', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM300', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-07', 'tz', 'America/New_York', 'category', 'spotting', 'code', 'spotting', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM304', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM303', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-08', 'observed_at', '2026-08-08T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.55'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM305', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM303', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-08', 'observed_at', '2026-08-08T12:45:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.3'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM306', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM303', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-08', 'tz', 'America/New_York', 'category', 'energy', 'code', 'fatigue', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM307', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM303', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-08', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM309', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM308', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-09', 'observed_at', '2026-08-09T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.43'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30B', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-10', 'observed_at', '2026-08-10T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.41'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30C', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-10', 'tz', 'America/New_York', 'category', 'feelings', 'code', 'sad', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30D', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-10', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30F', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-11', 'observed_at', '2026-08-11T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.62'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
||jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30G', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-11', 'tz', 'America/New_York', 'category', 'energy', 'code', 'fatigue', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30H', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-11', 'tz', 'America/New_York', 'category', 'feelings', 'code', 'sad', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30K', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-12', 'observed_at', '2026-08-12T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.42'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30N', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30M', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-13', 'observed_at', '2026-08-13T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.59'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30Q', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-14', 'observed_at', '2026-08-14T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.49'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30R', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-14', 'tz', 'America/New_York', 'category', 'pain', 'code', 'breast_tenderness', 'intensity', 3, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30T', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-15', 'observed_at', '2026-08-15T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.85'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30V', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-15', 'observed_at', '2026-08-15T12:15:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.2'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30W', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-15', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30Y', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30X', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-16', 'observed_at', '2026-08-16T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.83'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM30Z', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM30X', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-16', 'tz', 'America/New_York', 'category', 'pain', 'code', 'headache', 'intensity', 2, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM311', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM310', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-17', 'observed_at', '2026-08-17T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.84'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM312', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM310', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-17', 'tz', 'America/New_York', 'category', 'energy', 'code', 'fatigue', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM313', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM310', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-17', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM315', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM314', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-18', 'observed_at', '2026-08-18T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.9'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM317', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM316', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-19', 'observed_at', '2026-08-19T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.99'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM319', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM318', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-20', 'observed_at', '2026-08-20T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.82'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31A', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM318', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-20', 'tz', 'America/New_York', 'category', 'cravings', 'code', 'sweet', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31C', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31B', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-21', 'observed_at', '2026-08-21T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.86'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31E', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31D', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-22', 'observed_at', '2026-08-22T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.89'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31F', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31D', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-22', 'observed_at', '2026-08-22T12:45:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.1'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31H', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31G', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-23', 'observed_at', '2026-08-23T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.79'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31K', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-24', 'observed_at', '2026-08-24T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.78'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31M', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-24', 'tz', 'America/New_York', 'category', 'feelings', 'code', 'anxious', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31P', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31N', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-25', 'observed_at', '2026-08-25T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('37.06'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31Q', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31N', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-25', 'tz', 'America/New_York', 'category', 'cravings', 'code', 'sweet', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31R', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31N', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-25', 'tz', 'America/New_York', 'category', 'energy', 'code', 'exhausted', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31T', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-26', 'observed_at', '2026-08-26T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.91'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31W', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31V', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-27', 'observed_at', '2026-08-27T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.87'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31X', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31V', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-27', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM31Y', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31V', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-27', 'tz', 'America/New_York', 'category', 'cravings', 'code', 'cravings', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM320', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM31Z', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-28', 'observed_at', '2026-08-28T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.74'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM322', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM321', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-29', 'observed_at', '2026-08-29T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.57'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM323', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM321', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-29', 'observed_at', '2026-08-29T12:45:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('63.1'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM325', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM324', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-30', 'observed_at', '2026-08-30T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.42'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM326', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM324', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-30', 'tz', 'America/New_York', 'category', 'pain', 'code', 'cramps', 'intensity', 1, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM327', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM324', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-30', 'tz', 'America/New_York', 'category', 'energy', 'code', 'exhausted', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM329', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM328', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-08-31', 'observed_at', '2026-08-31T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.52'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32B', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-01', 'observed_at', '2026-09-01T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.37'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32C', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32A', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-01', 'tz', 'America/New_York', 'category', 'pain', 'code', 'cramps', 'intensity', 1, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32E', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32D', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-02', 'observed_at', '2026-09-02T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.28'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32G', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32F', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-03', 'observed_at', '2026-09-03T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.51'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32J', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32H', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-04', 'observed_at', '2026-09-04T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.35'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32M', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32K', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-05', 'observed_at', '2026-09-05T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.42'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32N', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32K', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-05', 'observed_at', '2026-09-05T12:30:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('62.9'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32Q', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-06', 'observed_at', '2026-09-06T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.44'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32S', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32R', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-07', 'observed_at', '2026-09-07T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.45'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32T', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32R', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-07', 'tz', 'America/New_York', 'category', 'pain', 'code', 'breast_tenderness', 'intensity', 3, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32V', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32R', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-07', 'tz', 'America/New_York', 'category', 'sleep', 'code', 'sleep_trouble', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32X', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32W', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-08', 'observed_at', '2026-09-08T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.54'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))
||jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM32Z', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM32Y', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-09', 'observed_at', '2026-09-09T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.58'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM331', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM330', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-10', 'observed_at', '2026-09-10T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.35'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM332', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM330', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-10', 'tz', 'America/New_York', 'category', 'mind', 'code', 'calm', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM333', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM330', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-10', 'tz', 'America/New_York', 'category', 'energy', 'code', 'fatigue', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM335', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM334', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-11', 'observed_at', '2026-09-11T11:15:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.3'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM336', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM334', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-11', 'tz', 'America/New_York', 'category', 'cravings', 'code', 'sweet', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM338', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM337', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-12', 'observed_at', '2026-09-12T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.89'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM339', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM337', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-12', 'observed_at', '2026-09-12T12:45:00.000Z', 'tz', 'America/New_York', 'category', 'weight', 'value_num', to_jsonb('62.7'::numeric), 'unit', 'kg', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33A', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM337', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-12', 'tz', 'America/New_York', 'category', 'mind', 'code', 'stressed', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33B', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM337', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-12', 'tz', 'America/New_York', 'category', 'energy', 'code', 'exhausted', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33D', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM33C', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-13', 'observed_at', '2026-09-13T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('37.04'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33F', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM33E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-14', 'observed_at', '2026-09-14T11:00:00.000Z', 'tz', 'America/New_York', 'category', 'bbt', 'value_num', to_jsonb('36.6'::numeric), 'unit', 'celsius', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33G', 'day_entry_id', '01M2FWKNG0ZMH2ANCH7R2CM33E', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'local_date', '2026-09-14', 'tz', 'America/New_York', 'category', 'energy', 'code', 'exhausted', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_2), 0,
  'sync_push call 2 (p_observations, 113 rows): rejected is empty');

create temp table seed_result_3 (v jsonb);
insert into seed_result_3 select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'mode', 'tracking', 'mode_started_on', '2026-07-15', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_3), 0,
  'sync_push call 3 (p_profile_modes, 1 rows): rejected is empty');

create temp table seed_result_4 (v jsonb);
insert into seed_result_4 select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y0', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'cycle_start_date', '2026-08-01', 'excluded_from_average', true, 'manual_start', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM2Y1', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'cycle_start_date', '2026-08-01', 'excluded_from_average', false, 'manual_start', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
  '[]'::jsonb,
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_4), 0,
  'sync_push call 4 (p_cycle_overrides, 2 rows): rejected is empty');

create temp table seed_result_5 (v jsonb);
insert into seed_result_5 select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33H', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Cramps responded well to a heat pad this cycle.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33J', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Sleep quality improved on evenings without screens.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33K', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Energy dips consistently mid-afternoon; worth watching.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33M', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Hydration seems correlated with fewer headaches.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33N', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Iron-rich meals on heavy days seem to help fatigue.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33P', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Check-in: mood steady this month overall.', 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from seed_result_5), 0,
  'sync_push call 5 (p_care_notes, 6 rows): rejected is empty');

create temp table seed_result_6 (v jsonb);
insert into seed_result_6 select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33Q', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Write down sleep hours for the past week', 'is_checked', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33R', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Record how many heavy-flow days this cycle', 'is_checked', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33S', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Bring the cycle history printout', 'is_checked', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33T', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Bring the temperature tracking chart', 'is_checked', true, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33V', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'List current supplements and medications', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33W', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Confirm next appointment date', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33X', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Note mood changes in the week before the period', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33Y', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Record average cycle length for the last 6 months', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM33Z', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Note any mid-cycle pain days', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
jsonb_build_object('id', '01M2FWKNG0ZMH2ANCH7R2CM340', 'profile_id', '01M2FWKNG0ZMH2ANCH7R2CM2XZ', 'body', 'Note down questions about cramp relief', 'is_checked', false, 'updated_at', to_char((now() - interval '2 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));

select is((select jsonb_array_length(v -> 'rejected') from seed_result_6), 0,
  'sync_push call 6 (p_visit_prep_items, 10 rows): rejected is empty');

select is(
  (select count(*)::integer from public.profiles
    where display_name = 'Maya' and deleted_at is null),
  1,
  'the seeded profile landed (count pinned)');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and flow <> 'spotting'),
  62,
  'every seeded day entry landed live, none carrying the deprecated spotting flow');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'bbt'),
  62,
  'the seeded BBT observation rows landed');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'weight'),
  9,
  'the seeded weight observation rows landed');
select is(
  (select count(*)::integer from public.profile_modes),
  1,
  'the profile_modes row landed');
select is(
  (select count(*)::integer from public.cycle_overrides
    where excluded_from_average),
  1,
  'the excluded_from_average cycle override landed');
select is(
  (select count(*)::integer from public.cycle_overrides where manual_start),
  1,
  'the manual_start cycle override landed');
select is(
  (select count(*)::integer from public.care_notes where deleted_at is null),
  6,
  'the seeded care notes landed');
select is(
  (select count(*)::integer from public.visit_prep_items
    where deleted_at is null and is_checked),
  4,
  'the seeded visit-prep items landed, with the checked ones checked');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and pms),
  5,
  'PMS-marker days landed with pms = true');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and pms and jsonb_array_length(tags) > 0),
  5,
  'every PMS day carries at least one taxonomy tag');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'spotting'),
  1,
  'spotting days are observations (never a flow level)');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'bbt' and excluded),
  0,
  'the excluded BBT outliers are marked excluded');

select * from finish();
rollback;
