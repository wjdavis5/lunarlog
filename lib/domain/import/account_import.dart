/// Restore-from-file import (Issue #140): the counterpart to
/// `lib/domain/export/account_export.dart`. Pure Dart, no Flutter/drift
/// (R14/R16) — the only untestable-under-`flutter test` parts of import are
/// the platform file picker (`lib/data/import/import_file_picker.dart`) and
/// the Drift transaction that applies a plan
/// (`lib/data/import/account_importer.dart`); everything here is a plain
/// function over bytes and already-loaded domain models.
///
/// Three steps, matching the UI flow (pick -> preview -> confirm):
/// * [parseAccountImport] turns raw file bytes into a validated
///   [AccountImportDocument], or a single [AccountImportError] describing
///   why the file was rejected. Validation here is deliberately strict and
///   whole-document (KTD-style "never partially apply a failed import"):
///   an import file is untrusted input that may carry health data (issue
///   design constraints), and every bound checked here mirrors
///   `lib/domain/limits.dart` exactly, so a row a genuine export from this
///   app could never have produced (an over-length note, an oversize tag
///   array, a malformed date) is treated as evidence of tampering or
///   corruption and rejects the whole file rather than silently dropping
///   one row - nothing is written for a rejected document.
/// * [previewImport] summarizes an already-parsed document (profile count,
///   entry count, date range) for the screen's confirmation step, before
///   anything is compared against the local store.
/// * [planImport] compares the document against the local store's current
///   state and decides, per profile: create (using the file's own profile
///   id — see [ImportedProfile.id]'s doc comment), match (existing profile,
///   same id) and merge/add its entries and observations, or skip (the
///   device cannot write that profile - see [writeBlockReasonFor]). This is
///   where the merge policy lives: an entry colliding on (profileId,
///   localDate) unions its tags with the same rule the sync engine uses
///   (`lib/data/sync/conflict_rules.dart`'s `mergeTags`) but keeps the
///   heavier flow level and the non-empty note under import's own additive
///   rule — the sync engine itself is last-writer-wins for a same-date
///   collision (`sameDateWinner`: one row's flow/note wins wholesale, never
///   merged field-by-field), so only the tag half of this policy actually
///   mirrors it (see [kImportMergePolicySentence]'s doc comment). An
///   observation colliding on (profileId, localDate, category, code) is
///   left alone (kept, imported one skipped). Nothing is ever deleted, and
///   an existing row is never silently overwritten - see [ImportPlan]'s
///   own doc comment.
///
/// [planImport]'s output is applied by
/// `lib/data/import/account_importer.dart`'s `AccountImporter`, which wraps
/// every write for the whole document in one Drift transaction: a failure
/// partway through leaves the store exactly as it was (rollback), never a
/// partial import.
library;

import 'dart:convert';

import '../export/account_export.dart' show kAccountExportSchemaVersion;
import '../limits.dart';
import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import '../models/profile_guardian.dart';
import '../models/profile_mode.dart';
import '../util/timezone.dart' show isValidIanaTimeZone;

/// Byte cap on a picked import file, checked before any JSON decoding
/// (Issue #140 review): a hostile or corrupted file with an enormous byte
/// count would otherwise be handed straight to `jsonDecode`, which has no
/// size limit of its own. 32 MiB is generous for a real device's export
/// (JSON text, not media) while still bounding worst-case memory use.
const int kMaxImportFileBytes = 32 * 1024 * 1024;

/// Accepted `schemaVersion` range (Issue #140): every version
/// `lib/domain/export/account_export.dart` has ever shipped, up to and
/// including its current `kAccountExportSchemaVersion`. A document outside
/// this range - lower (should never happen; 1 is the floor this app has
/// ever exported) or higher (exported by a newer app version this build
/// predates) - is rejected with a clear message rather than guessed at.
const int kAccountImportMinSchemaVersion = 1;
const int kAccountImportMaxSchemaVersion = kAccountExportSchemaVersion;

/// Mirrors `lib/data/db/ulid.dart`'s own `_validUlid` pattern (26-char
/// Crockford base32) — duplicated here, not imported, since `lib/domain`
/// never depends on `lib/data` (R14/R16, `test/architecture/
/// layering_test.dart`); the same reasoning `row_codec.dart` gives for its
/// own date pattern. Issue #140 review round 2, item 1: a profile/day-entry/
/// observation `id` that isn't a syntactically valid ULID would otherwise be
/// written verbatim as a local primary key (profiles) or `source_id`
/// (entries/observations) and later handed to `row_codec.dart`'s
/// `encodeProfile`/`encodeDayEntry`/`encodeObservation` for `sync_push`,
/// which throws `RowCodecError(invalidId)` for anything else — a permanent,
/// silent sync outage rather than a clean import-time rejection.
final RegExp _validUlid = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$');

/// A conservative superset of RFC 4122 UUID text (8-4-4-4-12 hex, any
/// version/variant nibble) — Issue #140 review round 2, item 4:
/// `day_entries.import_id` is a Postgres `uuid` column and `sync_push`
/// casts the wire value with `::uuid`, so a malformed `importId` must never
/// reach that cast. Deliberately lenient about version/variant bits (this
/// is a format check, not a spec-compliance check).
final RegExp _validUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Caps how much of a raw, untrusted file value ever lands in a rejection
/// message (Issue #140 review round 2, item 5): `AccountImportError.message`
/// can surface in UI/logs, and a multi-megabyte `flow`/`mode`/date string
/// interpolated verbatim would make that message itself a vector for
/// bloating whatever displays or stores it.
const int _kMaxRejectedValueLength = 40;

/// Truncates [raw] to [_kMaxRejectedValueLength] characters (plus an
/// ellipsis when actually truncated) before it is interpolated into an
/// [_ImportFormatException] message.
String _truncateForMessage(String raw) => raw.length > _kMaxRejectedValueLength
    ? '${raw.substring(0, _kMaxRejectedValueLength)}…'
    : raw;

/// Requires [raw] to be a syntactically valid ULID (Issue #140 review
/// round 2, item 1) — see [_validUlid]'s doc comment for why. The raw value
/// is deliberately never interpolated into the message: an oversized or
/// binary-garbage id (a crafted or corrupted file) has no useful
/// human-readable form, and this mirrors item 5's truncate-before-
/// interpolating rule by simply not interpolating at all here.
String _requireUlid(Object? raw, {required String what}) {
  if (raw is! String || !_validUlid.hasMatch(raw)) {
    throw _ImportFormatException('$what is not a valid id.');
  }
  return raw;
}

/// One line, no raw exception text, describing why a file was rejected —
/// or, in [ImportPlanSummary.skippedProfiles], why one profile was.
class AccountImportError {
  const AccountImportError(this.message);

  final String message;

  @override
  String toString() => 'AccountImportError: $message';
}

/// A `profiles[].dayEntries[]` element straight out of the parsed
/// document — the file's own values, not yet compared against anything
/// stored locally. See [DayEntryPlan] for the merged/resolved values
/// [planImport] computes from this.
class ImportedDayEntry {
  const ImportedDayEntry({
    required this.id,
    required this.localDate,
    required this.tz,
    required this.flow,
    this.tags = const [],
    this.note,
    required this.updatedAt,
    required this.source,
    this.sourceId,
    this.importId,
  });

  /// The id this entry carried in the exporting device's store. Carried
  /// through to [DayEntryPlan.fileId] on a [DayEntryImportOutcome.add] and
  /// IS reused as the new row's own id — when it is a syntactically valid
  /// ULID (always true here; see [_requireUlid]) and no live row already
  /// occupies the slot — so that two devices importing the same file
  /// converge on the same row id instead of each minting their own (see
  /// [DayEntryPlan.fileId]'s own doc comment for the full rule, including
  /// the provenance-revival and freshly-generated-ULID fallbacks). It is
  /// never adopted on a [DayEntryImportOutcome.merge], which already
  /// targets a live row by (profileId, localDate) identity (see
  /// `domain.DayEntry`'s own doc comment); there, this id is kept only as
  /// the fallback `sourceId` for a file lacking its own provenance (see
  /// [source]'s doc comment).
  final String id;

  final LocalDate localDate;
  final String tz;
  final FlowLevel flow;
  final List<String> tags;
  final String? note;
  final DateTime updatedAt;

  /// The raw `toDb()` provenance this entry will be planned with (Issue
  /// #140 review, item 7): a v4 export's own `source`/`sourceId` (e.g.
  /// `clue_import`/`abc`) round-trips unchanged when present — "present"
  /// means a non-`manual` [source] or a non-null [sourceId] (a genuinely
  /// local row never carries a `sourceId`). A file with neither (an older
  /// schema version, or a plain `manual`/null row) falls back to this
  /// app's own `file_import`/[id] tag, same as before this review. Resolved
  /// once at parse time in [_parseDayEntry] so every later step (planning,
  /// the merge-vs-add decision, applying) just reads it.
  final String source;
  final String? sourceId;
  final String? importId;
}

/// A `profiles[].observations[]` element straight out of the parsed
/// document, mirroring [ImportedDayEntry]'s shape (Issue #240 export
/// shape).
class ImportedObservation {
  const ImportedObservation({
    required this.id,
    required this.localDate,
    this.observedAt,
    required this.tz,
    required this.category,
    this.code,
    this.valueNum,
    this.valueText,
    this.unit,
    this.intensity,
    this.excluded = false,
    this.raw,
  });

  final String id;
  final LocalDate localDate;
  final DateTime? observedAt;
  final String tz;
  final String category;
  final String? code;
  final double? valueNum;
  final String? valueText;
  final String? unit;
  final int? intensity;
  final bool excluded;

  /// Already re-encoded JSON text (never the decoded `Object?`), matching
  /// `domain.Observation.raw`'s own shape.
  final String? raw;
}

/// A `profiles[]` element straight out of the parsed document.
class ImportedProfile {
  const ImportedProfile({
    required this.id,
    required this.displayName,
    this.isMinor = false,
    this.mode,
    this.sortOrder = 0,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.dayEntries = const [],
    this.observations = const [],
  });

  /// The id this profile carried in the exporting device's store — the
  /// matching key [planImport] uses against the local store's own profile
  /// ids. Reused as-is for a newly *created* profile, not re-minted (Issue
  /// #140 review, item 2): ULIDs are collision-free, and restoring the
  /// same file onto a second device signed into the same account must
  /// resolve to the SAME server-side profile on the next sync, not a
  /// duplicate — `AccountImporter._resolveProfileId` passes this straight
  /// through to `LunarLogStorage.upsertProfile(id: ...)`, and re-importing
  /// the same file therefore plans this profile as `matched`, not
  /// `created`, the second time.
  final String id;

  final String displayName;
  final bool isMinor;

  /// Raw `toDb()` mode string, or null. Already validated against
  /// [ProfileMode]'s closed set at parse time ([_parseMode]) — unlike
  /// `LunarLogStorage.upsertProfile`'s own degrade-to-`standard` leniency
  /// (appropriate only for a value this app or the server already
  /// accepted), an untrusted import file never reaches storage carrying an
  /// unrecognised mode. Only consulted for a *created* profile
  /// (`AccountImporter._resolveProfileId`'s `mode: plan.mode ?? 'standard'`)
  /// — a *matched* profile, tombstone-*restored* ones included, keeps its
  /// own stored mode untouched; the file's value is never applied over it.
  final String? mode;

  final int sortOrder;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ImportedDayEntry> dayEntries;
  final List<ImportedObservation> observations;
}

/// A fully parsed, structurally and boundedly valid export document
/// (Issue #140). Never carries a row a genuine export from this app
/// couldn't have produced — see this file's own doc comment.
class AccountImportDocument {
  const AccountImportDocument({
    required this.schemaVersion,
    this.exportedAt,
    this.appName,
    this.appVersion,
    this.profiles = const [],
  });

  final int schemaVersion;
  final DateTime? exportedAt;
  final String? appName;
  final String? appVersion;
  final List<ImportedProfile> profiles;
}

/// [parseAccountImport]'s result: exactly one of [AccountImportParsed] or
/// [AccountImportParseFailed] (KTD6 sum-type idiom, mirrors
/// `lib/data/auth/auth_link_classifier.dart`'s `AuthLink`).
sealed class AccountImportParseResult {
  const AccountImportParseResult();
}

final class AccountImportParsed extends AccountImportParseResult {
  const AccountImportParsed(this.document);

  final AccountImportDocument document;
}

final class AccountImportParseFailed extends AccountImportParseResult {
  const AccountImportParseFailed(this.error);

  final AccountImportError error;
}

/// Internal-only: every structural/bounds failure while walking the parsed
/// JSON throws this, caught once at the top of [parseAccountImport] and
/// turned into an [AccountImportParseFailed] — keeps every helper below a
/// plain value-returning function instead of threading a result type
/// through each one.
class _ImportFormatException implements Exception {
  _ImportFormatException(this.message);

  final String message;
}

/// Parses and fully validates [bytes] as an account export document
/// (schema versions [kAccountImportMinSchemaVersion]-
/// [kAccountImportMaxSchemaVersion]). See this file's own doc comment for
/// what "fully validates" means and why a single bad row rejects the whole
/// file.
AccountImportParseResult parseAccountImport(List<int> bytes) {
  if (bytes.length > kMaxImportFileBytes) {
    final maxMib = kMaxImportFileBytes ~/ (1024 * 1024);
    return AccountImportParseFailed(
        AccountImportError('This file is larger than lunarlog can import '
            '($maxMib MiB max).'));
  }
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw _ImportFormatException(
          'This file is not a lunarlog export document.');
    }
    return AccountImportParsed(_parseDocument(decoded));
  } on FormatException {
    return const AccountImportParseFailed(
        AccountImportError('This file is not valid JSON.'));
  } on _ImportFormatException catch (e) {
    return AccountImportParseFailed(AccountImportError(e.message));
  }
}

AccountImportDocument _parseDocument(Map<String, Object?> json) {
  final schemaVersion = _requireSchemaVersion(json['schemaVersion']);
  final profilesJson = json['profiles'];
  if (profilesJson is! List) {
    throw _ImportFormatException('The file has no "profiles" list.');
  }
  final app = json['app'];
  final profiles = [for (final raw in profilesJson) _parseProfile(raw)];
  _rejectDuplicateIds(profiles);
  return AccountImportDocument(
    schemaVersion: schemaVersion,
    exportedAt: DateTime.tryParse('${json['exportedAt']}'),
    appName: app is Map ? app['name']?.toString() : null,
    appVersion: app is Map ? app['version']?.toString() : null,
    profiles: profiles,
  );
}

/// Rejects an id collision anywhere in the WHOLE document — profile ids,
/// day-entry ids, and observation ids must each be unique across every
/// profile, not merely within one (round-3 review, item 2). Complements
/// [_rejectDuplicateEntryDates]/[_rejectDuplicateProvenance] (which are
/// scoped per-profile and catch a different shape of malformed file: two
/// rows for the same slot, not the same id reused for two different rows).
/// A genuine export from this app can never repeat an id — ULIDs are
/// collision-free and every row is exported exactly once — so a repeated
/// id here is exactly the kind of thing this file's own doc comment says
/// to treat as tampering/corruption: reject the whole document rather than
/// silently accept whichever copy [AccountImporter] would happen to apply
/// last (each `id` also becomes `DayEntryPlan.fileId`/an observation's row
/// id — see [ImportedDayEntry.id]'s doc comment — so two rows sharing one
/// id would otherwise collide at write time in a way this function is the
/// client's only chance to catch before ever attempting a write).
void _rejectDuplicateIds(List<ImportedProfile> profiles) {
  final seenProfileIds = <String>{};
  final seenEntryIds = <String>{};
  final seenObservationIds = <String>{};
  for (final profile in profiles) {
    if (!seenProfileIds.add(profile.id)) {
      throw _ImportFormatException(
          'Duplicate profile id (${_truncateForMessage(profile.id)}).');
    }
    for (final entry in profile.dayEntries) {
      if (!seenEntryIds.add(entry.id)) {
        throw _ImportFormatException(
            'Duplicate day entry id (${_truncateForMessage(entry.id)}).');
      }
    }
    for (final observation in profile.observations) {
      if (!seenObservationIds.add(observation.id)) {
        throw _ImportFormatException(
            'Duplicate observation id '
            '(${_truncateForMessage(observation.id)}).');
      }
    }
  }
}

int _requireSchemaVersion(Object? raw) {
  if (raw is! int ||
      raw < kAccountImportMinSchemaVersion ||
      raw > kAccountImportMaxSchemaVersion) {
    throw _ImportFormatException(
      'Unsupported export schema version (this app reads '
      '$kAccountImportMinSchemaVersion-$kAccountImportMaxSchemaVersion, '
      'file has ${raw ?? 'none'}).',
    );
  }
  return raw;
}

ImportedProfile _parseProfile(Object? raw) {
  if (raw is! Map<String, Object?>) {
    throw _ImportFormatException('A profile entry is not an object.');
  }
  final id = _requireUlid(raw['id'], what: 'A profile id');
  final dayEntriesJson = raw['dayEntries'];
  final observationsJson = raw['observations'];
  final dayEntries = [
    for (final e in dayEntriesJson is List ? dayEntriesJson : const [])
      _parseDayEntry(e, profileId: id),
  ];
  final observations = [
    for (final o in observationsJson is List ? observationsJson : const [])
      _parseObservation(o, profileId: id),
  ];
  _rejectDuplicateEntryDates(dayEntries, profileId: id);
  _rejectDuplicateProvenance(dayEntries, profileId: id);
  _rejectOrphanObservations(observations, dayEntries, profileId: id);
  _rejectExcessiveObservationsPerDay(observations, profileId: id);
  return ImportedProfile(
    id: id,
    displayName: _profileDisplayName(raw['displayName']),
    isMinor: raw['isMinor'] == true,
    mode: _parseMode(raw['mode'], context: 'Profile $id'),
    sortOrder: raw['sortOrder'] is int ? raw['sortOrder'] as int : 0,
    archivedAt: DateTime.tryParse('${raw['archivedAt']}'),
    createdAt: DateTime.tryParse('${raw['createdAt']}'),
    updatedAt: DateTime.tryParse('${raw['updatedAt']}'),
    dayEntries: dayEntries,
    observations: observations,
  );
}

String _profileDisplayName(Object? raw) {
  final name = raw is String ? raw : '';
  if (name.length > kMaxDisplayNameLength) {
    throw _ImportFormatException(
        'A profile name is longer than $kMaxDisplayNameLength characters.');
  }
  return name;
}

/// Validates `mode` against [ProfileMode]'s closed set (Issue #140 review,
/// item 4) — unlike `ProfileMode.fromDb`'s own degrade-to-`standard`
/// leniency (appropriate for a row already accepted by this app or the
/// server), an untrusted import file carrying an unrecognised mode is
/// rejected outright, same treatment as every other closed-set/bounded
/// field here. Null (absent key; every schema version has always allowed
/// this) passes through unchanged — `AccountImporter._resolveProfileId`
/// falls back to `'standard'`.
String? _parseMode(Object? raw, {required String context}) {
  if (raw == null) return null;
  if (raw is! String) {
    throw _ImportFormatException('$context has an invalid mode.');
  }
  final recognised = ProfileMode.values.any((m) => m.toDb() == raw);
  if (!recognised) {
    throw _ImportFormatException('$context has an unrecognised mode ("${_truncateForMessage(raw)}").');
  }
  return raw;
}

/// Rejects a profile carrying more than one day entry for the same civil
/// date (Issue #140 review, item 9): a genuine export from this app can
/// never produce two, since day entries are unique per (profile, date) at
/// the source — so this is exactly the kind of row a genuine export could
/// never have produced (this file's own doc comment), not a case worth
/// silently reconciling. Rejecting it here — rather than letting both
/// reach [AccountImporter], where the second's `upsertDayEntry` would
/// simply overwrite the first's freshly-written row under the same
/// (profileId, localDate) key — keeps [ImportPlanSummary.entriesAdded]
/// truthful: one planned "add" per date always means one row actually
/// written.
void _rejectDuplicateEntryDates(
  List<ImportedDayEntry> entries, {
  required String profileId,
}) {
  final seen = <String>{};
  for (final e in entries) {
    if (!seen.add(e.localDate.iso)) {
      throw _ImportFormatException(
          'Profile $profileId has more than one day entry for '
          '${e.localDate.iso}.');
    }
  }
}

/// Rejects two day entries in one profile sharing a resolved (source,
/// sourceId) provenance pair (Issue #140 review round 2, item 2) — sibling
/// of [_rejectDuplicateEntryDates]. The server's partial unique index
/// `day_entries_profile_source_source_id_uq` (`supabase/migrations/
/// 20260908170000_import_provenance.sql`) is scoped to `source_id is not
/// null`, so only a pair with a non-null [ImportedDayEntry.sourceId]
/// collides here, matching that scope exactly. Left unrejected, two such
/// entries on different dates would both parse and both plan as `add`
/// (their (profileId, localDate) pair differs, so
/// [_rejectDuplicateEntryDates] doesn't catch this) — applying the second
/// would have `AccountImporter._revivalIdFor` find the first one's
/// freshly-inserted row via `LunarLogStorage.findDayEntryBySource` and
/// revive-update it onto the second entry's own date, which
/// `upsertDayEntry`'s `id:` revival path (Issue #140 review round 2, item
/// 2's other half) must now also retarget by `local_date` for — this
/// rejection means that retargeting is never actually exercised by an
/// import, only by `db_test.dart`'s own direct case.
void _rejectDuplicateProvenance(
  List<ImportedDayEntry> entries, {
  required String profileId,
}) {
  final seen = <String>{};
  for (final e in entries) {
    final sourceId = e.sourceId;
    if (sourceId == null) continue;
    final key = '${e.source}|$sourceId';
    if (!seen.add(key)) {
      throw _ImportFormatException(
          'Profile $profileId has more than one day entry with the same '
          'source and sourceId.');
    }
  }
}

/// Rejects an observation whose date has no corresponding day entry in the
/// same profile (Issue #140 review, item 9): a genuine export always
/// exports the day entry alongside every observation that belongs to it
/// (see `AccountImporter._applyObservation`'s own doc comment), so this
/// case is evidence of a crafted/corrupt file, not a state
/// [ImportPlanSummary.observationsAdded] should have to silently absorb —
/// rejecting it here keeps that count truthful instead of relying on
/// `AccountImporter`'s defensive runtime skip (kept as a last-resort
/// backstop, never expected to trigger for a document this function
/// accepted).
void _rejectOrphanObservations(
  List<ImportedObservation> observations,
  List<ImportedDayEntry> dayEntries, {
  required String profileId,
}) {
  final entryDates = {for (final e in dayEntries) e.localDate.iso};
  for (final o in observations) {
    if (!entryDates.contains(o.localDate.iso)) {
      throw _ImportFormatException(
          'Profile $profileId has an observation on ${o.localDate.iso} '
          'with no matching day entry.');
    }
  }
}

/// Rejects a profile carrying more than [kMaxObservationsPerDay]
/// observations on one civil date (Issue #140 review, item 4) — mirrors
/// the same per-(profile, local_date) cap `sync_push` enforces server-side
/// (`lib/domain/limits.dart`'s doc comment); a CHECK constraint can't count
/// sibling rows, so this is the client's only chance to reject such a
/// document before ever attempting to write it.
void _rejectExcessiveObservationsPerDay(
  List<ImportedObservation> observations, {
  required String profileId,
}) {
  final counts = <String, int>{};
  for (final o in observations) {
    final date = o.localDate.iso;
    final count = (counts[date] ?? 0) + 1;
    counts[date] = count;
    if (count > kMaxObservationsPerDay) {
      throw _ImportFormatException(
          'Profile $profileId has more than $kMaxObservationsPerDay '
          'observations on $date.');
    }
  }
}

ImportedDayEntry _parseDayEntry(Object? raw, {required String profileId}) {
  if (raw is! Map<String, Object?>) {
    throw _ImportFormatException(
        'A day entry for profile $profileId is not an object.');
  }
  final id = _requireUlid(raw['id'],
      what: 'A day entry for profile $profileId');
  final context = 'day entry $id';
  final localDate = _parseLocalDate(raw['localDate'], context: context);
  final note = _boundedString(raw['note'], kMaxNoteLength, context: context);
  final updatedAt = DateTime.tryParse('${raw['updatedAt']}');
  if (updatedAt == null) {
    throw _ImportFormatException('$context has an invalid updatedAt.');
  }
  final provenance = _dayEntryProvenance(raw, entryId: id, context: context);
  return ImportedDayEntry(
    id: id,
    localDate: localDate,
    tz: _parseTz(raw['tz'], context: context),
    flow: _parseFlow(raw['flow'], context: context),
    tags: _parseTags(raw['tags'], context: context),
    note: note,
    updatedAt: updatedAt,
    source: provenance.source,
    sourceId: provenance.sourceId,
    importId: provenance.importId,
  );
}

/// The raw `source`/`sourceId`/`importId` an entry will carry into planning
/// — see [ImportedDayEntry.source]'s doc comment for the preserve-vs-
/// fallback rule (Issue #140 review, item 7).
typedef _DayEntryProvenance = ({
  String source,
  String? sourceId,
  String? importId,
});

_DayEntryProvenance _dayEntryProvenance(
  Map<String, Object?> raw, {
  required String entryId,
  required String context,
}) {
  final rawSource = raw['source'];
  if (rawSource != null && rawSource is! String) {
    throw _ImportFormatException('$context has an invalid source.');
  }
  final source = DayEntrySource.fromDb(rawSource as String?);
  final sourceId = _boundedString(raw['sourceId'], kMaxDayEntrySourceIdLength,
      context: '$context sourceId');
  final importId = _uuidOrNull(raw['importId']);
  final hasFileProvenance = source != DayEntrySource.manual || sourceId != null;
  if (hasFileProvenance) {
    return (source: source.toDb(), sourceId: sourceId, importId: importId);
  }
  return (source: DayEntrySource.fileImport.toDb(), sourceId: entryId, importId: null);
}

/// `tz` ≤ [kMaxTzLength] AND a valid IANA zone (Issue #140 review, item 4) —
/// null (absent key; every schema version has always allowed this) defaults
/// to `'UTC'` without re-validating a value this codebase itself would only
/// ever have written.
String _parseTz(Object? raw, {required String context}) {
  if (raw == null) return 'UTC';
  if (raw is! String || raw.length > kMaxTzLength) {
    throw _ImportFormatException('$context has an invalid time zone.');
  }
  if (!isValidIanaTimeZone(raw)) {
    throw _ImportFormatException(
        '$context has an unrecognised time zone ("$raw").');
  }
  return raw;
}

LocalDate _parseLocalDate(Object? raw, {required String context}) {
  if (raw is! String) {
    throw _ImportFormatException('$context has no date.');
  }
  try {
    return LocalDate.fromIso(raw);
  } on ArgumentError {
    throw _ImportFormatException('$context has an invalid date ("${_truncateForMessage(raw)}").');
  }
}

List<String> _parseTags(Object? raw, {required String context}) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw _ImportFormatException('$context has an invalid tags list.');
  }
  if (raw.length > kMaxTagCount) {
    throw _ImportFormatException(
        '$context has more than $kMaxTagCount tags.');
  }
  final tags = <String>[];
  for (final tag in raw) {
    if (tag is! String || tag.length > kMaxTagLength) {
      throw _ImportFormatException('$context has an invalid tag.');
    }
    tags.add(tag);
  }
  return tags;
}

/// Looks [raw] up against [FlowLevel.values] by its `.name` (Issue #140
/// review, item 8) — the exact strings `lib/domain/export/account_export.
/// dart` writes (`entry.flow.name`) and the only ones a genuine export
/// could ever contain, `'none'` included. Unlike the pre-review switch,
/// an unrecognised value is REJECTED rather than silently degraded to
/// `none`: a genuine export can only ever contain one of these five
/// strings, so anything else is exactly the kind of row this file's own
/// doc comment says to treat as tampering/corruption, not a legitimate
/// future addition to paper over.
FlowLevel _parseFlow(Object? raw, {required String context}) {
  if (raw is! String) {
    throw _ImportFormatException('$context has an invalid flow value.');
  }
  // Accept the Dart enum name (what today's export writes) and the
  // snake_case wire/db spelling (e.g. "super_heavy" once #247 lands and the
  // export switches to the db encoding); anything else is rejected rather
  // than degraded to none.
  try {
    return FlowLevel.values.byName(_snakeToCamel(raw));
  } on ArgumentError {
    throw _ImportFormatException(
        '$context has an unrecognised flow value ("${_truncateForMessage(raw)}").');
  }
}

String _snakeToCamel(String raw) => raw.replaceAllMapped(
    RegExp(r'_([a-z])'), (m) => m.group(1)!.toUpperCase());

/// Exposes [_snakeToCamel]'s mapping for direct testing (round-3 review,
/// item 4) — `FlowLevel` has no snake_case member today (see [_parseFlow]'s
/// doc comment for why the conversion exists ahead of #247), so a test
/// exercising it only through [_parseFlow] can't observe the mapping
/// itself, only whether the result happens to land on a real enum name.
/// This is a plain conversion helper, not part of the flow-parsing
/// contract — it does not validate that the result is a recognised
/// [FlowLevel].
String flowNameFromWire(String raw) => _snakeToCamel(raw);

ImportedObservation _parseObservation(Object? raw,
    {required String profileId}) {
  if (raw is! Map<String, Object?>) {
    throw _ImportFormatException(
        'An observation for profile $profileId is not an object.');
  }
  final id = _requireUlid(raw['id'],
      what: 'An observation for profile $profileId');
  final context = 'observation $id';
  final category = raw['category'];
  if (category is! String ||
      category.isEmpty ||
      category.length > kMaxObservationCategoryLength) {
    throw _ImportFormatException('$context has an invalid category.');
  }
  final intensity = _parseIntensity(raw['intensity'], context: context);
  return ImportedObservation(
    id: id,
    localDate: _parseLocalDate(raw['localDate'], context: context),
    observedAt: DateTime.tryParse('${raw['observedAt']}'),
    tz: _parseTz(raw['tz'], context: context),
    category: category,
    code: _boundedString(raw['code'], kMaxObservationCodeLength,
        context: '$context code'),
    valueNum: raw['valueNum'] is num ? (raw['valueNum'] as num).toDouble() : null,
    valueText: _boundedString(raw['valueText'], kMaxObservationValueTextLength,
        context: '$context value'),
    unit: _boundedString(raw['unit'], kMaxObservationUnitLength,
        context: '$context unit'),
    intensity: intensity,
    excluded: raw['excluded'] == true,
    raw: _encodedRawOrNull(raw['raw']),
  );
}

int? _parseIntensity(Object? raw, {required String context}) {
  if (raw == null) return null;
  if (raw is! int ||
      raw < kMinObservationIntensity ||
      raw > kMaxObservationIntensity) {
    throw _ImportFormatException('$context has an invalid intensity.');
  }
  return raw;
}

String? _boundedString(Object? value, int max, {required String context}) {
  if (value == null) return null;
  if (value is! String || value.length > max) {
    throw _ImportFormatException('$context is invalid.');
  }
  return value;
}

/// [value] when it is a syntactically valid UUID string, else null — never
/// a rejection (Issue #140 review round 2, item 4): unlike an `id` (item
/// 1) or a duplicate provenance pair (item 2), a malformed `importId` is
/// dropped rather than failing the whole document, since it is
/// provenance-only bookkeeping (Issue #159), not identity — the document
/// otherwise imports normally.
String? _uuidOrNull(Object? value) {
  if (value is! String || !_validUuid.hasMatch(value)) return null;
  return value;
}

String? _encodedRawOrNull(Object? value) {
  if (value == null) return null;
  final encoded = jsonEncode(value);
  if (utf8.encode(encoded).length > kMaxObservationRawLength) {
    throw _ImportFormatException("An observation's raw payload is too large.");
  }
  return encoded;
}

/// The screen's preview step (before anything is compared against the
/// local store): a plain summary of [document] itself.
class ImportPreview {
  const ImportPreview({
    required this.profileCount,
    required this.entryCount,
    required this.observationCount,
    this.earliestDate,
    this.latestDate,
  });

  final int profileCount;
  final int entryCount;
  final int observationCount;
  final LocalDate? earliestDate;
  final LocalDate? latestDate;
}

ImportPreview previewImport(AccountImportDocument document) {
  var entryCount = 0;
  var observationCount = 0;
  LocalDate? earliest;
  LocalDate? latest;
  for (final profile in document.profiles) {
    entryCount += profile.dayEntries.length;
    observationCount += profile.observations.length;
    for (final entry in profile.dayEntries) {
      if (earliest == null || entry.localDate.isBefore(earliest)) {
        earliest = entry.localDate;
      }
      if (latest == null || entry.localDate.isAfter(latest)) {
        latest = entry.localDate;
      }
    }
  }
  return ImportPreview(
    profileCount: document.profiles.length,
    entryCount: entryCount,
    observationCount: observationCount,
    earliestDate: earliest,
    latestDate: latest,
  );
}

/// One sentence naming the merge policy, shown on the preview step. Only
/// the tags half genuinely mirrors the sync engine's own rule
/// (`lib/data/sync/conflict_rules.dart`'s `mergeTags`) — the engine itself
/// resolves a same-date collision by last-writer-wins (`sameDateWinner`:
/// one row's flow/note wins wholesale, the loser tombstoned), it never
/// merges flow or note field-by-field. Import's flow/note rule (the
/// heavier flow, the existing non-empty note) is this issue's own
/// additive policy, not something the sync engine shares (Issue #140
/// review, item 9 — the pre-review wording claimed otherwise for all
/// three fields).
const String kImportMergePolicySentence =
    'New profiles and entries are added; an entry on a date you already '
    "track unions its tags the same way sync does. Flow level and note use "
    "import's own additive rule instead — the heavier flow level and your "
    "existing note are kept, unlike sync itself, which keeps only one row's "
    'whole flow/note, whichever was edited more recently. Nothing already '
    'on this device is ever deleted or silently overwritten.';

/// Why a *matched* existing profile cannot receive imported rows: archived
/// (Issue #140 design constraints), or the importing session holds a
/// `viewer`-role guardian membership on it (`GuardianRole.canLog`) —
/// importing into a shared profile pushes rows to every other guardian's
/// device, so the same write gate the day sheet already enforces
/// (`GuardianRole.readOnlyReason`) applies here. Null means writable.
///
/// [guardians] and [currentUserId] fail open exactly like
/// [acceptedGuardianFor] itself: no guardian rows synced yet, or no
/// [currentUserId] (local-only use), reads as "not known to be read-only",
/// never as blocked.
String? writeBlockReasonFor({
  required Profile profile,
  List<ProfileGuardian> guardians = const [],
  String? currentUserId,
}) {
  if (profile.archivedAt != null) {
    return 'This profile is archived.';
  }
  final guardian = acceptedGuardianFor(guardians, currentUserId);
  if (guardian != null && !guardian.role.canLog) {
    return 'You have view-only access to this profile.';
  }
  return null;
}

/// A day entry [planImport] decided to write, and how.
enum DayEntryImportOutcome { add, merge }

/// The resolved values [AccountImporter] writes for one entry — already
/// merged when [outcome] is [DayEntryImportOutcome.merge].
class DayEntryPlan {
  const DayEntryPlan({
    required this.outcome,
    required this.localDate,
    required this.tz,
    required this.flow,
    required this.tags,
    required this.note,
    required this.source,
    required this.sourceId,
    required this.importId,
    this.noteDiscarded = false,
    this.fileId,
  });

  final DayEntryImportOutcome outcome;
  final LocalDate localDate;
  final String tz;
  final FlowLevel flow;
  final List<String> tags;
  final String? note;
  final String source;
  final String? sourceId;
  final String? importId;

  /// Whether a non-empty file note was dropped in favour of a non-empty
  /// existing note during a [DayEntryImportOutcome.merge] (Issue #140
  /// review, item 9) — [ImportPlanSummary.notesDiscarded] sums this across
  /// every profile, so the confirm/result steps can be honest about a
  /// note the import silently kept rather than applied.
  final bool noteDiscarded;

  /// The file's own `dayEntries[].id` (already validated as a ULID — see
  /// [_requireUlid]), carried through only for [DayEntryImportOutcome.add]
  /// (Issue #140 review round 2, item 3) — null for a
  /// [DayEntryImportOutcome.merge], which already targets a live row by
  /// (profileId, localDate) and must never adopt a different id.
  /// `AccountImporter._revivalIdFor` reuses this as the new row's own id
  /// (when nothing already occupies the slot it would otherwise fall back
  /// to a provenance-revival match, or a freshly generated ULID) so that
  /// two devices importing the same file converge on the same row id
  /// instead of each minting their own and later colliding — see this
  /// decision's trade-off note in `docs/import/clue-mapping.md`.
  final String? fileId;
}

/// Whether an observation is a new row or left alone because one already
/// lives at the same (profileId, localDate, category, code).
enum ObservationImportOutcome { add, skip }

class ObservationPlan {
  const ObservationPlan({required this.outcome, required this.imported});

  final ObservationImportOutcome outcome;
  final ImportedObservation imported;
}

/// What happened to one `profiles[]` entry.
enum ProfileImportOutcome { created, matched, skipped }

class ProfilePlan {
  const ProfilePlan({
    required this.fileProfileId,
    required this.displayName,
    required this.outcome,
    this.skipReason,
    this.mode,
    this.isMinor = false,
    this.sortOrder = 0,
    this.entries = const [],
    this.observations = const [],
    this.hasOtherGuardians = false,
    this.restoredFromTombstone = false,
  });

  final String fileProfileId;
  final String displayName;
  final ProfileImportOutcome outcome;
  final String? skipReason;
  final String? mode;
  final bool isMinor;
  final int sortOrder;
  final List<DayEntryPlan> entries;
  final List<ObservationPlan> observations;

  /// Whether this *matched* profile has an accepted guardian other than
  /// the importing session's own user (Issue #140 review, item 10) — false
  /// for a created profile (nothing shared yet) or when no guardian info
  /// was supplied. Drives [ImportPlan.sharesWithOtherGuardians]'s preview
  /// disclosure.
  final bool hasOtherGuardians;

  /// Whether this *matched* profile is actually a tombstoned local profile
  /// being un-deleted, not a live one (Issue #140 review round 2, item 6):
  /// the file's id matched no row in `profilesRepository.list()` (live
  /// only), but did match a soft-deleted one, so [_planProfile] treats it
  /// as `matched` instead of `created` — creating it fresh would have
  /// `AccountImporter._resolveProfileId`'s `upsertProfile` call silently
  /// revive the tombstone and overwrite its stored metadata with the
  /// file's, and skip [writeBlockReasonFor] entirely (that check only ever
  /// ran for a *matched* plan). `AccountImporter._resolveProfileId` reads
  /// this to un-delete the row (`LunarLogStorage.reviveTombstonedProfile`)
  /// while leaving its stored metadata untouched, and
  /// [ImportPlanSummary.profilesRestored] reports it distinctly from an
  /// ordinary match in the result summary.
  final bool restoredFromTombstone;
}

/// Why a profile was skipped, for the result screen's "rejected" list.
class SkippedProfileReason {
  const SkippedProfileReason({required this.displayName, required this.reason});

  final String displayName;
  final String reason;
}

/// Aggregated counts for the preview/confirm and result steps. See this
/// file's own doc comment for what each bucket means.
class ImportPlanSummary {
  const ImportPlanSummary({
    required this.profilesCreated,
    required this.profilesMatched,
    required this.entriesAdded,
    required this.entriesMerged,
    required this.observationsAdded,
    required this.observationsSkipped,
    required this.skippedProfiles,
    this.notesDiscarded = 0,
    this.profilesRestored = 0,
  });

  final int profilesCreated;
  final int profilesMatched;
  final int entriesAdded;
  final int entriesMerged;
  final int observationsAdded;
  final int observationsSkipped;
  final List<SkippedProfileReason> skippedProfiles;

  /// Merged entries where a non-empty file note was dropped because the
  /// existing row already had one (Issue #140 review, item 9) — report
  /// honesty: [entriesMerged] alone doesn't say whether the file's own
  /// note actually made it onto the device.
  final int notesDiscarded;

  /// How many of [profilesMatched] were actually a tombstoned local
  /// profile un-deleted, not a live one matched by id (Issue #140 review
  /// round 2, item 6) — see [ProfilePlan.restoredFromTombstone].
  final int profilesRestored;

  int get profilesSkipped => skippedProfiles.length;

  factory ImportPlanSummary.from(List<ProfilePlan> profiles) {
    final counts = _profileOutcomeCounts(profiles);
    final entryCounts = _entryOutcomeCounts(profiles);
    final observationCounts = _observationOutcomeCounts(profiles);
    return ImportPlanSummary(
      profilesCreated: counts.created,
      profilesMatched: counts.matched,
      entriesAdded: entryCounts.added,
      entriesMerged: entryCounts.merged,
      observationsAdded: observationCounts.added,
      observationsSkipped: observationCounts.skipped,
      notesDiscarded: entryCounts.notesDiscarded,
      profilesRestored: counts.restored,
      skippedProfiles: [
        for (final p in profiles)
          if (p.outcome == ProfileImportOutcome.skipped)
            SkippedProfileReason(
              displayName: p.displayName,
              reason: p.skipReason ?? 'This profile cannot be written to.',
            ),
      ],
    );
  }
}

typedef _ProfileCounts = ({int created, int matched, int restored});

_ProfileCounts _profileOutcomeCounts(List<ProfilePlan> profiles) {
  var created = 0;
  var matched = 0;
  var restored = 0;
  for (final p in profiles) {
    if (p.outcome == ProfileImportOutcome.created) created++;
    if (p.outcome == ProfileImportOutcome.matched) {
      matched++;
      if (p.restoredFromTombstone) restored++;
    }
  }
  return (created: created, matched: matched, restored: restored);
}

typedef _EntryCounts = ({int added, int merged, int notesDiscarded});

_EntryCounts _entryOutcomeCounts(List<ProfilePlan> profiles) {
  var added = 0;
  var merged = 0;
  var notesDiscarded = 0;
  for (final p in profiles) {
    for (final e in p.entries) {
      if (e.outcome == DayEntryImportOutcome.add) {
        added++;
      } else {
        merged++;
        if (e.noteDiscarded) notesDiscarded++;
      }
    }
  }
  return (added: added, merged: merged, notesDiscarded: notesDiscarded);
}

typedef _ObservationCounts = ({int added, int skipped});

_ObservationCounts _observationOutcomeCounts(List<ProfilePlan> profiles) {
  var added = 0;
  var skipped = 0;
  for (final p in profiles) {
    for (final o in p.observations) {
      if (o.outcome == ObservationImportOutcome.add) {
        added++;
      } else {
        skipped++;
      }
    }
  }
  return (added: added, skipped: skipped);
}

/// The full merge/create/skip decision for every profile, entry, and
/// observation in a document — never itself a write. See this file's own
/// doc comment for the merge policy and [AccountImporter] (in
/// `lib/data/import/account_importer.dart`) for how it is applied.
class ImportPlan {
  const ImportPlan({required this.profiles});

  final List<ProfilePlan> profiles;

  ImportPlanSummary get summary => ImportPlanSummary.from(profiles);

  /// Whether any *matched* target profile has an accepted guardian other
  /// than the importing session's own user (Issue #140 review, item 10) —
  /// drives the preview step's "this pushes rows to every guardian"
  /// disclosure sentence.
  bool get sharesWithOtherGuardians => profiles.any(
      (p) => p.outcome == ProfileImportOutcome.matched && p.hasOtherGuardians);
}

/// The same union rule `lib/data/sync/conflict_rules.dart`'s `mergeTags`
/// applies to a same-date sync collision — this issue's merge policy
/// names that rule explicitly ("the same union rule the sync engine
/// uses"), duplicated in miniature here rather than imported, since
/// `lib/domain` never depends on `lib/data` (R14/R16,
/// `test/architecture/layering_test.dart`). Capped at [kMaxTagCount],
/// matching `day_entries_tags_check`.
List<String> _mergeTags(List<String> a, List<String> b) {
  final merged = {...a, ...b}.toList()..sort();
  return merged.length > kMaxTagCount ? merged.sublist(0, kMaxTagCount) : merged;
}

FlowLevel _higherFlow(FlowLevel a, FlowLevel b) =>
    FlowLevel.values.indexOf(a) >= FlowLevel.values.indexOf(b) ? a : b;

String? _mergedNote(String? existingNote, String? importedNote) =>
    (existingNote == null || existingNote.isEmpty) ? importedNote : existingNote;

bool _noteDiscarded(String? existingNote, String? importedNote) =>
    existingNote != null &&
    existingNote.isNotEmpty &&
    importedNote != null &&
    importedNote.isNotEmpty;

DayEntryPlan _planDayEntry(ImportedDayEntry imported, DayEntry? existing) {
  if (existing == null) {
    // Preserves the file's own v4 provenance when present (Issue #140
    // review, item 7) — see [ImportedDayEntry.source]'s doc comment; the
    // resolution already happened at parse time, so this just forwards it.
    return DayEntryPlan(
      outcome: DayEntryImportOutcome.add,
      localDate: imported.localDate,
      tz: imported.tz,
      flow: imported.flow,
      tags: imported.tags,
      note: imported.note,
      source: imported.source,
      sourceId: imported.sourceId,
      importId: imported.importId,
      fileId: imported.id,
    );
  }
  return DayEntryPlan(
    outcome: DayEntryImportOutcome.merge,
    localDate: imported.localDate,
    tz: existing.tz,
    flow: _higherFlow(existing.flow, imported.flow),
    tags: _mergeTags(existing.tags, imported.tags),
    note: _mergedNote(existing.note, imported.note),
    source: existing.source.toDb(),
    sourceId: existing.sourceId,
    importId: existing.importId,
    noteDiscarded: _noteDiscarded(existing.note, imported.note),
  );
}

List<DayEntryPlan> _planEntries(
  List<ImportedDayEntry> imported,
  List<DayEntry> existing,
) {
  final byDate = {for (final e in existing) e.localDate.iso: e};
  return [for (final e in imported) _planDayEntry(e, byDate[e.localDate.iso])];
}

String _observationKey(String date, String category, String? code) =>
    '$date|$category|${code ?? ''}';

List<ObservationPlan> _planObservations(
  List<ImportedObservation> imported,
  List<Observation> existing,
) {
  final existingKeys = {
    for (final o in existing) _observationKey(o.localDate.iso, o.category, o.code),
  };
  return [
    for (final o in imported)
      ObservationPlan(
        outcome: existingKeys.contains(_observationKey(o.localDate.iso, o.category, o.code))
            ? ObservationImportOutcome.skip
            : ObservationImportOutcome.add,
        imported: o,
      ),
  ];
}

ProfilePlan _planProfile(
  ImportedProfile imported,
  Profile? existing,
  Profile? tombstoned,
  List<DayEntry> existingEntries,
  List<Observation> existingObservations,
  String? Function(Profile existingProfile) writeBlockReason,
  bool Function(Profile existingProfile) hasOtherGuardians,
) {
  // Issue #140 review round 2, item 6: a tombstoned local profile at this
  // id is treated exactly like a live match — run the write-block check
  // against its own stored state, entries/observations merge against
  // whatever it still has attached — except the outcome is flagged so
  // `AccountImporter` un-deletes it instead of expecting a live row
  // already there, and the summary reports it as "restored". Checked
  // before the `existing == null` create path below, since a tombstoned
  // profile is by definition absent from `existingProfiles`
  // (`ProfilesRepository.list()` never returns one).
  final target = existing ?? tombstoned;
  if (target == null) {
    return ProfilePlan(
      fileProfileId: imported.id,
      displayName: imported.displayName,
      outcome: ProfileImportOutcome.created,
      mode: imported.mode,
      isMinor: imported.isMinor,
      sortOrder: imported.sortOrder,
      entries: _planEntries(imported.dayEntries, const []),
      observations: _planObservations(imported.observations, const []),
    );
  }
  final blockReason = writeBlockReason(target);
  if (blockReason != null) {
    return ProfilePlan(
      fileProfileId: imported.id,
      // A tombstoned profile's own stored `displayName` was already
      // cleared to '' by `softDeleteProfile` (KTD5: tombstones carry no
      // payload) — the file's own name is the only useful one to show in
      // a "this profile is blocked" message.
      displayName: existing?.displayName ?? imported.displayName,
      outcome: ProfileImportOutcome.skipped,
      skipReason: blockReason,
    );
  }
  return ProfilePlan(
    fileProfileId: imported.id,
    displayName: existing?.displayName ?? imported.displayName,
    outcome: ProfileImportOutcome.matched,
    entries: _planEntries(imported.dayEntries, existingEntries),
    observations: _planObservations(imported.observations, existingObservations),
    hasOtherGuardians: hasOtherGuardians(target),
    restoredFromTombstone: existing == null,
  );
}

/// Builds the full plan for [document] against the local store's current
/// state. Pure: [existingProfiles]/[existingEntriesByProfileId]/
/// [existingObservationsByProfileId] are snapshots the caller already
/// read; this never touches storage itself.
///
/// [existingEntriesByProfileId]/[existingObservationsByProfileId] need
/// only carry entries for a *matched* profile id (one appearing in both
/// [document] and [existingProfiles]) — a caller that only fetched those
/// (rather than every profile's full history) still gets a correct plan,
/// since a newly created profile has nothing to merge against by
/// definition.
///
/// [writeBlockReason] decides whether a *matched* existing profile may
/// receive imported rows (see [writeBlockReasonFor]); never called for a
/// profile this document is about to create.
///
/// [hasOtherGuardians] feeds [ImportPlan.sharesWithOtherGuardians]'s preview
/// disclosure (Issue #140 review, item 10) — like [writeBlockReason], only
/// called for a *matched* existing profile; defaults to "no info", i.e.
/// never shared.
///
/// [tombstonedProfilesById] (Issue #140 review round 2, item 6) carries a
/// file profile id -> its still-stored, soft-deleted local [Profile], for
/// an id [existingProfiles] doesn't hold (a live match always wins — see
/// [_planProfile]'s own doc comment for why this is checked at all).
/// Needed only for a document id absent from [existingProfiles]; a caller
/// that never soft-deletes profiles, or hasn't looked, can leave this
/// empty and every such profile plans as an ordinary create.
ImportPlan planImport({
  required AccountImportDocument document,
  required List<Profile> existingProfiles,
  Map<String, Profile> tombstonedProfilesById = const {},
  Map<String, List<DayEntry>> existingEntriesByProfileId = const {},
  Map<String, List<Observation>> existingObservationsByProfileId = const {},
  required String? Function(Profile existingProfile) writeBlockReason,
  bool Function(Profile existingProfile) hasOtherGuardians = _noOtherGuardians,
}) {
  final existingById = {for (final p in existingProfiles) p.id: p};
  return ImportPlan(profiles: [
    for (final imported in document.profiles)
      _planProfile(
        imported,
        existingById[imported.id],
        tombstonedProfilesById[imported.id],
        existingEntriesByProfileId[imported.id] ?? const [],
        existingObservationsByProfileId[imported.id] ?? const [],
        writeBlockReason,
        hasOtherGuardians,
      ),
  ]);
}

bool _noOtherGuardians(Profile existingProfile) => false;
