/// The canonical record-id builders for the `lunarlog/health` sync (Issue
/// #924): the exact strings the write path stamps as the platform's
/// stable per-record id — Health Connect `clientRecordId` / HealthKit
/// `HKMetadataKeyExternalUUID` — in one place, so the **write** path and
/// the **tombstone-deletion** path cannot drift onto different schemes.
///
/// Before #924 the deletion coordinator relayed only a day entry's own id,
/// which is exactly the flow sample's record id but *not* the record id of
/// any sample derived from that day (a symptom, cervical-mucus, or
/// ovulation-test sample embeds the day entry id inside a longer string).
/// A widened native delete is useless if the id it is handed never matches
/// what was written, so the builders live here and both paths call them.
///
/// [healthRecordIdsForEntry] is the second shared piece (Issue #930): the
/// full set of record ids a live day entry's tags produce, derived here so
/// the **write** path, the **tombstone-deletion** coordinator, and the
/// write path's own removed-record reconcile all agree. Before it existed
/// the coordinator kept a private copy of this derivation and the write
/// path had none at all, which is exactly how an edited-away symptom could
/// be written once and never addressed again.
///
/// Pure Dart (R14/R16) — no Flutter/drift imports.
library;

import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_platform.dart'
    show HealthWriteTypes;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import 'health_fertility_mapping.dart';
import 'health_flow_mapping.dart' show flowPayloadSummaryWasMarker;
import 'health_symptom_mapping.dart';

/// The record id of a day's menstrual-flow / intermenstrual-bleeding sample
/// (and of the `HealthFlowNoWrite` reconciliation delete): the day entry's
/// own ULID, exactly as `health_flow_write_service.dart` writes it.
String healthFlowRecordId(String dayEntryId) => dayEntryId;

/// The record id of a spotting observation's sample: the observation's own
/// ULID (the write path queues spotting rows through the flow writer, so
/// this is [healthFlowRecordId]'s id for the observation row).
String healthSpottingRecordId(String observationId) => observationId;

/// The record id of one `(day entry, HealthKit symptom type)` pair
/// (Issue #238).
String healthSymptomRecordId(String dayEntryId, String typeIdentifier) =>
    'symptom-$dayEntryId-$typeIdentifier';

/// The record id of a day's cervical-mucus sample (Issue #228).
String healthCervicalMucusRecordId(String dayEntryId) =>
    'cervical-mucus-$dayEntryId';

/// The record id of one `(day entry, HealthKit ovulation-result)` pair
/// (Issue #228).
String healthOvulationRecordId(String dayEntryId, String healthKitResult) =>
    'ovulation-$dayEntryId-$healthKitResult';

/// The record id of a basal-body-temperature observation's sample
/// (Issue #228).
String healthBbtRecordId(String observationId) => 'bbt-$observationId';

/// The record id of one period episode's interval record (Issue #202).
String healthPeriodRecordId(String profileId, LocalDate start) =>
    'period-$profileId-${start.iso}';

/// Every health-store record id one live [entry]'s tags can produce: its
/// flow/marker id itself ([healthFlowRecordId]), plus the symptom
/// ([healthSymptomRecordId]), cervical-mucus
/// ([healthCervicalMucusRecordId]), and ovulation
/// ([healthOvulationRecordId]) ids the write path derives from the entry's
/// tags. Callers that need the "what this day currently asserts" set — the
/// tombstone coordinator remembering a live row, or the write path diffing
/// against a previous export (Issue #930) — must use this and never
/// re-derive a subset.
///
/// Severity is irrelevant to the id, so the graded pain map is deliberately
/// empty: a pain grade change rewrites the same symptom id, which is an
/// update rather than a removal.
Set<String> healthRecordIdsForEntry(DayEntry entry) {
  final ids = <String>{healthFlowRecordId(entry.id)};
  for (final symptom in resolveHealthKitSymptoms(
    tags: entry.tags,
    gradedPainIntensities: const <String, int>{},
  )) {
    ids.add(healthSymptomRecordId(entry.id, symptom.typeIdentifier));
  }
  if (resolveCervicalMucus(entry.tags) != null) {
    ids.add(healthCervicalMucusRecordId(entry.id));
  }
  for (final ovulation in resolveOvulationTests(entry.tags)) {
    ids.add(healthOvulationRecordId(entry.id, ovulation.healthKitResult));
  }
  return ids;
}

/// Whether a delete of the record [written] is sure to reach it, given the
/// write types switched on in the health store (Issue #1581). [granted] is
/// `HealthPlatformStore.grantedWriteTypes`' answer, or null when every
/// type is on.
///
/// Both native halves delete by record id across every type they write,
/// pass over a type they may not write, and answer partial with the
/// skippedTypes (not allowed, since #1592). So a delete sent while the
/// record's type is off removes nothing. The write pass asks this first, to
/// avoid a delete the store will pass over, and leaves such a record
/// remembered until its type is back on; a record whose type a delete did
/// skip stays in the ledger the same way (_passedOver).
///
/// The type is read off the id, which is how these builders made it. A
/// spotting observation's record is the one that can be either of two
/// types — an intermenstrual marker, or a light flow sample when the day
/// falls inside a period. Since Issue #1591 the ledger's
/// [HealthExportLedgerEntry.payloadSummary] says which it was, and only
/// that type's switch is waited for ([flowPayloadSummaryWasMarker]); a
/// row written before then carries no summary, and keeps the old reading
/// of needing both.
bool healthRecordDeletable(
  HealthExportLedgerEntry? written,
  Set<String>? granted,
) {
  if (written == null || granted == null) return true;
  return switch (written.kind) {
    HealthExportLedgerKind.period =>
      granted.contains(HealthWriteTypes.menstrualFlow),
    HealthExportLedgerKind.bbt =>
      granted.contains(HealthWriteTypes.basalBodyTemperature),
    HealthExportLedgerKind.spotting =>
      _spottingRecordDeletable(written.payloadSummary, granted),
    HealthExportLedgerKind.entry => _entryRecordDeletable(written, granted),
  };
}

/// [healthRecordDeletable] for a spotting record. Since Issue #1591 the
/// ledger's [HealthExportLedgerEntry.payloadSummary] says which of the two
/// types the record was written as, and only that type's switch is waited
/// for ([flowPayloadSummaryWasMarker]); a row written before then carries
/// no summary, and keeps the old reading of needing both.
bool _spottingRecordDeletable(String? payloadSummary, Set<String> granted) =>
    switch (flowPayloadSummaryWasMarker(payloadSummary)) {
      true => granted.contains(HealthWriteTypes.spotting),
      false => granted.contains(HealthWriteTypes.menstrualFlow),
      null => granted.contains(HealthWriteTypes.menstrualFlow) &&
          granted.contains(HealthWriteTypes.spotting),
    };

/// [healthRecordDeletable] for a record written from a day entry.
bool _entryRecordDeletable(
  HealthExportLedgerEntry written,
  Set<String> granted,
) {
  final recordId = written.recordId;
  final entryId = written.sourceRowId;
  if (recordId == healthFlowRecordId(entryId)) {
    return granted.contains(HealthWriteTypes.menstrualFlow);
  }
  if (recordId == healthCervicalMucusRecordId(entryId)) {
    return granted.contains(HealthWriteTypes.cervicalMucus);
  }
  final symptomPrefix = healthSymptomRecordId(entryId, '');
  if (recordId.startsWith(symptomPrefix)) {
    return granted.contains(HealthWriteTypes.symptoms) ||
        granted.contains(recordId.substring(symptomPrefix.length));
  }
  if (recordId.startsWith(healthOvulationRecordId(entryId, ''))) {
    return granted.contains(HealthWriteTypes.ovulationTest);
  }
  // Not a shape this file builds: nothing to hold it back on.
  return true;
}

/// Whether a delete that passed over [skippedTypes] may have left the
/// symptom record [recordId] in the store.
///
/// HealthKit grants each symptom type on its own, and the iOS half names
/// every one that is off, with [HealthWriteTypes.symptoms] beside them
/// whenever any is. So the record's own type decides. Read as "all of
/// them", that extra name kept every symptom record remembered while any
/// one symptom type was off: a headache she unticked was deleted from
/// Apple Health, then asked to be deleted again on every pass, and every
/// pass reported a partial failure.
///
/// The type is what follows the last hyphen of the id
/// ([healthSymptomRecordId]); no type name has one. The extra name alone,
/// with no symptom type beside it, is a store that does not say which,
/// and then every symptom record may still be there.
bool _symptomRecordMatchesSkippedType(
  String recordId,
  Set<String> skippedTypes,
) {
  final type = recordId.substring(recordId.lastIndexOf('-') + 1);
  if (skippedTypes.contains(type)) return true;
  return skippedTypes.contains(HealthWriteTypes.symptoms) &&
      !kSymptomHealthKitTypeIdentifiers.values.any(skippedTypes.contains);
}

/// Checks whether [recordId] belongs to one of the write types in [skippedTypes]
/// (Issue #1583).
///
/// For a spotting record ([isSpotting]), [payloadSummary] indicates whether it
/// was written as an intermenstrual marker or a flow sample inside a period
/// (Issue #1591, Issue #1644). If [payloadSummary] is known, only a skip of that
/// specific type indicates the record may still be in the store. If [payloadSummary]
/// is null (written by an earlier build), either type being passed over may have
/// left the record in the store.
bool healthRecordMatchesSkippedType(
  String recordId,
  Set<String> skippedTypes, {
  bool isSpotting = false,
  String? payloadSummary,
}) {
  if (skippedTypes.isEmpty) return false;
  if (recordId.startsWith('cervical-mucus-')) {
    return skippedTypes.contains(HealthWriteTypes.cervicalMucus);
  }
  if (recordId.startsWith('ovulation-')) {
    return skippedTypes.contains(HealthWriteTypes.ovulationTest);
  }
  if (recordId.startsWith('bbt-')) {
    return skippedTypes.contains(HealthWriteTypes.basalBodyTemperature);
  }
  if (recordId.startsWith('period-')) {
    return skippedTypes.contains(HealthWriteTypes.menstrualFlow);
  }
  if (recordId.startsWith('symptom-')) {
    return _symptomRecordMatchesSkippedType(recordId, skippedTypes);
  }
  if (isSpotting) {
    return switch (flowPayloadSummaryWasMarker(payloadSummary)) {
      true => skippedTypes.contains(HealthWriteTypes.spotting),
      false => skippedTypes.contains(HealthWriteTypes.menstrualFlow),
      null => skippedTypes.contains(HealthWriteTypes.spotting) ||
          skippedTypes.contains(HealthWriteTypes.menstrualFlow),
    };
  }
  return skippedTypes.contains(HealthWriteTypes.menstrualFlow);
}
