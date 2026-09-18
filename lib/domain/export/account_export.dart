/// Account export builder (Issue #17, Unit U5; KTD5, KTD6). Pure Dart: no
/// Flutter, no Supabase, no `dart:io` - the only untestable part of export
/// is the temp-file write and share-sheet hand-off in
/// `lib/data/export/account_export_writer.dart`.
///
/// The local encrypted Drift store is the app's source of truth (KTD5), so
/// this reads exactly what [ProfilesRepository.list] and
/// [DayEntriesRepository.listForProfile] already return: archived profiles
/// included, tombstoned rows excluded by those repositories themselves
/// (see their own docs) - export never has to reason about `deletedAt`.
///
/// Deliberately excluded from the document (R9): sync bookkeeping
/// (`server_version`, `user_id`), guardian attribution ids
/// (`logged_by_user_id`, `last_modified_by_user_id`), and anything else not
/// already modelled as a plain field on [Profile]/[DayEntry] - this is the
/// family's data, not the sync protocol's.
///
/// Issue #248 adds the server-side half: [buildMergedAccountExport] wraps
/// [buildAccountExport]'s local-only document with whatever
/// `public.export_account_data()` returns (guardian memberships,
/// invitations, ownership-transfer history, notification preferences,
/// registered devices, missed-entry alert state, feedback tickets,
/// reminder windows, and (Issue #292) the caller's `public.settings`
/// key/value rows - none of which the local Drift store holds, since
/// `public.settings` has no local mirror at all today (issue #101: it is
/// provisioned but not yet written by the app)), merged under a `server`
/// key by [mergeAccountExport] without altering this file's own
/// `profiles`/`dayEntries` shape at all - a right-of-access field this
/// file's own build functions never need their own code path for: once
/// `export_account_data()` carries `settings`, the merge already nests it
/// in without a schema-version bump (this document's `schemaVersion`
/// versions the local `profiles[]`/`dayEntries[]` shape, not the
/// opaque merged server document). The sign-in gate on
/// "Export my data" itself is unchanged by this issue (that ungating is
/// #222) - only the *local* half of export is meant to ever run signed
/// out, and [buildMergedAccountExport] already treats a null
/// [AccountExportRemoteSource] (or one that resolves to `null`) as
/// "nothing to merge", so it degrades correctly either way.
library;

import 'dart:convert';

import '../logging/custom_tag_registry.dart';
import '../logging/day_entry_merge_event.dart';
import '../models/care_note.dart';
import '../models/cycle_override.dart';
import '../models/day_entry.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import '../logging/tracking_preferences.dart';
import '../models/visit_prep_item.dart';
import '../repositories/profile_modes_repository.dart' show ProfileLifecycleMode;
import 'account_export_remote_source.dart';

/// Bumped whenever the exported document's shape changes in a way a reader
/// (a future importer, or a person opening the file) must know about.
/// v2 adds `profiles[].mode` (Issue #131). v3 adds
/// `profiles[].observations` (Issue #240): a real per-profile read wired
/// through `ObservationsRepository`/`DriftObservationsRepository`,
/// `lib/data/export/account_export_writer.dart`, and its UI callers
/// (`lib/ui/account/export_account_collaborator.dart`,
/// `lib/ui/settings/your_data_section.dart`) — a reader of an old (v2)
/// export still knows the absence of the key means "not yet collected,"
/// not "this profile has none." v4 adds `dayEntries[].source`/`sourceId`/
/// `importId` and `observations[].importId` (Issue #159): provenance is not
/// sync bookkeeping or guardian attribution (the R9 exclusions this file's
/// doc comment names above) — it is user-relevant data about where an
/// entry came from ("Imported from Clue"), so unlike those it belongs in
/// the export. v5 adds two new `dayEntries[].flow` wire values,
/// `super_heavy` and `not_bleeding` (Issue #247): a reader written against
/// v4 that treats an unrecognised flow string as a hard error must be
/// updated before it can read a v5 file; `account_import.dart`'s
/// `_parseFlow` already accepts both via `flowNameFromWire`. v6 adds
/// `profiles[].careNotes` and `profiles[].visitPrepItems` (Issue #128): a
/// reader of an old (v5) export still knows the absence of the key means
/// "not yet collected," not "this profile has none" (the v3 precedent).
/// v7 adds `dayEntries[].pms` (Issue #220): the first-class PMS marker. A
/// reader of an old (v6) export treats the key's absence as "false" (the
/// marker simply did not exist yet), the same default the importer uses.
/// v8 adds `profiles[].bbtUnit` and `profiles[].weightUnit` (Issue #255):
/// the per-profile display-unit preferences for numeric measurements. A
/// reader of an old (v7) export treats an absent key as the metric default
/// (`celsius`/`kg`), the same defaults the importer applies. v9 (Issue #140
/// review, LLA-084 — "backup omits persistent health and prediction
/// state") adds five plain profile-subject/onboarding fields
/// (`birthYear`, `relationship`, `lastPeriodStart`,
/// `typicalCycleLengthDays`, `typicalPeriodLengthDays` — already synced
/// profile columns this export simply never read before), `profileMode`
/// (the #188 life-stage mode plus birth-control method/dates; `null` when
/// no `profile_modes` row was ever written), and `cycleOverrides` (every
/// live manual cycle correction). Deliberately excluded, matching this
/// file's own R9 device-credential/consent boundary: `profileMode.healthSyncConsent`
/// — a device-specific, safety-sensitive permission a JSON file must never
/// silently transfer onto a different device or account. A reader of an
/// old (v8) export treats every new key's absence the same way the v3/v6
/// precedent already established: "not yet collected," not "this profile
/// has none of this." v10 (Issue #648, mirroring #255's same-day
/// precedent for a synced profile preference column) adds
/// `profiles[].trackingPreferences` (Issue #259's per-profile "which
/// tracking categories the day sheet surfaces" document) — omitted from
/// v9 on the mistaken premise that it belonged with the R9
/// device-credential exclusions above; it is ordinary synced profile
/// metadata like `bbtUnit`/`weightUnit`, not a device-specific consent.
/// `null` means never customized (the [TrackingPreferences] lazy-default
/// contract — see its own doc comment), the same "absent means not yet
/// collected/customized" reading the v3/v6/v8 precedents already
/// established. A reader of an old (v9) export treats the key's absence
/// identically.
/// v11 (Issue #130) adds `profiles[].mergeEvents`: the profile's
/// window-live same-date merge disclosures (one row per discarded
/// `flow`/`note` value, carrying the losing value's retained text). Only
/// events still inside the 30-day recovery window are exported — the file
/// must not extend the retention the app itself enforces — and a reader
/// of an old (v10) export treats the key's absence as "not yet
/// collected," the same v3/v6 precedent. The importer (#140) deliberately
/// does NOT restore them: they are machine-written records of merges that
/// already happened, not user data a restore needs to replay as fresh
/// notices (`account_import.dart` reads known keys only, so a v11 file
/// round-trips through import with the key harmlessly ignored).
/// v12 (Issue #824) adds `profiles[].customTags`: the profile's live
/// custom-tag registry entries (one entry per user-defined tag vocabulary,
/// carrying code, displayName, category, intensityEnabled, hiddenAt,
/// sortOrder, createdAt, updatedAt). Attribution ids (`created_by`) stay out
/// per this file's R9 rule, and tombstoned rows are excluded. A reader of
/// an old (v11) export treats the key's absence as "not yet collected,"
/// the same v3/v6/v11 precedent.
const int kAccountExportSchemaVersion = 12;

/// The app doesn't read this from a plugin (KTD6: `lib/domain` stays pure
/// Dart and untestable platform calls stay out of the builder) - it is a
/// plain literal the writer passes in, kept in step with `pubspec.yaml`'s
/// `version:` by hand.
const String kAccountExportAppName = 'lunarlog';

/// Builds the exported document: [schemaVersion], [exportedAt] (always
/// normalized to UTC), [app] (name + version, both passed in - see
/// [kAccountExportAppName]), and [profiles] with each profile's own
/// [dayEntries] nested under it.
///
/// Deterministic (profiles sorted by id, entries by [DayEntry.localDate]):
/// two calls with the same input, `jsonEncode`d, produce byte-identical
/// output.
Map<String, Object?> buildAccountExport({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  Map<String, List<Observation>> observationsByProfile = const {},
  Map<String, List<CareNote>> careNotesByProfile = const {},
  Map<String, List<VisitPrepItem>> visitPrepByProfile = const {},
  // Issue #140 review, LLA-084 (kAccountExportSchemaVersion v9).
  Map<String, ProfileLifecycleMode?> profileModesByProfile = const {},
  Map<String, List<CycleOverride>> cycleOverridesByProfile = const {},
  // Issue #130 (kAccountExportSchemaVersion v11).
  Map<String, List<DayEntryMergeEvent>> mergeEventsByProfile = const {},
  // Issue #824 (kAccountExportSchemaVersion v12).
  Map<String, List<CustomTag>> customTagsByProfile = const {},
  required DateTime exportedAt,
  String appName = kAccountExportAppName,
  required String appVersion,
}) {
  final sortedProfiles = [...profiles]..sort((a, b) => a.id.compareTo(b.id));
  return {
    'schemaVersion': kAccountExportSchemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'app': {'name': appName, 'version': appVersion},
    'profiles': [
      for (final profile in sortedProfiles)
        _exportProfile(
          profile,
          entriesByProfile[profile.id] ?? const [],
          observationsByProfile[profile.id] ?? const [],
          careNotesByProfile[profile.id] ?? const [],
          visitPrepByProfile[profile.id] ?? const [],
          profileModesByProfile[profile.id],
          cycleOverridesByProfile[profile.id] ?? const [],
          mergeEventsByProfile[profile.id] ?? const [],
          customTagsByProfile[profile.id] ?? const [],
        ),
    ],
  };
}

Map<String, Object?> _exportProfile(
  Profile profile,
  List<DayEntry> entries,
  List<Observation> observations,
  List<CareNote> careNotes,
  List<VisitPrepItem> prepItems,
  ProfileLifecycleMode? profileMode,
  List<CycleOverride> cycleOverrides,
  List<DayEntryMergeEvent> mergeEvents,
  List<CustomTag> customTags,
) {
  final sortedEntries = [...entries]
    ..sort((a, b) => a.localDate.compareTo(b.localDate));
  final sortedObservations = [...observations]
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedCareNotes = [...careNotes]
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedPrepItems = [...prepItems]
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedCycleOverrides = [...cycleOverrides]
    ..sort((a, b) => a.cycleStartDate.compareTo(b.cycleStartDate));
  final sortedMergeEvents = [...mergeEvents]
    ..sort((a, b) => a.id.compareTo(b.id));
  final sortedCustomTags = [...customTags]
    ..sort((a, b) => a.id.compareTo(b.id));
  return {
    'id': profile.id,
    'displayName': profile.displayName,
    'isMinor': profile.isMinor,
    'mode': profile.mode.toDb(),
    // Issue #255 (kAccountExportSchemaVersion v8): display-unit
    // preferences -- rendering choices, not data transformations; the
    // profile's observations each still carry their own `unit`.
    'bbtUnit': profile.bbtUnit.toDb(),
    'weightUnit': profile.weightUnit.toDb(),
    'sortOrder': profile.sortOrder,
    'archivedAt': profile.archivedAt?.toUtc().toIso8601String(),
    'createdAt': profile.createdAt.toUtc().toIso8601String(),
    'updatedAt': profile.updatedAt.toUtc().toIso8601String(),
    'dayEntries': [for (final entry in sortedEntries) _exportDayEntry(entry)],
    // Issue #140 review, LLA-084 (kAccountExportSchemaVersion v9): profile
    // subject metadata and onboarding-collected cycle facts — already
    // synced `profiles` columns (see `domain.Profile`'s own doc comments)
    // this export simply never read before.
    'birthYear': profile.birthYear,
    'relationship': profile.relationship?.toDb(),
    'lastPeriodStart': profile.lastPeriodStart?.iso,
    'typicalCycleLengthDays': profile.typicalCycleLengthDays,
    'typicalPeriodLengthDays': profile.typicalPeriodLengthDays,
    // Issue #140 review, LLA-084 (kAccountExportSchemaVersion v9): the #188
    // life-stage mode plus birth-control state — null when no
    // `profile_modes` row was ever written (the lazy-default contract;
    // `_exportProfileMode`'s doc comment covers the deliberate
    // health_sync_consent exclusion).
    'profileMode': _exportProfileMode(profileMode),
    // Issue #648 (kAccountExportSchemaVersion v10): the #259 per-profile
    // tracking-preferences document — decoded, matching `observations[].raw`'s
    // treatment (the wire/storage form is JSON text; export wants the
    // decoded object, not a doubly-encoded string). `null` means never
    // customized (see this file's v10 doc comment above).
    'trackingPreferences': _exportTrackingPreferences(profile.trackingPreferences),
    'cycleOverrides': [
      for (final override in sortedCycleOverrides) _exportCycleOverride(override),
    ],
    // Issue #240; see this file's `kAccountExportSchemaVersion` v3 doc
    // comment — this is a real per-profile read, not a placeholder.
    'observations': [
      for (final observation in sortedObservations) _exportObservation(observation),
    ],
    // Issue #128 (kAccountExportSchemaVersion v6): the profile's standing
    // care notes and visit-prep checklist — the clinician-facing half of
    // export carries the prep list. Guardian attribution ids
    // (`logged_by`/`last_modified_by`, and `checked_by` — an auth
    // identifier, not family data) stay out per this file's R9 rule above.
    'careNotes': [
      for (final note in sortedCareNotes) _exportCareNote(note),
    ],
    'visitPrepItems': [
      for (final item in sortedPrepItems) _exportVisitPrepItem(item),
    ],
    // Issue #130 (kAccountExportSchemaVersion v11): the profile's
    // window-live same-date merge disclosures. Attribution ids stay out
    // per this file's R9 rule (see careNotes above); the losing value's
    // retained text is exported because it is the user's own discarded
    // writing, exactly the text the in-app notice recovers.
    'mergeEvents': [
      for (final event in sortedMergeEvents) _exportMergeEvent(event),
    ],
    // Issue #824 (kAccountExportSchemaVersion v12): the profile's live
    // custom-tag registry entries. Attribution ids (`created_by`) stay out
    // per R9; tombstoned rows are excluded.
    'customTags': [
      for (final tag in sortedCustomTags) _exportCustomTag(tag),
    ],
  };
}

/// Issue #824 (kAccountExportSchemaVersion v12): one custom tag registry entry.
/// Attribution id (`created_by`) stays out per R9; tombstoned rows excluded.
Map<String, Object?> _exportCustomTag(CustomTag tag) => {
      'id': tag.id,
      'code': tag.code,
      'displayName': tag.displayName,
      'category': tag.category,
      'intensityEnabled': tag.intensityEnabled,
      'hiddenAt': tag.hiddenAt?.toUtc().toIso8601String(),
      'sortOrder': tag.sortOrder,
      'createdAt': tag.createdAt.toUtc().toIso8601String(),
      'updatedAt': tag.updatedAt.toUtc().toIso8601String(),
    };

/// Issue #130 (kAccountExportSchemaVersion v11): one recorded same-date
/// merge discard. `field` is the wire string (`flow`/`note`); attribution
/// ids stay out per R9. [DayEntryMergeEvent.createdAt] is exported as
/// `recordedAt` — the instant the merge was recorded, which drives the
/// 30-day recovery window.
Map<String, Object?> _exportMergeEvent(DayEntryMergeEvent event) => {
      'id': event.id,
      'localDate': event.localDateIso,
      'winningRowId': event.winningRowId,
      'losingRowId': event.losingRowId,
      'field': event.field.toDb(),
      'losingValueText': event.losingValueText,
      'recordedAt': event.createdAt.toUtc().toIso8601String(),
      'updatedAt': event.updatedAt.toUtc().toIso8601String(),
    };

/// `null` when no `profile_modes` row was ever written for the profile
/// (the lazy-default contract — see `ProfileLifecycleMode`'s own doc
/// comment), otherwise the life-stage mode plus birth-control state.
/// `healthSyncConsent` is deliberately never exported (Issue #140 review,
/// LLA-084) — matching this file's own R9 boundary
/// ("device credentials/consent excluded intentionally"), a device's
/// consent to bind a specific health platform is not a fact a JSON file
/// should ever be able to silently carry onto a different device or
/// account.
Map<String, Object?>? _exportProfileMode(ProfileLifecycleMode? mode) {
  if (mode == null) return null;
  return {
    'mode': mode.mode.toDb(),
    // Issue #192: full fidelity for restore — the mode's start date and
    // the pregnancy due date ride the export alongside the mode itself.
    'modeStartedOn': mode.modeStartedOn,
    'estimatedDueDate': mode.estimatedDueDate,
    'birthControlMethod': mode.birthControlMethod,
    'birthControlStartedOn': mode.birthControlStartedOn,
    'birthControlStoppedOn': mode.birthControlStoppedOn,
  };
}

/// `null` when the profile's tracking-preferences document was never
/// customized (Issue #648) — the same lazy-default contract
/// [TrackingPreferences] itself documents. Keeps the inner shape
/// (`{category: {enabled, sort_order}}`, `sort_order` stays snake_case)
/// identical to the sync wire's own decoded form — `account_import.dart`'s
/// reader reconstructs a [TrackingPreferences] straight from this object
/// via [TrackingPreferences.fromJsonText] (re-encoded), the same tolerant
/// parse the sync engine already gives a malformed entry.
Map<String, Object?>? _exportTrackingPreferences(TrackingPreferences? prefs) {
  if (prefs == null) return null;
  return {
    for (final entry in prefs.entries.entries)
      entry.key: {
        'enabled': entry.value.enabled,
        'sort_order': entry.value.sortOrder,
      },
  };
}

/// One live manual cycle correction (Issue #140 review, LLA-084) — full
/// fidelity, so a restore can recreate it exactly, not just its
/// excluded-from-average flag.
Map<String, Object?> _exportCycleOverride(CycleOverride override) => {
      'id': override.id,
      'cycleStartDate': override.cycleStartDate,
      'excludedFromAverage': override.excludedFromAverage,
      'manualStart': override.manualStart,
      'noteId': override.noteId,
      'updatedAt': override.updatedAt?.toUtc().toIso8601String(),
    };

Map<String, Object?> _exportDayEntry(DayEntry entry) => {
      'id': entry.id,
      'localDate': entry.localDate.iso,
      'tz': entry.tz,
      // Issue #247: the wire string, matching `source`'s toDb() below --
      // `superHeavy`/`notBleeding` are no longer the same as the enum's
      // Dart name (`super_heavy`/`not_bleeding`).
      'flow': entry.flow.toDb(),
      'tags': entry.tags,
      'note': entry.note,
      // Issue #220 (kAccountExportSchemaVersion v7).
      'pms': entry.pms,
      // Issue #159 (kAccountExportSchemaVersion v4).
      'source': entry.source.toDb(),
      'sourceId': entry.sourceId,
      'importId': entry.importId,
      'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
    };

/// Merges [serverDocument] (an already-decoded `export_account_data()`
/// document) into [localDocument] under a `server` key (Issue #248),
/// without altering [localDocument]'s own keys or shape - the future
/// importer (#140) round-trips the local `profiles`/`dayEntries` section
/// exactly as it does today.
///
/// [serverDocument] is `null` when the server step never ran or produced
/// nothing usable (signed out, offline, unconfigured build - see
/// [AccountExportRemoteSource]): the document then carries
/// `serverIncluded: false` and no `server` key at all, so a reader (a
/// person, or the importer) can tell "the server step never ran" apart
/// from "it ran and the account genuinely has no server-side data".
Map<String, Object?> mergeAccountExport({
  required Map<String, Object?> localDocument,
  required Map<String, Object?>? serverDocument,
}) {
  if (serverDocument == null) {
    return {
      ...localDocument,
      'serverIncluded': false,
    };
  }
  return {
    ...localDocument,
    'serverIncluded': true,
    'server': serverDocument,
  };
}

/// Builds the full export document (Issue #248): [buildAccountExport]'s
/// local-only document, merged with the server's own export via
/// [remoteSource] when one is supplied.
///
/// [remoteSource] is `null` for an unconfigured build (no Supabase client
/// - see `AccountExportWriter`) or a signed-out/offline session; either
/// way this never turns export into a hard failure -
/// [AccountExportRemoteSource.fetchServerExport] itself resolves to `null`
/// on any failure (no session, network, server error), and this function
/// treats that identically to "no remote source at all" via
/// [mergeAccountExport].
Future<Map<String, Object?>> buildMergedAccountExport({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  Map<String, List<Observation>> observationsByProfile = const {},
  Map<String, List<CareNote>> careNotesByProfile = const {},
  Map<String, List<VisitPrepItem>> visitPrepByProfile = const {},
  // Issue #140 review, LLA-084 (kAccountExportSchemaVersion v9).
  Map<String, ProfileLifecycleMode?> profileModesByProfile = const {},
  Map<String, List<CycleOverride>> cycleOverridesByProfile = const {},
  // Issue #130 (kAccountExportSchemaVersion v11).
  Map<String, List<DayEntryMergeEvent>> mergeEventsByProfile = const {},
  // Issue #824 (kAccountExportSchemaVersion v12).
  Map<String, List<CustomTag>> customTagsByProfile = const {},
  required DateTime exportedAt,
  String appName = kAccountExportAppName,
  required String appVersion,
  AccountExportRemoteSource? remoteSource,
}) async {
  final localDocument = buildAccountExport(
    profiles: profiles,
    entriesByProfile: entriesByProfile,
    observationsByProfile: observationsByProfile,
    careNotesByProfile: careNotesByProfile,
    visitPrepByProfile: visitPrepByProfile,
    profileModesByProfile: profileModesByProfile,
    cycleOverridesByProfile: cycleOverridesByProfile,
    mergeEventsByProfile: mergeEventsByProfile,
    customTagsByProfile: customTagsByProfile,
    exportedAt: exportedAt,
    appName: appName,
    appVersion: appVersion,
  );
  final serverDocument = await remoteSource?.fetchServerExport();
  return mergeAccountExport(
    localDocument: localDocument,
    serverDocument: serverDocument,
  );
}
Map<String, Object?> _exportObservation(Observation o) => {
      'id': o.id,
      'dayEntryId': o.dayEntryId,
      'localDate': o.localDate.iso,
      'observedAt': o.observedAt?.toUtc().toIso8601String(),
      'tz': o.tz,
      'category': o.category,
      'code': o.code,
      'valueNum': o.valueNum,
      'valueText': o.valueText,
      'unit': o.unit,
      'intensity': o.intensity,
      'excluded': o.excluded,
      'source': o.source.toDb(),
      'sourceId': o.sourceId,
      // Issue #159 (kAccountExportSchemaVersion v4).
      'importId': o.importId,
      'raw': o.raw == null ? null : jsonDecode(o.raw!),
      'updatedAt': o.updatedAt.toUtc().toIso8601String(),
    };

/// Issue #128 (kAccountExportSchemaVersion v6): one standing care note.
/// Attribution ids stay out per this file's R9 rule (see [_exportProfile]).
Map<String, Object?> _exportCareNote(CareNote note) => {
      'id': note.id,
      'body': note.body,
      'updatedAt': note.updatedAt.toUtc().toIso8601String(),
    };

/// Issue #128 (kAccountExportSchemaVersion v6): one visit-prep checklist
/// item, including its check state — the clinician-facing export carries
/// the prep list. `checkedByUserId` stays out per this file's R9 rule.
Map<String, Object?> _exportVisitPrepItem(VisitPrepItem item) => {
      'id': item.id,
      'body': item.body,
      'isChecked': item.isChecked,
      'checkedAt': item.checkedAt?.toUtc().toIso8601String(),
      'updatedAt': item.updatedAt.toUtc().toIso8601String(),
    };
