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
/// Pure Dart (R14/R16) — no Flutter/drift imports.
library;

import 'package:lunarlog/domain/models/local_date.dart';

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
