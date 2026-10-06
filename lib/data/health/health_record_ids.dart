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
/// [healthStoreTypesForRecordId] is the third (Issue #1555): the builders
/// read backwards, from a record id to the store types the record can be
/// in. A delete carries those, because removing a record needs its own
/// type's write permission and each type can be switched off by itself.
///
/// Pure Dart (R14/R16) — no Flutter/drift imports.
library;

import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import 'health_fertility_mapping.dart';
import 'health_symptom_mapping.dart';

// What each builder below puts in front of the source row's id. Shared with
// [healthStoreTypesForRecordId], which reads them back.
const String _symptomPrefix = 'symptom-';
const String _cervicalMucusPrefix = 'cervical-mucus-';
const String _ovulationPrefix = 'ovulation-';
const String _bbtPrefix = 'bbt-';
const String _periodPrefix = 'period-';

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
    '$_symptomPrefix$dayEntryId-$typeIdentifier';

/// The record id of a day's cervical-mucus sample (Issue #228).
String healthCervicalMucusRecordId(String dayEntryId) =>
    '$_cervicalMucusPrefix$dayEntryId';

/// The record id of one `(day entry, HealthKit ovulation-result)` pair
/// (Issue #228).
String healthOvulationRecordId(String dayEntryId, String healthKitResult) =>
    '$_ovulationPrefix$dayEntryId-$healthKitResult';

/// The record id of a basal-body-temperature observation's sample
/// (Issue #228).
String healthBbtRecordId(String observationId) => '$_bbtPrefix$observationId';

/// The record id of one period episode's interval record (Issue #202).
String healthPeriodRecordId(String profileId, LocalDate start) =>
    '$_periodPrefix$profileId-${start.iso}';

/// The store types a record can be in, on each platform (Issue #1555).
///
/// Removing a record needs its type's write permission, and each type can
/// be switched off on its own. A delete call names these types so the
/// native half can tell "a type this call needs is off" from "some other
/// type is off": someone who declines a type she never logs must still
/// have her other removals acknowledged.
class HealthRecordStoreTypes {
  const HealthRecordStoreTypes({
    required this.healthKit,
    required this.healthConnect,
  });

  /// HealthKit case names, as in `kHealthKitWrittenTypeCaseNames`. Empty
  /// for a record HealthKit has no type for (the period record).
  final Set<String> healthKit;

  /// Health Connect record class names, as in
  /// `kHealthConnectWrittenRecordTypes`. Empty for a record Health Connect
  /// has no type for (every symptom).
  final Set<String> healthConnect;
}

/// A day's own record: a flow sample or a spotting marker, whichever the
/// day mapped to when it was written. The id does not say which, so both
/// types count.
const HealthRecordStoreTypes _flowStoreTypes = HealthRecordStoreTypes(
  healthKit: {'menstrualFlow', 'intermenstrualBleeding'},
  healthConnect: {'MenstruationFlowRecord', 'IntermenstrualBleedingRecord'},
);

/// The types of every record id that starts with a prefix of its own,
/// except a symptom's, whose type is in the id itself.
const Map<String, HealthRecordStoreTypes> _prefixedStoreTypes = {
  _cervicalMucusPrefix: HealthRecordStoreTypes(
    healthKit: {'cervicalMucusQuality'},
    healthConnect: {'CervicalMucusRecord'},
  ),
  _ovulationPrefix: HealthRecordStoreTypes(
    healthKit: {'ovulationTestResult'},
    healthConnect: {'OvulationTestRecord'},
  ),
  _bbtPrefix: HealthRecordStoreTypes(
    healthKit: {'basalBodyTemperature'},
    healthConnect: {'BasalBodyTemperatureRecord'},
  ),
  _periodPrefix: HealthRecordStoreTypes(
    healthKit: {},
    healthConnect: {'MenstruationPeriodRecord'},
  ),
};

/// The store types the record [recordId] can be in: the inverse of the
/// builders above. Null when the id is not one of theirs, which a caller
/// must read as "any type".
///
/// A source row's own id is a ULID and holds no dash, so an id with a dash
/// and no known prefix is not recognised rather than taken for a day's own
/// record. That keeps a builder added later from being read as a flow
/// record before this function knows it.
HealthRecordStoreTypes? healthStoreTypesForRecordId(String recordId) {
  if (recordId.startsWith(_symptomPrefix)) return _symptomStoreTypes(recordId);
  for (final family in _prefixedStoreTypes.entries) {
    if (recordId.startsWith(family.key)) return family.value;
  }
  return recordId.contains('-') ? null : _flowStoreTypes;
}

/// A symptom record's types: the HealthKit type its id ends with, and no
/// Health Connect type, since Health Connect has none. Null when the id
/// does not end with a symptom type this app writes.
HealthRecordStoreTypes? _symptomStoreTypes(String recordId) {
  final type = recordId.substring(recordId.lastIndexOf('-') + 1);
  if (!kSymptomHealthKitTypeIdentifiers.containsValue(type)) return null;
  return HealthRecordStoreTypes(healthKit: {type}, healthConnect: const {});
}

/// The store types [recordIds] can be in between them, or null when any of
/// them is not recognised ([healthStoreTypesForRecordId]).
HealthRecordStoreTypes? healthStoreTypesForRecordIds(
  Iterable<String> recordIds,
) {
  final healthKit = <String>{};
  final healthConnect = <String>{};
  for (final recordId in recordIds) {
    final types = healthStoreTypesForRecordId(recordId);
    if (types == null) return null;
    healthKit.addAll(types.healthKit);
    healthConnect.addAll(types.healthConnect);
  }
  return HealthRecordStoreTypes(
    healthKit: healthKit,
    healthConnect: healthConnect,
  );
}

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
