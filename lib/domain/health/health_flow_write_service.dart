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

  /// Rows the pass looked at that map to no sample: a day whose flow is
  /// `none` or `notBleeding`, or a spotting entry on a day whose own flow
  /// already carries the intensity. Since Issue #1581 the pass looks at
  /// every row saved since write access was granted, so this counts them
  /// all on every pass, not only the ones that changed.
  final int daysWithoutSample;

  /// Records taken out of the store this pass because their row no longer
  /// produces them (Issue #619, LLA-024; Issue #930): a bleeding day
  /// changed to `notBleeding`, a symptom or fertility tag removed, a
  /// reading cleared. Counts only records this device remembers writing
  /// (Issue #1581); a row that never had a record in the store sends no
  /// delete.
  final int samplesReconciled;
}

abstract interface class HealthFlowWriteService {
  /// Runs one sync pass for the currently bound profile. Never throws —
  /// every expected failure mode is a [HealthFlowSyncReport.blocked];
  /// unexpected storage errors propagate (the coordinator's job to
  /// tolerate).
  Future<HealthFlowSyncReport> syncNow();

  /// The unbind/reset half of the write flow: clears the forward-only
  /// cursor and the native-side binding mirror. Runs through the pass
  /// queue ([runInPassQueue]), so it lands after any pass that was running
  /// or already queued when the binding went away (Issue #1702) — the
  /// clear is the last writer, and a pass cannot re-store what it cleared.
  Future<void> onUnbound();
}

/// The one-at-a-time queue every health write pass runs through (Issue
/// #1581), exposed as its own seam so another writer can join it instead of
/// racing a pass.
///
/// Issue #1614: `HealthSyncTombstoneCoordinator` deletes a tombstoned row's
/// records on its own. Without this, its delete could land after a pass had
/// written the records again (Undo saves the row back within the debounce
/// windows), leaving them gone from the store and the ledger until another
/// pass. Through this queue the delete either runs before the pass — which
/// then sees the live row and writes again — or after it, with the
/// tombstoned set collected at execution time, when the row is live again
/// and nothing is deleted.
abstract interface class HealthWritePassQueue {
  /// Runs [action] with no write pass able to interleave: it starts after
  /// the pass that is running (and any queued behind it), and a pass
  /// requested while it runs waits for it. [action] must not request a
  /// pass itself (a pass queues behind the action and would wait forever).
  Future<T> runInPassQueue<T>(Future<T> Function() action);
}
