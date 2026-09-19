/// The one-way health-store write contract (Issue #193): the seam the
/// debounced coordinator drives, expressed in domain models only.
///
/// The concrete implementation lives in
/// `lib/data/health/health_flow_write_service.dart`; this file also owns
/// [HealthFlowSyncReport], the value one pass returns, so the contract can
/// name it without dragging a data type into `lib/domain`.
library;

import 'package:lunarlog/domain/health/health_platform.dart';

/// What one [HealthFlowWriteService.syncNow] pass did. Counts are per
/// pass; [blocked] carries the terminal outcome that stopped (or ended)
/// the pass when it was not a clean full run.
class HealthFlowSyncReport {
  const HealthFlowSyncReport({
    required this.bound,
    this.authorizationRequested = false,
    this.blocked,
    this.samplesWritten = 0,
    this.periodRecordsWritten = 0,
    this.symptomSamplesWritten = 0,
    this.cervicalMucusSamplesWritten = 0,
    this.ovulationTestSamplesWritten = 0,
    this.basalBodyTemperatureSamplesWritten = 0,
    this.daysWithoutSample = 0,
    this.samplesReconciled = 0,
  });

  /// Whether a live bound profile was found to sync at all. `false` means
  /// health sync is off for this device (or the bound profile was deleted)
  /// — nothing else in the report is meaningful.
  final bool bound;

  /// Whether this pass performed the one-time `requestWriteAuthorization`
  /// call (i.e. this was the grant moment).
  final bool authorizationRequested;

  /// The non-allowed outcome that ended the pass before everything
  /// eligible was written: a guard refusal (`HealthPlatformRefused`), an
  /// authorization prompt outcome, or a failing write. Null on a fully
  /// successful pass (including a pass where every eligible day mapped to
  /// no sample). The cursor is advanced only when this is null.
  final HealthPlatformResult? blocked;

  /// Days a sample/record was actually written for.
  final int samplesWritten;

  /// Period-episode interval records (`MenstruationPeriodRecord`, Issue
  /// #202) actually written this pass — distinct from [samplesWritten],
  /// which counts the per-day flow/intermenstrual writes.
  final int periodRecordsWritten;

  /// HealthKit symptom samples written this pass (Issue #238) — one per
  /// distinct HealthKit symptom type on an eligible day's tags. Always 0
  /// on a platform with no symptom types (Health Connect), where the
  /// write is a graceful `unavailable` skip.
  final int symptomSamplesWritten;

  /// Cervical-mucus samples written this pass (Issue #228) — at most one
  /// per eligible day (discharge is single-select).
  final int cervicalMucusSamplesWritten;

  /// Ovulation-test samples written this pass (Issue #228) — one per
  /// distinct platform result on an eligible day (positive and peak
  /// collapse to one).
  final int ovulationTestSamplesWritten;

  /// Basal-body-temperature samples written this pass (Issue #228) — one per
  /// eligible manually tracked/imported `bbt` observation.
  final int basalBodyTemperatureSamplesWritten;

  /// Eligible days that mapped to [HealthFlowNoWrite] (`none`/
  /// `notBleeding`), or to a skipped duplicate (spotting on a day whose
  /// own flow already carries the intensity).
  final int daysWithoutSample;

  /// Issue #619, LLA-024: of [daysWithoutSample], how many issued a
  /// `deleteRecords` call for their own record id — reconciling away a
  /// sample a PRIOR pass may have written under that same id, for a day
  /// that has since been edited to no sample (e.g. an exported bleeding
  /// day changed to `notBleeding`). Deleting an id with no matching store
  /// sample is a documented no-op, so this call is issued unconditionally
  /// for every eligible no-write day rather than only when a prior write
  /// is known to have happened.
  final int samplesReconciled;
}

abstract interface class HealthFlowWriteService {
  /// Runs one sync pass for the currently bound profile. Never throws —
  /// every expected failure mode is a [HealthFlowSyncReport.blocked];
  /// unexpected storage errors propagate (the coordinator's job to
  /// tolerate).
  Future<HealthFlowSyncReport> syncNow();

  /// The unbind/reset half of the write flow: clears the forward-only
  /// cursor and the native-side binding mirror.
  Future<void> onUnbound();
}
