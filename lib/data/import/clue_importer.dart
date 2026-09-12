/// Applies a parsed Clue export to the local store (Issue #199, epic:
/// Import): the effectful half of the Clue import, mirroring
/// `account_importer.dart`'s split between pure planning/domain and a thin
/// storage adapter.
///
/// Every row is stamped `source: 'clue_import'` with a `source_id` derived
/// from the file's checksum ([clueDaySourceId]/[clueObservationSourceId] in
/// `lib/domain/import/clue/clue_import_run.dart`), so re-importing the same
/// file addresses the same rows: rows already holding identical content are
/// left untouched (a true no-op — no write, no `dirty` bump), and only
/// genuinely new or changed rows are written. The whole run is wrapped in
/// one [LunarLogStorage.db] transaction: an unexpected failure partway
/// through rolls everything back, never a partial import.
///
/// Mapping discipline (the issue's explicit boundaries): only what already
/// has a home on main is mapped — `period` levels via `flowLevelFromClue`
/// (Issue #247) onto the day entry's `flow`, every other known type onto
/// its [kClueTypeMap] category/code (Issue #190), numerics onto `bbt`.
/// Anything else lands in `observations.raw` via [clueRawJson] and is
/// counted in the summary, never mapped (#190 owns future mappings) and
/// never dropped. Day-entry `tags`/`note` are never written by this
/// importer (Clue options live in `observations`, the tracking model's
/// home per Issue #240); an existing row's tags/note/`pms` are preserved
/// verbatim on a flow upgrade.
///
/// Custom/free-text content stays out of diagnostics: skip details carry
/// shapes and bound names, never values (see [ClueImportSummary]).
library;

import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/tables.dart' as db;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/domain/import/clue/clue_cycle_reconstruction.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/import/clue/clue_flow_level_mapping.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart';
import 'package:lunarlog/domain/import/clue/clue_option_map.dart';
import 'package:lunarlog/domain/limits.dart';

/// Runs one Clue file import against the local store (Issue #199).
class ClueImporter {
  ClueImporter(this._storage);

  final LunarLogStorage _storage;

  /// Writes [parseResult]'s datapoints for [profileId] and returns the
  /// explicit "what did (and did not) come across" summary. [fileChecksum]
  /// is [clueFileChecksum] of the original file bytes — the idempotency
  /// anchor. [tz] is the IANA zone stamped on newly created day entries
  /// (an upgraded row keeps its stored zone).
  Future<ClueImportSummary> run({
    required String profileId,
    required String tz,
    required ClueExportParseResult parseResult,
    required String fileChecksum,
  }) async {
    final planned = summarizeClueImport(parseResult);
    final grouped = groupClueDatapointsByDate(parseResult.datapoints);
    var daysWritten = 0;
    var daysUnchanged = 0;
    var observationsWritten = 0;
    var observationsUnchanged = 0;
    var rowsSkipped = 0;
    final skippedDetails = <String>[];
    void skip(String reason) {
      rowsSkipped++;
      if (skippedDetails.length < kMaxSkippedDetails) {
        skippedDetails.add(reason);
      }
    }

    await _storage.db.transaction(() async {
      for (final entry in grouped.entries) {
        final dateIso = entry.key.iso;
        final dayId = await _ensureDayEntry(
          profileId: profileId,
          tz: tz,
          dateIso: dateIso,
          datapoints: entry.value,
          fileChecksum: fileChecksum,
          onWritten: () => daysWritten++,
          onUnchanged: () => daysUnchanged++,
          onSkip: skip,
        );
        if (dayId == null) continue;
        final ordinals = <String, int>{};
        for (final datapoint in entry.value) {
          if (datapoint is CluePeriodDatapoint) continue;
          final ordinal = ordinals[datapoint.clueType] ?? 0;
          ordinals[datapoint.clueType] = ordinal + 1;
          await _ensureObservation(
            profileId: profileId,
            tz: tz,
            dayEntryId: dayId,
            dateIso: dateIso,
            datapoint: datapoint,
            ordinal: ordinal,
            fileChecksum: fileChecksum,
            onWritten: () => observationsWritten++,
            onUnchanged: () => observationsUnchanged++,
            onSkip: skip,
          );
        }
      }
    });
    return planned.withApplied(
      daysWritten: daysWritten,
      daysUnchanged: daysUnchanged,
      observationsWritten: observationsWritten,
      observationsUnchanged: observationsUnchanged,
      rowsSkipped: rowsSkipped,
      skippedDetails: skippedDetails,
    );
  }

  /// Ensures the day entry for one date exists and carries the import's
  /// flow level, returning its id — or null when the day could not be
  /// written (counted via [onSkip], never thrown: one bad day must not
  /// abort the rest of the file). Kept as a thin try/catch shell over
  /// [_refreshDayEntry]/[_adoptDayEntry] so no single method carries both
  /// the lookup branches and the write branches.
  Future<String?> _ensureDayEntry({
    required String profileId,
    required String tz,
    required String dateIso,
    required List<ClueDatapoint> datapoints,
    required String fileChecksum,
    required void Function() onWritten,
    required void Function() onUnchanged,
    required void Function(String reason) onSkip,
  }) async {
    final sourceId = clueDaySourceId(
      fileChecksum: fileChecksum,
      dateIso: dateIso,
    );
    final desiredFlow = _desiredDayFlow(datapoints);
    try {
      final existing = await _storage.findDayEntryBySource(
        profileId: profileId,
        source: kClueImportSource,
        sourceId: sourceId,
      );
      if (existing != null) {
        return await _refreshDayEntry(
          existing: existing,
          profileId: profileId,
          dateIso: dateIso,
          sourceId: sourceId,
          desiredFlow: desiredFlow,
          onWritten: onWritten,
          onUnchanged: onUnchanged,
        );
      }
      return await _adoptDayEntry(
        profileId: profileId,
        tz: tz,
        dateIso: dateIso,
        desiredFlow: desiredFlow,
        sourceId: sourceId,
        onWritten: onWritten,
        onUnchanged: onUnchanged,
      );
    } on ArgumentError catch (error) {
      onSkip('day $dateIso not stored (${error.name ?? 'invalid value'})');
      return null;
    }
  }

  /// The import's flow level for one date, or null when the file carries no
  /// `period` datapoint for it (genuinely unlogged — never the explicit
  /// `notBleeding` assertion, which only a real `period/none` datapoint
  /// maps to via `flowLevelFromClue`).
  db.FlowLevel? _desiredDayFlow(List<ClueDatapoint> datapoints) {
    final highest = highestCluePeriodLevel([
      for (final d in datapoints)
        if (d is CluePeriodDatapoint) d,
    ]);
    return highest == null ? null : flowFromDomain(flowLevelFromClue(highest));
  }

  /// Reconciles a day entry a previous run of the same file already wrote
  /// (found by `source`/`source_id`, tombstones included): identical
  /// content is a no-op, a changed level is rewritten in place, and a
  /// tombstone is revived. Tags/note/`pms` on a live row are preserved —
  /// the importer never writes them.
  Future<String> _refreshDayEntry({
    required db.DayEntry existing,
    required String profileId,
    required String dateIso,
    required String sourceId,
    required db.FlowLevel? desiredFlow,
    required void Function() onWritten,
    required void Function() onUnchanged,
  }) async {
    final live = existing.deletedAt == null;
    if (live && (desiredFlow == null || existing.flow == desiredFlow)) {
      onUnchanged();
      return existing.id;
    }
    final row = await _storage.upsertDayEntry(
      id: existing.id,
      profileId: profileId,
      localDate: dateIso,
      tz: existing.tz,
      flow: desiredFlow ?? db.FlowLevel.none,
      tags: live ? existing.tags : const [],
      note: live ? existing.note : null,
      // A revived tombstone's marker stays cleared.
      pms: live ? existing.pms : false,
      source: kClueImportSource,
      sourceId: sourceId,
    );
    onWritten();
    return row.id;
  }

  /// Reconciles a date with no row from this file yet: attaches to the
  /// live row when one exists (upgrading an unlogged `none` flow, never
  /// downgrading a logged one), or inserts a fresh imported row.
  Future<String> _adoptDayEntry({
    required String profileId,
    required String tz,
    required String dateIso,
    required db.FlowLevel? desiredFlow,
    required String sourceId,
    required void Function() onWritten,
    required void Function() onUnchanged,
  }) async {
    final live =
        await _storage.getDayEntry(profileId: profileId, localDate: dateIso);
    if (live == null) {
      final row = await _storage.upsertDayEntry(
        profileId: profileId,
        localDate: dateIso,
        tz: tz,
        flow: desiredFlow ?? db.FlowLevel.none,
        source: kClueImportSource,
        sourceId: sourceId,
      );
      onWritten();
      return row.id;
    }
    if (desiredFlow == null ||
        live.flow == desiredFlow ||
        live.flow != db.FlowLevel.none) {
      // No period data, already at the imported level, or a manually
      // logged level the import must never downgrade: keep the row as-is.
      onUnchanged();
      return live.id;
    }
    final row = await _storage.upsertDayEntry(
      id: live.id,
      profileId: profileId,
      localDate: dateIso,
      tz: live.tz,
      flow: desiredFlow,
      tags: live.tags,
      note: live.note,
      pms: live.pms,
      source: live.source,
      sourceId: live.sourceId,
      importId: live.importId,
    );
    onWritten();
    return row.id;
  }

  /// Ensures one observation row for a non-period datapoint, idempotent on
  /// (profile, source, source_id) with content equality. Unknown shapes
  /// ride `raw`; known shapes ride their mapped columns with a null raw.
  Future<void> _ensureObservation({
    required String profileId,
    required String tz,
    required String dayEntryId,
    required String dateIso,
    required ClueDatapoint datapoint,
    required int ordinal,
    required String fileChecksum,
    required void Function() onWritten,
    required void Function() onUnchanged,
    required void Function(String reason) onSkip,
  }) async {
    final built = _buildObservation(
      tz: tz,
      dayEntryId: dayEntryId,
      datapoint: datapoint,
    );
    if (built == null) {
      onSkip('unrecognised ${datapoint.clueType} value too large to keep');
      return;
    }
    final sourceId = clueObservationSourceId(
      fileChecksum: fileChecksum,
      dateIso: dateIso,
      type: datapoint.clueType,
      ordinal: ordinal,
    );
    try {
      final existing = await _storage.findObservationBySource(
        profileId: profileId,
        source: kClueImportSource,
        sourceId: sourceId,
      );
      if (existing != null &&
          existing.deletedAt == null &&
          _sameObservationContent(existing, built)) {
        onUnchanged();
        return;
      }
      await _storage.upsertObservation(
        id: existing?.id,
        dayEntryId: dayEntryId,
        profileId: profileId,
        localDate: dateIso,
        tz: tz,
        category: built.category,
        code: built.code,
        valueNum: built.valueNum,
        unit: built.unit,
        excluded: built.excluded,
        source: kClueImportSource,
        sourceId: sourceId,
        raw: built.raw,
      );
      onWritten();
    } on ArgumentError catch (error) {
      onSkip(
          '${datapoint.clueType} on $dateIso not stored (${error.name ?? 'invalid value'})');
    }
  }

  /// Maps one non-period datapoint to its stored columns, or null when
  /// even the reduced `raw` cannot fit the column bound (the caller counts
  /// it as skipped rather than dropping it silently). Over-bound
  /// category/code strings are truncated to the server CHECK bounds — the
  /// full original always survives in `raw` for unknown shapes, and mapped
  /// codes over the bound cannot sync regardless (storage enforces the
  /// same bound for every writer).
  _ObservationBuild? _buildObservation({
    required String tz,
    required String dayEntryId,
    required ClueDatapoint datapoint,
  }) {
    if (datapoint is ClueObservationDatapoint) {
      return _ObservationBuild(
        category: _truncate(datapoint.category, kMaxObservationCategoryLength),
        code: datapoint.code.isEmpty
            ? null
            : _truncate(datapoint.code, kMaxObservationCodeLength),
      );
    }
    if (datapoint is ClueNumericDatapoint) {
      return _ObservationBuild(
        category: 'bbt',
        valueNum: datapoint.valueNum,
        unit: datapoint.unit == null
            ? null
            : _truncate(datapoint.unit!, kMaxObservationUnitLength),
        excluded: datapoint.excluded,
      );
    }
    if (datapoint is ClueUnknownDatapoint) {
      final raw = clueRawJson(datapoint.raw);
      if (raw == null) return null;
      final isKnownType = kClueTypeMap[datapoint.clueType] != null ||
          kClueNumericTypes.contains(datapoint.clueType);
      return _ObservationBuild(
        category: unmappedCategoryFor(datapoint.clueType),
        code: isKnownType
            ? null
            : _truncate(datapoint.clueType, kMaxObservationCodeLength),
        raw: raw,
      );
    }
    return null;
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  /// Content equality for the re-import no-op: identity (ids, dates) and
  /// sync bookkeeping (`updatedAt`, tombstone state) are excluded — only
  /// the payload and provenance that this importer itself writes.
  bool _sameObservationContent(db.Observation existing, _ObservationBuild built) =>
      existing.category == built.category &&
      existing.code == built.code &&
      existing.valueNum == built.valueNum &&
      existing.unit == built.unit &&
      existing.excluded == built.excluded &&
      existing.raw == built.raw &&
      existing.source == kClueImportSource;
}

/// The stored columns for one imported observation, before provenance is
/// attached by [_ensureObservation].
class _ObservationBuild {
  const _ObservationBuild({
    required this.category,
    this.code,
    this.valueNum,
    this.unit,
    this.excluded = false,
    this.raw,
  });

  final String category;
  final String? code;
  final double? valueNum;
  final String? unit;
  final bool excluded;
  final String? raw;
}
