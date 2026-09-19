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

import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import 'health_fertility_mapping.dart';
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
