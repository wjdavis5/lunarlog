/// Client-side mirror of `sync_push`'s row-shape rules (issue #710).
///
/// These constants and [validateSeedPayload] exist so the seeder's tests
/// can assert — without a database — that every emitted row is exactly
/// within the allowlists `20260915200001_sync_push_tombstone_resurrection_
/// guard.sql` enforces (`c_profile_keys`, `c_day_entry_keys`, ...). The
/// lists below are deliberately hand-kept mirrors of that file's constant
/// arrays; drift in either direction is caught by the generated pgTAP
/// fixture (`supabase/tests/seed_sync_push_sample_test.sql`), which runs
/// the same payload through the real function in CI.
library;

import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/tags.dart';

import 'payload_generator.dart';
import 'sync_chunker.dart';

const Set<String> kProfileKeys = {
  'id', 'display_name', 'is_minor', 'sort_order', 'archived_at',
  'created_at', 'updated_at', 'deleted_at',
  'birth_year', 'relationship',
  'mode',
  'last_period_start', 'typical_cycle_length_days', 'typical_period_length_days',
  'bbt_unit', 'weight_unit',
  'tracking_preferences',
  'user_id', 'server_version', 'transferred_at', 'transferred_to_user_id',
};

const Set<String> kDayEntryKeys = {
  'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
  'pms',
  'source', 'source_id', 'import_id',
  'updated_at', 'deleted_at',
  'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
};

const Set<String> kObservationKeys = {
  'id', 'day_entry_id', 'profile_id', 'local_date', 'observed_at', 'tz',
  'category', 'code', 'value_num', 'value_text', 'unit', 'intensity',
  'excluded', 'source', 'source_id',
  'import_id',
  'exported_to_platform_at', 'raw', 'updated_at', 'deleted_at',
  'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
  'created_at',
};

const Set<String> kProfileModeKeys = {
  'profile_id', 'mode', 'mode_started_on', 'birth_control_method',
  'birth_control_started_on', 'birth_control_stopped_on',
  'health_sync_consent', 'updated_at',
  'server_version',
};

const Set<String> kCycleOverrideKeys = {
  'id', 'profile_id', 'cycle_start_date', 'excluded_from_average',
  'manual_start', 'note_id', 'updated_at', 'deleted_at',
  'server_version',
};

const Set<String> kCareNoteKeys = {
  'id', 'profile_id', 'body', 'updated_at', 'deleted_at',
  'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
  'created_at',
};

const Set<String> kVisitPrepItemKeys = {
  'id', 'profile_id', 'body', 'is_checked', 'updated_at', 'deleted_at',
  'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
  'created_at',
};

/// The live (writable) flow wire set — the deprecated `spotting` alias is
/// deliberately absent: spotting is an observations category, never a flow
/// level (issue #247).
const Set<String> kWritableFlowLevels = {
  'none',
  'not_bleeding',
  'light',
  'medium',
  'heavy',
  'super_heavy',
};

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A single violation; [describe] is safe to print (no payload values).
class SeedRowViolation {
  const SeedRowViolation(this.table, this.id, this.rule);

  final String table;
  final String id;
  final String rule;

  @override
  String toString() => '$table[$id]: $rule';
}

void _checkKeys(
  String table,
  Map<String, Object?> row,
  Set<String> allowed,
  String id,
  List<SeedRowViolation> out,
) {
  for (final key in row.keys) {
    if (!allowed.contains(key)) {
      out.add(SeedRowViolation(table, id, 'unknown key "$key"'));
    }
  }
}

void _checkUlid(
  String table,
  String? id,
  List<SeedRowViolation> out, {
  String field = 'id',
}) {
  if (id == null || !isValidUlid(id)) {
    out.add(SeedRowViolation(table, id ?? '<null>', '$field is not a ULID'));
  }
}

void _checkIsoDate(
  String table,
  String id,
  String field,
  Object? value,
  List<SeedRowViolation> out,
) {
  final v = value;
  if (v is! String || !_isoDate.hasMatch(v)) {
    out.add(SeedRowViolation(table, id, '$field is not an ISO calendar date'));
  }
}

/// Validates [payload] against the mirrored server rules. Returns every
/// violation found (empty list = the payload is sync_push-clean).
List<SeedRowViolation> validateSeedPayload(SeedPayload payload) {
  final out = <SeedRowViolation>[];
  final anchor = payload.anchor;

  void checkUpdatedAt(String table, String id, Object? value) {
    if (value is! String) {
      out.add(SeedRowViolation(table, id, 'updated_at is missing'));
      return;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      out.add(SeedRowViolation(table, id, 'updated_at is not a timestamp'));
    } else if (parsed.isAfter(anchor.add(const Duration(minutes: 5)))) {
      out.add(SeedRowViolation(
          table, id, 'updated_at is more than 5 minutes past the anchor'));
    } else if (parsed
        .isBefore(anchor.subtract(const Duration(days: 170)))) {
      out.add(SeedRowViolation(table, id,
          'updated_at is older than the ~170-day seeding policy window'));
    }
  }

  // profiles
  final profileIds = <String>{};
  for (final row in payload.profiles) {
    final id = row['id'] as String?;
    _checkUlid('profiles', id, out);
    if (id != null) profileIds.add(id);
    _checkKeys('profiles', row, kProfileKeys, id ?? '<null>', out);
    checkUpdatedAt('profiles', id ?? '<null>', row['updated_at']);
    final name = row['display_name'];
    if (name is String && name.length > kMaxDisplayNameLength) {
      out.add(SeedRowViolation('profiles', id ?? '<null>',
          'display_name exceeds kMaxDisplayNameLength'));
    }
    _checkIsoDate(
        'profiles', id ?? '<null>', 'last_period_start', row['last_period_start'], out);
  }

  // day entries: exactly one live row per (profile, local_date), flow in
  // the writable set, tags valid + bounded, note bounded.
  final liveDayKeys = <String>{};
  for (final row in payload.dayEntries) {
    final id = row['id'] as String?;
    _checkUlid('day_entries', id, out);
    final pid = row['profile_id'] as String?;
    _checkUlid('day_entries', pid, out, field: 'profile_id');
    _checkKeys('day_entries', row, kDayEntryKeys, id ?? '<null>', out);
    checkUpdatedAt('day_entries', id ?? '<null>', row['updated_at']);
    _checkIsoDate(
        'day_entries', id ?? '<null>', 'local_date', row['local_date'], out);
    final flow = row['flow'];
    if (flow is! String || !kWritableFlowLevels.contains(flow)) {
      out.add(SeedRowViolation('day_entries', id ?? '<null>',
          'flow "$flow" is not in the writable flow set'));
    }
    if (pid != null && row['local_date'] is String) {
      final key = '$pid|${row['local_date']}';
      if (!liveDayKeys.add(key)) {
        out.add(SeedRowViolation(
            'day_entries', id ?? '<null>', 'two live rows for one (profile, local_date)'));
      }
    }
    final tags = row['tags'];
    if (tags != null) {
      if (tags is! List || tags.length > kMaxTagCount) {
        out.add(SeedRowViolation(
            'day_entries', id ?? '<null>', 'tags exceeds kMaxTagCount'));
      } else {
        for (final tag in tags) {
          if (tag is! String ||
              tag.length > kMaxTagLength ||
              !isValidTagCode(tag)) {
            out.add(SeedRowViolation('day_entries', id ?? '<null>',
                'tag "$tag" is not a valid taxonomy code'));
          }
        }
      }
    }
    final note = row['note'];
    if (note is String && note.length > kMaxNoteLength) {
      out.add(SeedRowViolation(
          'day_entries', id ?? '<null>', 'note exceeds kMaxNoteLength'));
    }
  }
  final dayEntryIds = payload.dayEntries
      .map((r) => r['id'])
      .whereType<String>()
      .toSet();

  // observations: parent must be present in the same payload, no two live
  // rows share (profile, local_date, category, code), category/code
  // lengths bounded.
  final liveObsKeys = <String>{};
  for (final row in payload.observations) {
    final id = row['id'] as String?;
    _checkUlid('observations', id, out);
    _checkKeys('observations', row, kObservationKeys, id ?? '<null>', out);
    checkUpdatedAt('observations', id ?? '<null>', row['updated_at']);
    _checkIsoDate(
        'observations', id ?? '<null>', 'local_date', row['local_date'], out);
    final parent = row['day_entry_id'];
    if (parent is! String || !dayEntryIds.contains(parent)) {
      out.add(SeedRowViolation('observations', id ?? '<null>',
          'day_entry_id does not reference a payload day entry'));
    }
    final category = row['category'];
    if (category is String && category.length > kMaxObservationCategoryLength) {
      out.add(SeedRowViolation('observations', id ?? '<null>',
          'category exceeds kMaxObservationCategoryLength'));
    }
    final code = row['code'];
    if (code is String && code.length > kMaxObservationCodeLength) {
      out.add(SeedRowViolation(
          'observations', id ?? '<null>', 'code exceeds kMaxObservationCodeLength'));
    }
    final intensity = row['intensity'];
    if (intensity != null &&
        (intensity is! int ||
            intensity < kMinObservationIntensity ||
            intensity > kMaxObservationIntensity)) {
      out.add(SeedRowViolation(
          'observations', id ?? '<null>', 'intensity outside 1-5'));
    }
    if (category is String && code is String && row['local_date'] is String) {
      final pid = row['profile_id'];
      final key = '$pid|${row['local_date']}|$category|$code';
      if (!liveObsKeys.add(key)) {
        out.add(SeedRowViolation('observations', id ?? '<null>',
            'two live rows share (profile, local_date, category, code)'));
      }
    }
  }

  // profile_modes: keyed by profile_id, no id, no tombstone.
  for (final row in payload.profileModes) {
    final pid = row['profile_id'] as String?;
    _checkUlid('profile_modes', pid, out, field: 'profile_id');
    _checkKeys('profile_modes', row, kProfileModeKeys, pid ?? '<null>', out);
    checkUpdatedAt('profile_modes', pid ?? '<null>', row['updated_at']);
    if (row.containsKey('id') || row.containsKey('deleted_at')) {
      out.add(SeedRowViolation(
          'profile_modes', pid ?? '<null>', 'profile_modes rows carry no id and no tombstone'));
    }
    if (pid != null && !profileIds.contains(pid)) {
      out.add(SeedRowViolation(
          'profile_modes', pid, 'profile_id is not a payload profile'));
    }
  }

  // cycle_overrides
  for (final row in payload.cycleOverrides) {
    final id = row['id'] as String?;
    _checkUlid('cycle_overrides', id, out);
    _checkKeys('cycle_overrides', row, kCycleOverrideKeys, id ?? '<null>', out);
    checkUpdatedAt('cycle_overrides', id ?? '<null>', row['updated_at']);
    _checkIsoDate('cycle_overrides', id ?? '<null>', 'cycle_start_date',
        row['cycle_start_date'], out);
    final pid = row['profile_id'];
    if (pid is! String || !profileIds.contains(pid)) {
      out.add(SeedRowViolation(
          'cycle_overrides', id ?? '<null>', 'profile_id is not a payload profile'));
    }
  }

  // care_notes / visit_prep_items
  for (final row in payload.careNotes) {
    final id = row['id'] as String?;
    _checkUlid('care_notes', id, out);
    _checkKeys('care_notes', row, kCareNoteKeys, id ?? '<null>', out);
    checkUpdatedAt('care_notes', id ?? '<null>', row['updated_at']);
    final body = row['body'];
    if (body is! String || body.isEmpty || body.length > kMaxCareNoteLength) {
      out.add(SeedRowViolation(
          'care_notes', id ?? '<null>', 'body is missing or over kMaxCareNoteLength'));
    }
  }
  for (final row in payload.visitPrepItems) {
    final id = row['id'] as String?;
    _checkUlid('visit_prep_items', id, out);
    _checkKeys('visit_prep_items', row, kVisitPrepItemKeys, id ?? '<null>', out);
    checkUpdatedAt('visit_prep_items', id ?? '<null>', row['updated_at']);
    final body = row['body'];
    if (body is! String ||
        body.isEmpty ||
        body.length > kMaxVisitPrepItemLength) {
      out.add(SeedRowViolation('visit_prep_items', id ?? '<null>',
          'body is missing or over kMaxVisitPrepItemLength'));
    }
    if (row.containsKey('checked_by_user_id') ||
        row.containsKey('checked_at')) {
      out.add(SeedRowViolation('visit_prep_items', id ?? '<null>',
          'checked_by_user_id/checked_at are server-stamped, never sent'));
    }
  }

  return out;
}

/// Validates the chunking invariants (<= 500/array, <= 3500/call) over
/// [batches]; returns violation descriptions (empty = clean).
List<String> validateBatchCaps(List<SyncPushBatch> batches) {
  final out = <String>[];
  for (final batch in batches) {
    for (final entry in batch.params.entries) {
      if (entry.value.length > kSyncPushMaxRowsPerArray) {
        out.add('${entry.key} carries ${entry.value.length} rows (> 500)');
      }
    }
    if (batch.totalRows > kSyncPushMaxTotalRows) {
      out.add('${batch.tableName} batch carries ${batch.totalRows} rows (> 3500)');
    }
  }
  return out;
}
