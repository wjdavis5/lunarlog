/// Sentry bootstrap (U7; KTD12, R17, R19): the one place that configures
/// `SentryFlutter.init`, with the privacy floor applied as options and the
/// scrubbers from `scrub.dart` wired as `beforeSend`/`beforeBreadcrumb`.
///
/// With no DSN (tests, local runs, any build without `SENTRY_DSN`) nothing is
/// initialized and the app runner is awaited directly; `Sentry.capture*`
/// calls elsewhere then hit the SDK's no-op hub. The init function is
/// injectable so tests can assert both paths without touching the real SDK.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/scrub.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Shape of `SentryFlutter.init` (the SDK's tear-off has one more internal
/// optional parameter, which makes it assignable here).
typedef SentryInit = Future<void> Function(
  FlutterOptionsConfiguration optionsConfiguration, {
  AppRunner? appRunner,
});

/// Runs [appRunner] under Sentry when [dsn] is non-empty, otherwise directly.
///
/// [dsn] defaults to the build-time [AppConfig.sentryDsn]; [init] defaults to
/// the real `SentryFlutter.init`. Both are parameters only so the decision is
/// testable (R19).
Future<void> runWithSentry({
  required Future<void> Function() appRunner,
  SentryInit init = SentryFlutter.init,
  String dsn = AppConfig.sentryDsn,
}) async {
  if (dsn.isEmpty) {
    await appRunner();
    return;
  }
  await init(
    (options) => configureSentryOptions(
      options,
      dsn: dsn,
      tracesSampleRate: AppConfig.sentryTracesSampleRate,
    ),
    appRunner: appRunner,
  );
}

/// Applies the KTD12 privacy floor to [options]. Pure over [options]; kept
/// separate from [runWithSentry] so tests can assert every setting.
///
/// [breadcrumbLog] (Issue #6, U4; KTD9) receives every breadcrumb that
/// survives [scrubBreadcrumb] — feeding the feedback diagnostics preview
/// from the same already-scrubbed stream Sentry uses, so no new
/// instrumentation is needed when Sentry is configured. Defaults to the
/// shared [defaultBreadcrumbLog]; tests pass their own.
///
/// [tracesSampleRate] (U4; R9, R10, R14) is injectable for the same reason
/// [dsn] is: [AppConfig.sentryTracesSampleRate] is not `const` (parsing and
/// clamping cannot happen in a const initializer), so a default value here
/// would still read the real build's dart-define — coupling every test
/// that does not pass this parameter to whatever `flutter test` happened
/// to be invoked with. Defaulting to `null` (tracing off) instead means a
/// test suite run stays identical whether or not `--dart-define
/// =SENTRY_TRACES_SAMPLE_RATE=…` was passed; only [runWithSentry]'s
/// production call site passes the real [AppConfig] value.
void configureSentryOptions(
  SentryFlutterOptions options, {
  required String dsn,
  BreadcrumbLog? breadcrumbLog,
  double? tracesSampleRate,
}) {
  final log = breadcrumbLog ?? defaultBreadcrumbLog;
  options
    ..dsn = dsn
    // `release` is left to the SDK's LoadReleaseIntegration, which reads
    // `name@version+build` from the platform package info.
    ..environment = kReleaseMode ? 'production' : 'development'
    // Identity and content: never.
    ..sendDefaultPii = false
    ..attachScreenshot = false
    // ignore: experimental_member_use
    ..attachViewHierarchy = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableUserInteractionTracing = false
    // Errors at 100% (R17, tiny user base); no profiling data, which would
    // carry route names and request URLs.
    ..sampleRate = 1.0
    // U4 (R9, R14): null unless SENTRY_TRACES_SAMPLE_RATE is set, so an
    // unconfigured build produces no transactions and no app-start
    // measurement -- exactly today's behavior.
    ..tracesSampleRate = tracesSampleRate
    // ignore: experimental_member_use
    ..profilesSampleRate = null
    // Release health (R17).
    ..enableAutoSessionTracking = true
    // Request bodies are never attached to captured HTTP failures.
    ..maxRequestBodySize = MaxRequestBodySize.never
    // Native crash capture (U3; R6, R7, R8): every option set explicitly,
    // following this cascade's existing "so a default change upstream
    // cannot turn it on [or off]" convention.
    ..anrEnabled = true
    ..enableNativeCrashHandling = true
    ..enableNdkScopeSync = true
    ..enableAppHangTracking = true
    ..enableWatchdogTerminationTracking = true
    ..enableAutoNativeBreadcrumbs = true
    // The only option here that is off by SDK default (KTD6). Turning it on
    // would open an Android ApplicationExitInfo channel assembled natively
    // -- outside this scrubber -- from a process that holds decrypted
    // health strings in memory, and nobody has inspected what such a
    // payload actually carries. Pinned false; the opt-in (after a real
    // payload has been inspected) belongs to issue #19.
    ..enableTombstone = false
    // Print breadcrumbs are the only option left at the SDK default of
    // `true` in this cascade -- pinned false instead. `DebugPrintIntegration`
    // (sentry_flutter 9.28.0) turns every non-debug-mode `debugPrint` call
    // into a `Breadcrumb.console` with the raw printed text as `message`
    // and no `data`, so `containsDenyListedKey` (a key-name check) never
    // sees it; the only guard the message gets is `scrubBreadcrumb`'s
    // `mentionsDenyListedKey` word scan, which catches a literal key name
    // like `note` appearing as a token but not an arbitrary sensitive
    // *value* a caller happened to print -- e.g. `app_lifecycle.dart`'s
    // reset-failure handler does `debugPrint('lunarlog reset failed:
    // $error\n$stackTrace')`, and neither `error`'s message nor the stack
    // trace is guaranteed to avoid health-adjacent content. Same posture
    // as `enableTombstone` above: pin off until a real payload has been
    // inspected (issue #19), rather than ship a value-based scrubber this
    // file has never had reason to build.
    ..enablePrintBreadcrumbs = false;
  // Allowlist scrubbing (R18). scrubTransaction (U4) is inert while
  // tracesSampleRate is null -- no transaction is ever produced for it to
  // see -- and proven by unit tests long before an operator opts in.
  //
  // Every callback below fails closed: the SDK forwards the raw,
  // unscrubbed event/transaction/breadcrumb when a `beforeSend*`/
  // `beforeBreadcrumb` callback throws, so a bug in the scrubber itself
  // (an unexpected field shape, a null the scrubber didn't anticipate)
  // would otherwise leak exactly the payload this whole file exists to
  // stop. Catching broadly and returning null (drop) is deliberate here --
  // dropping a report is always safe, sending an unscrubbed one never is.
  options.beforeSend = (event, hint) {
    try {
      return scrubEvent(event);
    } catch (_) {
      return null;
    }
  };
  options.beforeSendTransaction = (transaction, hint) {
    try {
      return scrubTransaction(transaction);
    } catch (_) {
      return null;
    }
  };
  options.beforeBreadcrumb = (breadcrumb, hint) {
    try {
      final scrubbed = scrubBreadcrumb(breadcrumb);
      if (scrubbed != null) {
        log.record(
            scrubbed.category ?? 'breadcrumb', breadcrumbLabel(scrubbed));
      }
      return scrubbed;
    } catch (_) {
      return null;
    }
  };
  // Session replay stays off: both sample rates null (the SDK default) means
  // `replay.isEnabled` is false. Set explicitly so a default change upstream
  // cannot turn it on.
  options.replay
    ..sessionSampleRate = null
    ..onErrorSampleRate = null;
}

/// Wraps the root widget in [SentryWidget] when crash reporting is active;
/// returns [child] untouched otherwise, so an unconfigured build has no
/// Sentry widget in its tree.
Widget wrapWithSentry(Widget child) =>
    AppConfig.hasSentry ? SentryWidget(child: child) : child;

/// The [NavigatorObserver] list for `MaterialApp.navigatorObservers` (U2;
/// R1, R3, R4, R5, R13). Empty when Sentry is unconfigured, so an
/// unconfigured build installs no observer — same gate as [wrapWithSentry].
///
/// `setRouteNameAsTransaction: true` puts the current screen's (scrubbed —
/// KTD4) name on `event.transaction`; `enableAutoTransactions: true` is
/// inert while `AppConfig.sentryTracesSampleRate` is null (U4) and starts
/// producing route transactions only once an operator opts into tracing.
/// No `routeNameExtractor` is supplied: [scrub.dart]'s `scrubRouteName` is
/// the enforcement point regardless of what the observer reports, so a
/// second extraction layer here would be redundant, not safer.
List<NavigatorObserver> sentryNavigatorObservers() => AppConfig.hasSentry
    ? [
        SentryNavigatorObserver(
          enableAutoTransactions: true,
          setRouteNameAsTransaction: true,
        ),
      ]
    : const <NavigatorObserver>[];
