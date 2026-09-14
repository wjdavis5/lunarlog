/// Issue #520's guard test: enumerates every column defined in
/// `lib/data/db/tables.dart` and every `'p_…'` string literal anywhere in
/// `lib/`, and asserts each one is either deny-listed
/// ([isDenyListedKey]) or explicitly waived below with a reason. A column
/// or RPC parameter added later that is neither is a build failure, not a
/// silent gap — which is exactly the drift #497 and #520 found (three of
/// seven `sync_push` parameters, and a stack of columns from two later
/// feature waves, had quietly gone unlisted).
///
/// This intentionally parses the *source* of `tables.dart` rather than
/// importing Drift's generated table metadata: every column here — Drift
/// getter or `sync_push`/RPC parameter — is a plain string name, and
/// reading the source directly keeps this test decoupled from
/// `build_runner` output and usable as a fast, no-codegen lint.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/scrub.dart';

/// Converts a Dart camelCase identifier to the snake_case name Drift gives
/// a column with no explicit `.named(...)` override (matching Drift's own
/// default column-naming convention).
String _camelToSnake(String identifier) {
  final buffer = StringBuffer();
  for (var i = 0; i < identifier.length; i++) {
    final char = identifier[i];
    final isUpper = char != char.toLowerCase();
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

/// One capturing group per column getter's declaration (from `TextColumn`/
/// `BoolColumn`/`IntColumn`/`DateTimeColumn`/`RealColumn get <name> =>` to
/// the terminating `;`), with the getter name in group 1 and the rest of
/// the declaration (searched below for an explicit `.named(...)`) in
/// group 2. Column declarations in this file are single fields with no
/// nested `;`, so stopping at the first `;` is exact.
final RegExp _columnDeclaration = RegExp(
  r'(?:TextColumn|BoolColumn|IntColumn|DateTimeColumn|RealColumn)\s+get\s+'
  r'(\w+)\s*=>([^;]*);',
  dotAll: true,
);

final RegExp _namedOverride = RegExp(r"\.named\('([a-zA-Z0-9_]+)'\)");

/// Every column name declared in [source] (the actual database column
/// name: the `.named(...)` override when present, else the snake_case form
/// of the getter).
Set<String> extractTableColumnNames(String source) {
  final columns = <String>{};
  for (final match in _columnDeclaration.allMatches(source)) {
    final getter = match.group(1)!;
    final body = match.group(2)!;
    final override = _namedOverride.firstMatch(body)?.group(1);
    columns.add(override ?? _camelToSnake(getter));
  }
  return columns;
}

final RegExp _pLiteral = RegExp(r"'(p_[a-zA-Z0-9_]*)'");

/// Every `'p_…'` single-quoted string literal anywhere under [libDir],
/// recursively — the RPC/sync_push parameter names (issue #520 asks for
/// this exact scan).
Set<String> extractPPrefixedLiterals(Directory libDir) {
  final literals = <String>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final match in _pLiteral.allMatches(entity.readAsStringSync())) {
      literals.add(match.group(1)!);
    }
  }
  return literals;
}

/// Columns and RPC parameters that are deliberately NOT deny-listed,
/// each with the reason it is safe to leave uncovered. Every entry here is
/// either (a) a bookkeeping field shared across most/all tables (an
/// opaque id, a sync timestamp/counter/flag) that carries no health
/// content by itself, or (b) a closed-set/bounded value distinct from the
/// open free text the deny list exists to catch.
///
/// `category`/`code`/`unit`/`intensity`/`excluded` (Observations) get the
/// same reasoning as issue #520 itself flags them for care around: they
/// are near-closed-vocabulary labels, not open free text, and — unlike
/// every other waived entry — a generic word among them (`code`) already
/// appears as an innocuous key in a real breadcrumb elsewhere
/// (`{'code': 'canceled'}`, a Google sign-in outcome); deny-listing it
/// would false-positive-drop that breadcrumb, which carries no health
/// content at all. See `lib/observability/scrub.dart`'s
/// `sentryDenyListedKeys` doc comment for the same note in context.
const Map<String, String> _waivedKeys = {
  // Opaque ULID/id references — not free-text content.
  'id': 'opaque ULID identifier, not free-text content',
  'profile_id': 'opaque ULID reference, not free-text content',
  'day_entry_id': 'opaque ULID reference, not free-text content',
  'transferred_to_user_id': 'opaque auth user id, not content',
  'logged_by_user_id': 'opaque auth user id, not content',
  'last_modified_by_user_id': 'opaque auth user id, not content',
  'user_id': 'opaque auth user id, not content',
  'invited_by': 'opaque auth user id, not content',
  'checked_by_user_id': 'opaque auth user id, not content',
  'bound_user_id': 'opaque auth user id, not content',
  'device_id': 'opaque per-install device identifier, not content',
  'source_id': 'import/device provenance key, not health content',
  'import_id': 'placeholder FK to a future import job row, not content',
  'p_connection_id': 'opaque prediction-connection id RPC parameter',
  'p_id': 'opaque push-device-registry id RPC parameter',
  'p_import_id': 'opaque bulk-import job id RPC parameter',
  'p_invitation_id': 'opaque sharing-invitation id RPC parameter',
  'p_profile_id': 'opaque profile id RPC parameter',
  'p_target_user_id': 'opaque auth user id RPC parameter',
  'p_transfer_id': 'opaque ownership-transfer id RPC parameter',

  // Device-local sync/lifecycle bookkeeping — timestamps, counters, flags.
  'sort_order': 'device-local display ordering, not content',
  'archived_at': 'lifecycle bookkeeping timestamp, not content',
  'created_at': 'lifecycle bookkeeping timestamp, not content',
  'updated_at': 'sync bookkeeping timestamp, not content',
  'deleted_at': 'tombstone bookkeeping timestamp, not content',
  'dirty': 'device-local sync flag, not content',
  'local_rev': 'device-local sync revision counter, not content',
  'transferred_at': 'ownership-transfer bookkeeping timestamp, not content',
  'observed_at': 'observation timestamp, not content by itself',
  'exported_to_platform_at':
      'health-platform export bookkeeping timestamp, not content',
  'is_checked': 'checklist boolean state, not content',
  'checked_at': 'checklist bookkeeping timestamp, not content',
  'excluded_from_average':
      'boolean flag about cycle-average membership, not content',
  'manual_start': 'boolean flag about how a cycle began, not content',
  'cursor_profiles': 'device-local sync cursor, not content',
  'cursor_day_entries': 'device-local sync cursor, not content',
  'cursor_observations': 'device-local sync cursor, not content',
  'cursor_profile_modes': 'device-local sync cursor, not content',
  'cursor_cycle_overrides': 'device-local sync cursor, not content',
  // cursor_care_notes is NOT here: its normalised form ('cursorcarenotes')
  // contains the 'note' stem, so isDenyListedKey already catches it — a
  // waiver here would be redundant (and the redundant-waiver test below
  // would catch it if it crept back in).
  'cursor_visit_prep_items': 'device-local sync cursor, not content',
  'cursor_profile_guardians':
      'device-local sync cursor, not content (issue #525)',
  'cursor_deleted_profiles':
      'device-local sync cursor, not content (issue #597)',
  'last_full_pull_at': 'device-local sync bookkeeping timestamp, not content',
  'last_sync_at': 'device-local sync bookkeeping timestamp, not content',
  'server_clock_offset_ms': 'device-local clock-skew bookkeeping, not content',
  'last_error':
      "documented (SyncState.lastError) as a type name or short code, "
          'never health content',
  'last_synced_at': 'health-platform sync bookkeeping timestamp, not content',
  'p_episode_open': 'boolean reminder-window RPC parameter, not content',
  'p_ttl_hours': 'numeric TTL RPC parameter, not content',
  'server_version':
      'server-owned monotonic sync-ordering counter (issue #635), not content',
  'access_revoked_at':
      'device-local revocation-eviction bookkeeping timestamp (issue #635), '
          'not content',
  'units_unconfirmed':
      'device-local boolean marking whether bbt_unit/weight_unit have been '
          'confirmed against a real server value since the v20 upgrade '
          '(issue #637, LLA-039), not content',
  'pms_unconfirmed':
      'device-local boolean marking whether pms has been confirmed '
          'against a real server value since the v20 upgrade (issue #637, '
          'LLA-039), not content',

  // Closed-set / bounded values — distinct from open free text.
  'relationship': 'closed-set relationship-to-creator enum, not free text',
  'source': "closed-set provenance enum ('manual'/'healthkit'/…), not content",
  'role': 'closed-set guardian role enum, not free text',
  'status': 'closed-set invitation/guardian status enum, not free text',
  'unit': "closed-set unit enum ('celsius'/'kg'/…), not free text",
  'intensity': 'bounded 1-5 intensity score, not free text',
  'platform':
      "closed-set platform enum ('healthkit'/'health_connect'/'ios'/"
          "'android'), not content",
  'anchor':
      'opaque per-platform health-sync change token/cursor, not a '
          'credential and not health content',
  'p_new_role': 'closed-set guardian role RPC parameter, not free text',
  'p_role': 'closed-set guardian role RPC parameter, not free text',
  'p_parent_post_transfer_role':
      'closed-set role RPC parameter, not free text',
  'p_platform': 'closed-set device-OS RPC parameter, not content',

  // Generic near-closed-vocabulary labels — see the class doc above for
  // why these specifically stay off the deny list.
  'category': 'near-closed-vocabulary observation label, not open free '
      'text; colliding with it as a bare word would false-positive-drop '
      "unrelated breadcrumbs (e.g. a sign-in breadcrumb's own 'category'-"
      'shaped fields)',
  'code': "near-closed-vocabulary observation label, not open free text; "
      "collides with the OAuth breadcrumb field {'code': 'canceled'} used "
      'elsewhere, which carries no health content',
  'excluded': "Observations' per-point BBT exclusion flag, not content",

  // Device-local, non-health settings.
  'key': "AppSettings' setting-name key, not content (the paired 'value' "
      "column IS deny-listed, via the 'value' stem)",
  'tz': 'IANA time zone name, not content',

  // Per-profile display-unit preferences (Issue #255): closed-set
  // presentation enums ('celsius'/'fahrenheit', 'kg'/'lb') — they say how
  // to render a measurement, never the measurement itself.
  'bbt_unit': "display-unit preference enum ('celsius'/'fahrenheit'), not content",
  'weight_unit': "display-unit preference enum ('kg'/'lb'), not content",
};

void main() {
  group('Issue #520 guard: deny-list coverage over tables.dart + p_ literals',
      () {
    late Set<String> columns;
    late Set<String> pLiterals;

    setUpAll(() {
      final tablesSource =
          File('lib/data/db/tables.dart').readAsStringSync();
      columns = extractTableColumnNames(tablesSource);
      pLiterals = extractPPrefixedLiterals(Directory('lib'));
    });

    test('the parser actually found columns and p_ literals (sanity)', () {
      // If either collection comes back empty, the regexes below are
      // silently matching nothing and every other assertion in this file
      // would pass vacuously.
      expect(columns.length, greaterThan(60),
          reason: 'expected 60+ distinct columns across all tables in '
              'tables.dart; the extraction regex may be broken');
      expect(pLiterals.length, greaterThan(20),
          reason: "expected 20+ distinct 'p_…' literals under lib/; the "
              'extraction regex may be broken');
      // Spot-check a couple of well-known names on each side.
      expect(columns, containsAll(['note', 'display_name', 'value_text']));
      expect(pLiterals, containsAll(['p_day_entries', 'p_observations']));
    });

    test('every tables.dart column is deny-listed or explicitly waived', () {
      final uncovered = <String>[];
      for (final column in columns) {
        if (isDenyListedKey(column)) continue;
        if (_waivedKeys.containsKey(column)) continue;
        uncovered.add(column);
      }
      expect(uncovered, isEmpty,
          reason: 'these tables.dart columns are neither deny-listed nor '
              'waived — add them to sentryDenyListedKeys (scrub.dart) or to '
              '_waivedKeys (this file) with a reason:\n'
              '${uncovered.join('\n')}');
    });

    test("every 'p_…' literal in lib/ is deny-listed or explicitly waived",
        () {
      final uncovered = <String>[];
      for (final literal in pLiterals) {
        if (isDenyListedKey(literal)) continue;
        if (_waivedKeys.containsKey(literal)) continue;
        uncovered.add(literal);
      }
      expect(uncovered, isEmpty,
          reason: "these 'p_…' literals are neither deny-listed nor "
              'waived — add them to sentryDenyListedKeys (scrub.dart) or to '
              '_waivedKeys (this file) with a reason:\n'
              '${uncovered.join('\n')}');
    });

    test('every waiver reason is non-empty and every waived name is real '
        '(no stale waivers)', () {
      for (final entry in _waivedKeys.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
      final known = {...columns, ...pLiterals};
      final stale =
          _waivedKeys.keys.where((k) => !known.contains(k)).toList();
      expect(stale, isEmpty,
          reason: 'these waivers no longer match any column or p_ literal '
              '— remove them:\n${stale.join('\n')}');
    });

    test('no name is both deny-listed and waived (a waiver that stops '
        'meaning anything should be deleted, not kept)', () {
      final redundant = _waivedKeys.keys.where(isDenyListedKey).toList();
      expect(redundant, isEmpty,
          reason: 'these are already caught by isDenyListedKey — the '
              'waiver is redundant and should be removed:\n'
              '${redundant.join('\n')}');
    });
  });
}
