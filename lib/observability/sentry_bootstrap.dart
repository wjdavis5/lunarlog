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
    (options) => configureSentryOptions(options, dsn: dsn),
    appRunner: appRunner,
  );
}

/// Applies the KTD12 privacy floor to [options]. Pure over [options]; kept
/// separate from [runWithSentry] so tests can assert every setting.
void configureSentryOptions(SentryFlutterOptions options,
    {required String dsn}) {
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
    // Errors at 100% (R17, tiny user base); no performance or profiling
    // data, which would carry route names and request URLs.
    ..sampleRate = 1.0
    ..tracesSampleRate = null
    // ignore: experimental_member_use
    ..profilesSampleRate = null
    // Release health (R17).
    ..enableAutoSessionTracking = true
    // Request bodies are never attached to captured HTTP failures.
    ..maxRequestBodySize = MaxRequestBodySize.never;
  // Allowlist scrubbing (R18).
  options.beforeSend = (event, hint) => scrubEvent(event);
  options.beforeBreadcrumb = (breadcrumb, hint) => scrubBreadcrumb(breadcrumb);
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
