/// Dev-only crash-report smoke trigger (#973): the two probes that raise a
/// data-layer error and a UI-layer error on demand so the owner's manual
/// #19 privacy smoke test can observe the scrubbed payloads in Sentry.
///
/// The trigger surface itself lives in Settings → About and renders only
/// when `AppConfig.crashSmokeEnabled` is true — `LUNARLOG_CRASH_SMOKE=true`
/// *and* `kDebugMode`. Nothing here is reachable in a store or QA build;
/// it is compiled into debug runs only and tree-shaken out of the rest.
///
/// This library owns the capture call so both probes go through one path:
/// a probe throws, its original stack trace (captured at the throw site, so
/// the `lunarlog/data/` frame survives) is handed to `Sentry.captureException`,
/// and the already-wired `beforeSend` hook in [configureSentryOptions]
/// applies `scrubEvent` before anything leaves the device. The UI-layer
/// probe is passed in as a `Never Function()` rather than imported, because
/// `lib/observability` must not depend on `lib/ui`.
library;

import 'dart:async' show unawaited;

import 'package:lunarlog/data/diagnostics/crash_smoke_probe.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A no-argument probe that always throws. `Never` lets a UI-layer thrower
/// be injected without this library importing `lib/ui`; the crash trigger's
/// About tile passes `lib/ui/settings/crash_smoke_trigger.dart`'s
/// `throwUiCrashSmoke`, so the reported stack trace points into `lib/ui`.
typedef CrashSmokeProbe = Never Function();

/// The reporting call every probe funnels through. Injectable so tests can
/// capture the `(error, stackTrace)` pair the probe produced — and convert
/// it through a local `Hub` — instead of touching the network, while
/// production reports through the real, configured Sentry hub.
typedef CrashSmokeReporter = void Function(Object error, StackTrace stackTrace);

void _sentryReporter(Object error, StackTrace stackTrace) {
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}

/// Runs the data-layer probe ([throwDataLayerCrashSmoke]) and reports the
/// error it threw.
void captureDataLayerCrashSmoke({
  CrashSmokeReporter report = _sentryReporter,
}) =>
    _capture(throwDataLayerCrashSmoke, report);

/// Runs [probe] (the UI-layer thrower, injected by the caller) and reports
/// the error it threw.
void captureUiCrashSmoke({
  required CrashSmokeProbe probe,
  CrashSmokeReporter report = _sentryReporter,
}) =>
    _capture(probe, report);

/// Runs [probe] and hands the thrown error and its original stack trace to
/// [report]. Catching broadly is the point: the trigger is a deliberate
/// error generator, so an escaping exception would crash the debug build
/// instead of producing a report.
void _capture(CrashSmokeProbe probe, CrashSmokeReporter report) {
  try {
    probe();
  } catch (error, stackTrace) {
    report(error, stackTrace);
  }
}
