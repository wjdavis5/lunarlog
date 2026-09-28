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

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
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
///
/// [scrubEventFn]/[scrubTransactionFn] (round 2 of issue #7's review) are
/// injectable for the same reason [breadcrumbLog] is: the fail-closed
/// `beforeSend`/`beforeSendTransaction` try/catch below exists to catch a
/// bug *in the scrubber itself*, and [scrubEvent]/[scrubTransaction] are
/// pure functions over well-typed SDK objects with no reachable throw path
/// through the public API -- so without a seam to substitute a throwing
/// stand-in, that catch block would be untestable and a regression in it
/// (the round-1 gap this closes) could ship green. Default to the real
/// [scrubEvent]/[scrubTransaction]; only tests override them.
///
/// [isWeb] (issue #1110) defaults to the compile-time [kIsWeb] and is
/// injectable for the same reason [tracesSampleRate] is: under
/// `flutter test` it is always false, so the web branch below (the Dart
/// transport swap and the `autoInitializeNativeSdk = false` pin) would be
/// unreachable without the seam. Only tests pass it.
///
/// [webHttpClient] is the HTTP client [WebDartSentryTransport] posts
/// envelopes through when the web branch runs. Defaults to a real
/// `http.Client()`; only tests inject one (a recording fake), so the
/// transport's endpoint, headers, and body are asserted off the wire
/// exactly as the SDK's own request handler would build them.
void configureSentryOptions(
  SentryFlutterOptions options, {
  required String dsn,
  bool? isWeb,
  http.Client? webHttpClient,
  BreadcrumbLog? breadcrumbLog,
  double? tracesSampleRate,
  SentryEvent? Function(SentryEvent event) scrubEventFn = scrubEvent,
  SentryTransaction? Function(SentryTransaction transaction)
      scrubTransactionFn =
      scrubTransaction,
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
    // *value* a caller happened to print. lunarlog's own call sites are
    // uniformly type-only now (issue #97), so this pin guards foreign
    // output: third-party packages and Flutter itself print values this
    // codebase does not control. Same posture as `enableTombstone` above:
    // pin off until a real payload has been inspected (issue #19), rather
    // than ship a value-based scrubber this file has never had reason to
    // build.
    ..enablePrintBreadcrumbs = false;
  // Web transport swap (issue #1110). On web, sentry_flutter 9.28.0 injects
  // its JS SDK from a hardcoded `browser.sentry-cdn.com` URL (no self-host
  // option) and delivers every envelope through that same JS binding --
  // which `script-src 'self'` in `web/_headers` blocks at both steps, so a
  // DSN'd web build has a dead SDK. `autoInitializeNativeSdk = false` is the
  // SDK's own switch for skipping the script load AND its `SentryWeb.init`
  // (`WebSdkIntegration.call` returns before both), and it also leaves the
  // `JavascriptTransport` the SDK installs as the default web transport
  // pointing at a binding that was never initialized -- so the transport is
  // swapped here for a Dart-side envelope POST straight to the DSN's
  // `*.ingest.sentry.io` endpoint, which `connect-src` already allows.
  // Everything above the swap (the KTD12 privacy floor) and the scrubbers
  // wired below are platform-independent: a web event is scrubbed by exactly
  // the same `beforeSend`/`beforeBreadcrumb` hooks a native event is.
  //
  // The accepted trade-off (the issue's option 2): errors that exist only in
  // the JS layer -- engine-level console errors, anything the browser JS
  // SDK's global handlers would catch outside Dart -- are no longer
  // observable on web at all, where today they were merely unreachable. Dart
  // errors, the ones a Flutter web build actually produces, keep flowing.
  if (isWeb ?? kIsWeb) {
    options
      ..autoInitializeNativeSdk = false
      ..transport = WebDartSentryTransport(
        dsn: dsn,
        options: options,
        client: webHttpClient,
      );
  }
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
      return scrubEventFn(event);
    } catch (_) {
      return null;
    }
  };
  options.beforeSendTransaction = (transaction, hint) {
    try {
      return scrubTransactionFn(transaction);
    } catch (_) {
      return null;
    }
  };
  options.beforeBreadcrumb = (breadcrumb, hint) {
    try {
      final scrubbed = scrubBreadcrumb(breadcrumb);
      if (scrubbed != null) {
        log.record(
          scrubbed.category ?? 'breadcrumb',
          breadcrumbLabel(scrubbed),
        );
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

/// A Dart-side envelope transport for the web build (issue #1110).
///
/// POSTs the raw envelope bytes straight to the DSN's ingest `envelope`
/// endpoint over `package:http` — on web that means the browser's own HTTP
/// stack, governed by `connect-src`, which `web/_headers` already pins to
/// the DSN's `*.ingest.sentry.io` host. The wire format mirrors the core
/// Dart SDK's own `HttpTransport` (package:sentry 9.28.0,
/// `transport/http_transport_request_handler.dart`): `Content-Type:
/// application/x-sentry-envelope` plus the `X-Sentry-Auth` credential
/// header. That is the shape the core SDK itself ships to browsers — its
/// `client_provider.dart` hands `HttpTransport` a browser `http.Client` on
/// the non-io branch — so ingest's CORS handling for these headers is the
/// SDK's own supported configuration, not a guess this file invented.
///
/// Deliberately minimal next to the real `HttpTransport`: no rate-limit
/// tracking, no retry-after handling, no client reports. Every failure path
/// drops the envelope and returns the SDK's empty id — exactly what the
/// SDK's `JavascriptTransport.send` does when a capture fails — because a
/// dropped crash report is the same loss the blocked CDN script causes
/// today, never a data-integrity risk. A malformed DSN degrades to that
/// same drop-everything posture rather than throwing at configure time:
/// [configureSentryOptions] has no way to surface an error there, and a
/// dead transport is the posture an empty DSN already produces.
class WebDartSentryTransport implements Transport {
  /// Builds a transport for [dsn]. [options] supplies the envelope
  /// serializer (attachment size caps) and the `sentry_client` credential
  /// string. [client] defaults to a real `http.Client()` — the browser's
  /// HTTP stack on web — and is injectable so tests can record the request.
  WebDartSentryTransport({
    required String dsn,
    required SentryOptions options,
    http.Client? client,
  }) : _options = options,
       _client = client ?? http.Client() {
    _parsed = _parseDsn(dsn, options.sentryClientName);
  }

  final SentryOptions _options;
  final http.Client _client;

  /// Null when [dsn] was empty or malformed: every send then drops.
  ({Uri endpoint, String authHeader})? _parsed;

  /// Parses [dsn] into the POST target and the `X-Sentry-Auth` credential
  /// header. The header's shape mirrors package:sentry 9.28.0's
  /// `_CredentialBuilder` verbatim; any parse failure returns null (the
  /// drop-everything posture documented on the class).
  static ({Uri endpoint, String authHeader})? _parseDsn(
    String dsn,
    String sentryClientName,
  ) {
    if (dsn.isEmpty) {
      return null;
    }
    final Uri endpoint;
    try {
      final parsed = Dsn.parse(dsn);
      // postUri builds and re-parses a new absolute Uri from the parsed
      // pieces, so a DSN that parsed as a *relative* Uri (no scheme/host --
      // Uri.parse accepts those) can still fail here. Both failure modes
      // mean the DSN cannot produce a usable endpoint: drop everything.
      endpoint = parsed.postUri;
      var authHeader =
          'Sentry sentry_version=7, '
          'sentry_client=$sentryClientName, '
          'sentry_key=${parsed.publicKey}';
      if (parsed.secretKey != null) {
        authHeader += ', sentry_secret=${parsed.secretKey}';
      }
      return (endpoint: endpoint, authHeader: authHeader);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final parsed = _parsed;
    if (parsed == null) {
      return SentryId.empty();
    }
    try {
      final body = <int>[];
      await for (final chunk in envelope.envelopeStream(_options)) {
        body.addAll(chunk);
      }
      final response = await _client.post(
        parsed.endpoint,
        headers: <String, String>{
          'Content-Type': 'application/x-sentry-envelope',
          'X-Sentry-Auth': parsed.authHeader,
        },
        body: body,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return envelope.header.eventId;
      }
      _options.log(
        SentryLevel.error,
        'WebDartSentryTransport: ingest returned ${response.statusCode}; '
        'envelope dropped.',
      );
      return SentryId.empty();
    } on Exception catch (exception, stackTrace) {
      _options.log(
        SentryLevel.error,
        'WebDartSentryTransport: failed to send envelope',
        exception: exception,
        stackTrace: stackTrace,
      );
      return SentryId.empty();
    }
  }
}

/// Wraps the root widget in [SentryWidget] when crash reporting is active;
/// returns [child] untouched otherwise, so an unconfigured build has no
/// Sentry widget in its tree.
Widget wrapWithSentry(Widget child) =>
    AppConfig.hasSentry ? SentryWidget(child: child) : child;

/// [SentryNavigatorObserver]'s `routeNameExtractor` (KTD4). Extracted as a
/// standalone top-level function -- rather than inlined in
/// [sentryNavigatorObservers] -- so it can be unit-tested directly: under
/// `flutter test`, [AppConfig.hasSentry] is always false (it is a compile-time
/// `const`), so the closure passed to `SentryNavigatorObserver` in
/// [sentryNavigatorObservers] never runs in that process and would otherwise
/// be untestable.
///
/// This extractor is required, not merely defense in depth: while tracing is
/// on, `SentryTracer.traceContext()` reads the transaction name directly off
/// the live `SentryTracer` (built from the observer's route name) to populate
/// the trace's Dynamic Sampling Context, which rides along on both the
/// outgoing Sentry envelope header and the `baggage` header sent to Supabase.
/// That DSC is assembled before an event ever reaches
/// [scrubTransaction]/[scrubEvent] as `beforeSend*` callbacks, so
/// [scrub.dart]'s scrubbers -- the enforcement point for every event field --
/// never see it and cannot stop the raw route name from leaving the device.
/// Routing [settings] through [scrubRouteName] here scrubs the name at the
/// one point upstream of that leak, closing it for good. The returned
/// [RouteSettings] carries only the scrubbed name -- `arguments` is dropped
/// unconditionally, same as the navigation-breadcrumb handling above (KTD1):
/// a scalar argument has no keys for a deny-list check to find.
RouteSettings? sentryRouteNameExtractor(RouteSettings? settings) =>
    settings == null
    ? null
    : RouteSettings(name: scrubRouteName(settings.name));

/// The [NavigatorObserver] list for `MaterialApp.navigatorObservers` (U2;
/// R1, R3, R4, R5, R13). Empty when Sentry is unconfigured, so an
/// unconfigured build installs no observer — same gate as [wrapWithSentry].
///
/// `setRouteNameAsTransaction: true` puts the current screen's (scrubbed —
/// KTD4) name on `event.transaction`; `enableAutoTransactions: true` is
/// inert while `AppConfig.sentryTracesSampleRate` is null (U4) and starts
/// producing route transactions only once an operator opts into tracing.
/// [sentryRouteNameExtractor] closes the Dynamic Sampling Context leak
/// documented on that function.
List<NavigatorObserver> sentryNavigatorObservers() => AppConfig.hasSentry
    ? [
        SentryNavigatorObserver(
          enableAutoTransactions: true,
          setRouteNameAsTransaction: true,
          routeNameExtractor: sentryRouteNameExtractor,
        ),
      ]
    : const <NavigatorObserver>[];
