/// Emits the generated pgTAP fixture (issue #710, AC #4):
/// `supabase/tests/seed_sync_push_sample_test.sql`.
///
/// The fixture embeds a SMALL payload (single adult profile, 2 months) from
/// the same [generateSeedPayload] the runtime uses, signs in a pgTAP
/// fixture user, replays every `sync_push` call, and asserts `rejected` is
/// empty plus spot-check counts. CI's `db-tests` job therefore proves the
/// seeder's payload shapes against the real function on every PR.
///
/// `updated_at` values are emitted as SQL `to_char(now() ...)` expressions
/// (not literals) so the fixture never ages past the server's 180-day
/// tombstone-resurrection window no matter when it runs.
///
/// GENERATED FILE — regenerate with:
/// `dart run tool/seed_test_accounts/main.dart --emit-pgtap supabase/tests/seed_sync_push_sample_test.sql`
library;

import 'payload_generator.dart';
import 'sync_chunker.dart';

/// Fixed inputs for the fixture payload (deliberately small; independent
/// of the runtime defaults so regenerating the fixture never silently
/// changes size).
const int kPgtapFixtureMonths = 2;
const int kPgtapFixtureSeed = 71002;
DateTime kPgtapFixtureClock() => DateTime.utc(2026, 9, 14, 12);

String _sqlString(Object value) {
  final s = value.toString();
  return "'${s.replaceAll("'", "''")}'";
}

String _jsonbValue(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double) {
    // Emit as a JSON number literal (jsonb_build_object accepts text for
    // to_jsonb coercion; using to_jsonb on a numeric string is lossless).
    return 'to_jsonb(${_sqlString(value.toString())}::numeric)';
  }
  if (value is List) {
    final inner = [
      for (final element in value) _sqlString(element as Object),
    ].join(', ');
    return 'jsonb_build_array($inner)';
  }
  return _sqlString(value);
}

String _rowExpr(Map<String, Object?> row, {required String updatedAtSql}) {
  final parts = <String>[];
  for (final entry in row.entries) {
    if (entry.key == 'updated_at') {
      parts.add("'updated_at', $updatedAtSql");
      continue;
    }
    parts.add("'${entry.key}', ${_jsonbValue(entry.value)}");
  }
  return 'jsonb_build_object(${parts.join(', ')})';
}

String _batchArrayExpr(String paramName, SyncPushBatch batch, String updatedAtSql) {
  final rows = batch.params[paramName]!;
  // Postgres caps a single function call at 100 arguments, and each row is
  // one argument to jsonb_build_array — so large batches are emitted as
  // several <= 50-row arrays concatenated with ||.
  const chunkSize = 50;
  final chunks = <String>[];
  for (var i = 0; i < rows.length; i += chunkSize) {
    final end = (i + chunkSize).clamp(0, rows.length);
    final rowExprs = [
      for (final row in rows.sublist(i, end))
        _rowExpr(row, updatedAtSql: updatedAtSql),
    ];
    chunks.add('jsonb_build_array(\n${rowExprs.join(',\n')})');
  }
  if (chunks.isEmpty) return "'[]'::jsonb";
  return chunks.join('\n||');
}

/// Builds the fixture file content.
String buildPgtapFixture() {
  final payload = generateSeedPayload(SeedSpec(
    months: kPgtapFixtureMonths,
    seed: kPgtapFixtureSeed,
    clock: kPgtapFixtureClock,
    includeTeenProfile: false,
  ));
  final batches = chunkForSyncPush(payload);

  // One shared updated_at expression: the payload's single anchor,
  // re-expressed relative to the database's own now() at test time (2 days
  // ago keeps every insert inside the 180-day window with margin).
  const updatedAtSql =
      "to_char((now() - interval '2 days') at time zone 'UTC', "
      "'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')";

  final chunksSql = StringBuffer();
  var assertionCount = 0;
  const allParams = [
    'p_profiles',
    'p_day_entries',
    'p_observations',
    'p_profile_modes',
    'p_cycle_overrides',
    'p_care_notes',
    'p_visit_prep_items',
  ];
  for (var i = 0; i < batches.length; i++) {
    final batch = batches[i];
    // Positional args, every one of the seven supplied (empty tables as
    // '[]'::jsonb) so a batch carrying only a later table stays valid.
    final args = [
      for (final param in allParams)
        batch.params.containsKey(param)
            ? _batchArrayExpr(param, batch, updatedAtSql)
            : "'[]'::jsonb",
    ].join(',\n  ');
    chunksSql
      ..writeln(
        'create temp table seed_result_$i (v jsonb);',
      )
      ..writeln(
        'insert into seed_result_$i select public.sync_push(',
      )
      ..writeln('  $args);')
      ..writeln()
      ..writeln(
        "select is((select jsonb_array_length(v -> 'rejected') "
        "from seed_result_$i), 0,")
      ..writeln(
        "  'sync_push call $i (${batch.tableName}, ${batch.totalRows} rows): "
        "rejected is empty');")
      ..writeln();
    assertionCount++;
  }

  // Spot-check counts and shape pins.
  final spotChecks = '''
select is(
  (select count(*)::integer from public.profiles
    where display_name = 'Maya' and deleted_at is null),
  ${payload.profiles.length},
  'the seeded profile landed (count pinned)');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and flow <> 'spotting'),
  ${payload.dayEntries.length},
  'every seeded day entry landed live, none carrying the deprecated spotting flow');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'bbt'),
  ${payload.observations.where((o) => o['category'] == 'bbt').length},
  'the seeded BBT observation rows landed');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'weight'),
  ${payload.observations.where((o) => o['category'] == 'weight').length},
  'the seeded weight observation rows landed');
select is(
  (select count(*)::integer from public.profile_modes),
  ${payload.profileModes.length},
  'the profile_modes row landed');
select is(
  (select count(*)::integer from public.cycle_overrides
    where excluded_from_average),
  ${payload.cycleOverrides.where((c) => c['excluded_from_average'] == true).length},
  'the excluded_from_average cycle override landed');
select is(
  (select count(*)::integer from public.cycle_overrides where manual_start),
  ${payload.cycleOverrides.where((c) => c['manual_start'] == true).length},
  'the manual_start cycle override landed');
select is(
  (select count(*)::integer from public.care_notes where deleted_at is null),
  ${payload.careNotes.length},
  'the seeded care notes landed');
select is(
  (select count(*)::integer from public.visit_prep_items
    where deleted_at is null and is_checked),
  ${payload.visitPrepItems.where((v) => v['is_checked'] == true).length},
  'the seeded visit-prep items landed, with the checked ones checked');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and pms),
  ${payload.dayEntries.where((d) => d['pms'] == true).length},
  'PMS-marker days landed with pms = true');
select is(
  (select count(*)::integer from public.day_entries
    where deleted_at is null and pms and jsonb_array_length(tags) > 0),
  ${payload.dayEntries.where((d) => d['pms'] == true).length},
  'every PMS day carries at least one taxonomy tag');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'spotting'),
  ${payload.observations.where((o) => o['category'] == 'spotting').length},
  'spotting days are observations (never a flow level)');
select is(
  (select count(*)::integer from public.observations
    where deleted_at is null and category = 'bbt' and excluded),
  ${payload.observations.where((o) => o['excluded'] == true).length},
  'the excluded BBT outliers are marked excluded');
''';
  assertionCount += 13;

  return '''
-- GENERATED FILE -- DO NOT EDIT.
--
-- Issue #710's seeder fixture: a small, deterministic sync_push payload
-- (single adult profile, ~2 months) produced by the same generator the
-- operator tool uses (tool/seed_test_accounts/payload_generator.dart),
-- replayed against the real public.sync_push so CI (db-tests) proves the
-- seeder's payload shapes survive the live function with zero rejections.
--
-- Regenerate with:
--   dart run tool/seed_test_accounts/main.dart --emit-pgtap \\
--     supabase/tests/seed_sync_push_sample_test.sql
--
-- updated_at values are relative to now() so this file never ages past
-- sync_push's 180-day tombstone-resurrection window.
begin;
select plan($assertionCount);

select tests.create_supabase_user('seed_sample_user');
select tests.authenticate_as('seed_sample_user');

$chunksSql$spotChecks
select * from finish();
rollback;
''';
}
