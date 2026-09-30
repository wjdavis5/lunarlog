/// The background half of the OS health-store import (Issue #993) — the
/// coordinator the platform triggers drive: an `HKObserverQuery` +
/// `enableBackgroundDelivery` on iOS (`AppDelegate.swift`'s
/// `HealthKitChannelHandler`), a periodic WorkManager job on Android
/// (`HealthBackgroundImportWorker.kt`). Both fire through the shared
/// `lunarlog/health` channel; this class turns each fire into exactly one
/// [HealthBackgroundImportRunner.importInBackground] pass — the same
/// anchored, never-overwrite, own-writes-excluded pipeline the Settings
/// tap runs, minus everything a background context must never do (see
/// `health_import.dart`'s interface doc: no prompt, no UI, and the Issue
/// #959 permission probe before any read).
///
/// **What the coordinator itself is responsible for** (everything else is
/// the service's or the natives' job):
///
/// * **The startup pull.** The platform may fire before Dart can listen —
///   iOS registers its observer during engine init, and a background
///   relaunch runs engine init before `main()`. `start` registers the
///   listener and then pulls the native latch
///   (`consumePendingBackgroundImportTrigger`), so a delivery that beat
///   the listener is not lost.
/// * **One pass at a time.** Overlapping triggers (HealthKit can fire for
///   both read types within milliseconds; a WorkManager tick can land
///   while an observer pass is running) are *dropped*, never queued: the
///   pipeline is idempotent and reads the whole window every pass, so a
///   queued pass could only re-derive the same merge. The running pass
///   simply finishes; the next trigger runs a fresh one.
/// * **Counts-only logging.** Every outcome lands in the app breadcrumb
///   log (`defaultBreadcrumbLog`) as category `healthBackgroundImport`
///   plus a coarse name — counts and blocked-kind names only, never a
///   sample, date, or profile id. A background pass leaves no other trace:
///   no notification, no dialog, no Settings state.
///
/// Pure Dart (R14/R16): the trigger and runner are injected interfaces, so
/// every branch here runs under `flutter test` against fakes.
library;

import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/observability/breadcrumbs.dart'
    show defaultBreadcrumbLog;

import 'health_background_import_trigger.dart';

// The service takes its collaborators as constructor parameters that are
// not initializing formals (private finals via the initializer list), the
// same declared pattern health_import_service.dart uses.
// ignore_for_file: prefer_initializing_formals

/// Drives [HealthBackgroundImportRunner] from the platform's triggers.
/// Started once at app composition (`lib/app.dart`, same gating as the
/// user-initiated runner — `AppConfig.hasHealthSync` plus a wired store);
/// disposing only matters to tests.
class HealthBackgroundImportCoordinator {
  HealthBackgroundImportCoordinator({
    required HealthBackgroundImportTrigger trigger,
    required HealthBackgroundImportRunner runner,
  }) : _trigger = trigger,
       _runner = runner;

  final HealthBackgroundImportTrigger _trigger;
  final HealthBackgroundImportRunner _runner;

  /// True while a triggered pass is between start and finish — the
  /// overlapping-trigger drop is keyed on this, never on the future (which
  /// completes after logging and can race a trigger that lands in the same
  /// microtask queue drain).
  bool _running = false;

  bool _started = false;

  /// Registers the trigger listener and immediately pulls the native
  /// pending latch (see the library doc). Idempotent: a second `start`
  /// re-listens and re-pulls rather than double-subscribing.
  Future<void> start() async {
    _started = true;
    _trigger.listen(_onTriggered);
    if (await _trigger.consumePendingTrigger()) {
      await _onTriggered();
    }
  }

  /// Clears the trigger listener. The composition root never calls this
  /// (the coordinator lives as long as the app); tests do.
  void dispose() {
    _started = false;
    _trigger.dispose();
  }

  /// One triggered pass: the re-entrancy drop, then the prompt-free
  /// runner, then the counts-only log line. Never rethrows: a failed pass
  /// is logged coarsely and the platform's next trigger retries it — a
  /// throw out of the trigger handler would surface as an unhandled zone
  /// error in a background context nobody can see.
  Future<void> _onTriggered() async {
    if (!_started) return;
    if (_running) {
      _log('skippedOverlappingTrigger');
      return;
    }
    _running = true;
    try {
      final summary = await _runner.importInBackground();
      _log(_summaryName(summary));
    } catch (_) {
      // Unexpected storage errors propagate out of the runner's contract
      // too; a background pass turns one into a coarse log line instead of
      // an unreachable exception.
      _log('failed');
    } finally {
      _running = false;
    }
  }

  /// The coarse outcome name: counts and deny-reason names only, never
  /// content (see the library doc) — no sample, date, or profile id. The
  /// deny reasons are [HealthSyncCheck]'s user-facing enum names, the same
  /// words the Settings screen would show.
  String _summaryName(HealthImportSummary summary) {
    if (summary.bound == false) return 'unbound';
    // Issue #1215: a trigger that fired before the binding's first
    // user-initiated import completed. Coarse on purpose — it names a
    // consent state, never a count or a date.
    if (summary.firstImportNotStarted) return 'notYetStarted';
    final blocked = summary.blocked;
    if (blocked == null) {
      return 'imported(${summary.daysWritten}+${summary.spottingDaysWritten})'
          ' unchanged=${summary.daysUnchanged}'
          ' keptManual=${summary.daysKeptManual}'
          ' samples=${summary.samplesRead}';
    }
    if (blocked is HealthPlatformPermissionDenied) {
      return 'permissionNotGranted';
    }
    if (blocked is HealthPlatformRefused) {
      return 'guardRefused(${blocked.check.name})';
    }
    return 'blocked';
  }

  void _log(String name) {
    defaultBreadcrumbLog.record(
      'healthBackgroundImport',
      '${_runner.platform.name} $name',
    );
  }
}
