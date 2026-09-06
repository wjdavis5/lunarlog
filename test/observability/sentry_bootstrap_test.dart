// U2/U3 (KTD4, KTD6; R1, R3-R8, R13): Sentry bootstrap wiring — the
// `runWithSentry`/`configureSentryOptions` groups moved here verbatim from
// `scrub_test.dart` (this surface has grown enough to own a file), plus the
// navigator-observer and native-capture-option coverage U2/U3 add.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/sentry_bootstrap.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _note = 'private note about cramps';
const _email = 'kid@example.com';

String _json(SentryEvent event) => jsonEncode(event.toJson());

/// Proves `beforeBreadcrumb`'s fail-closed wrapping covers the whole body,
/// not just the call into `scrubBreadcrumb` -- the tee's own `log.record`
/// call runs inside the same try block and must drop the breadcrumb, not
/// propagate, when it throws.
class _ThrowingBreadcrumbLog extends BreadcrumbLog {
  @override
  void record(String category, String name) =>
      throw StateError('boom');
}

void main() {
  group('runWithSentry', () {
    test('empty DSN runs the app without calling init', () async {
      var initCalls = 0;
      var appRuns = 0;
      await runWithSentry(
        dsn: '',
        init: (config, {appRunner}) async {
          initCalls++;
        },
        appRunner: () async => appRuns++,
      );
      expect(initCalls, 0);
      expect(appRuns, 1);
    });

    test('with a DSN, init is called with the KTD12 privacy floor and the '
        'app runner is handed through', () async {
      const dsn = 'https://public@o0.ingest.sentry.io/1';
      SentryFlutterOptions? seen;
      AppRunner? seenRunner;
      var appRuns = 0;
      await runWithSentry(
        dsn: dsn,
        init: (config, {appRunner}) async {
          final options = SentryFlutterOptions(dsn: dsn);
          await config(options);
          seen = options;
          seenRunner = appRunner;
        },
        appRunner: () async => appRuns++,
      );
      expect(appRuns, 0, reason: 'runWithSentry hands the runner to init');
      expect(seenRunner, isNotNull);
      await seenRunner!();
      expect(appRuns, 1);

      final o = seen!;
      expect(o.dsn, dsn);
      expect(o.environment, anyOf('production', 'development'));
      expect(o.sendDefaultPii, isFalse);
      expect(o.attachScreenshot, isFalse);
      // ignore: experimental_member_use
      expect(o.attachViewHierarchy, isFalse);
      expect(o.replay.sessionSampleRate, anyOf(isNull, 0.0));
      expect(o.replay.onErrorSampleRate, anyOf(isNull, 0.0));
      expect(o.enableUserInteractionBreadcrumbs, isFalse);
      expect(o.enableUserInteractionTracing, isFalse);
      // runWithSentry wires the real AppConfig.sentryTracesSampleRate
      // (U4), so this legitimately reflects whatever dart-define this
      // very test run was invoked with -- assert only that it stays in
      // Sentry's valid [0, 1] range, not a specific value.
      expect(o.tracesSampleRate, anyOf(isNull, inInclusiveRange(0.0, 1.0)));
      // ignore: experimental_member_use
      expect(o.profilesSampleRate, anyOf(isNull, 0.0));
      expect(o.sampleRate, 1.0);
      expect(o.enableAutoSessionTracking, isTrue);
      expect(o.maxRequestBodySize, MaxRequestBodySize.never);
      expect(o.beforeSend, isNotNull);
      expect(o.beforeBreadcrumb, isNotNull);

      // The wired callbacks are the scrubbers.
      final scrubbed = await o.beforeSend!(
        SentryEvent(tags: {'note': _note}, user: SentryUser(id: 'u1')),
        Hint(),
      );
      expect(scrubbed!.user, isNull);
      expect(_json(scrubbed), isNot(contains(_note)));
      expect(
        o.beforeBreadcrumb!(
            Breadcrumb(category: 'x', data: {'email': _email}), Hint()),
        isNull,
      );
    });
  });

  group('configureSentryOptions breadcrumb tee (Issue #6, U4; KTD9)', () {
    test('a breadcrumb that survives scrubBreadcrumb is teed into the injected log', () {
      final log = BreadcrumbLog();
      final options = SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!, breadcrumbLog: log);

      options.beforeBreadcrumb!(
        Breadcrumb(category: 'navigation', message: 'overview'),
        Hint(),
      );

      expect(log.snapshot(), ['navigation: overview']);
    });

    test('a breadcrumb scrubBreadcrumb drops is not teed', () {
      final log = BreadcrumbLog();
      final options = SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!, breadcrumbLog: log);

      options.beforeBreadcrumb!(
        Breadcrumb(category: 'x', data: {'email': _email}),
        Hint(),
      );

      expect(log.snapshot(), isEmpty);
    });

    test('AE10 (unit half): a data-only navigation breadcrumb lands as '
        '"navigation: SettingsScreen"', () {
      final log = BreadcrumbLog();
      final options = SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!, breadcrumbLog: log);

      options.beforeBreadcrumb!(
        Breadcrumb(category: 'navigation', data: {
          'state': 'didPush',
          'from': 'ProfilePickerScreen',
          'to': 'SettingsScreen',
        }),
        Hint(),
      );

      expect(log.snapshot(), ['navigation: SettingsScreen']);
    });
  });

  group('fail-closed beforeSend*/beforeBreadcrumb (code review; the SDK '
      'forwards the raw event when a callback throws)', () {
    test('beforeBreadcrumb returns null, not the scrubbed breadcrumb, when '
        'the tee itself throws', () {
      final options =
          SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options,
          dsn: options.dsn!, breadcrumbLog: _ThrowingBreadcrumbLog());

      final result = options.beforeBreadcrumb!(
        Breadcrumb(category: 'navigation', message: 'overview'),
        Hint(),
      );

      expect(result, isNull);
    });

    test('beforeSend on a well-formed event still returns the scrubbed '
        'event (the try/catch does not swallow the success path)', () {
      final options =
          SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!);

      final result =
          options.beforeSend!(SentryEvent(message: SentryMessage('ok')), Hint());
      expect(result, isA<SentryEvent>());
    });
  });

  group('sentryNavigatorObservers (U2; R13, AE4)', () {
    test('AE4: empty when unconfigured (the default under flutter test, no '
        'SENTRY_DSN)', () {
      expect(sentryNavigatorObservers(), isEmpty);
    });
  });

  group('configureSentryOptions tracing (U4; R9, R10, R14, AE5)', () {
    test('AE5: with no tracesSampleRate passed (configureSentryOptions '
        "defaults to off, decoupled from this test run's real dart-define), "
        'tracesSampleRate is null and isTracingEnabled() is false', () {
      final options =
          SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!);

      expect(options.tracesSampleRate, isNull);
      expect(options.isTracingEnabled(), isFalse);
    });

    test('an explicit tracesSampleRate is set verbatim, whatever this test '
        "run's real dart-define was", () {
      final options =
          SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!, tracesSampleRate: 0.2);

      expect(options.tracesSampleRate, 0.2);
      expect(options.isTracingEnabled(), isTrue);
    });

    test('beforeSendTransaction is wired to scrubTransaction', () {
      final options =
          SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!);

      expect(options.beforeSendTransaction, isNotNull);
    });
  });

  group('configureSentryOptions native-capture options (U3; R6, R7, R8, '
      'AE7)', () {
    late SentryFlutterOptions options;

    setUp(() {
      options = SentryFlutterOptions(dsn: 'https://public@o0.ingest.sentry.io/1');
      configureSentryOptions(options, dsn: options.dsn!);
    });

    test('every native-capture option holds its intended explicit value, '
        'not an SDK default', () {
      expect(options.anrEnabled, isTrue);
      expect(options.enableNativeCrashHandling, isTrue);
      expect(options.enableNdkScopeSync, isTrue);
      expect(options.enableAppHangTracking, isTrue);
      expect(options.enableWatchdogTerminationTracking, isTrue);
      expect(options.enableAutoNativeBreadcrumbs, isTrue);
      // The one option pinned false rather than turned on (KTD6): a
      // tombstone is assembled natively, outside this scrubber, from a
      // process holding decrypted health strings in memory.
      expect(options.enableTombstone, isFalse);
      // Pinned false, not left at the SDK default of true (code review):
      // print-breadcrumb text only ever reaches scrubBreadcrumb's
      // deny-listed-word scan, which cannot see an arbitrary sensitive
      // *value* a caller printed (see app_lifecycle.dart's reset-failure
      // debugPrint).
      expect(options.enablePrintBreadcrumbs, isFalse);
    });

    test('maxBreadcrumbs stays at the SDK default of 100, not reduced -- a '
        'smaller ring would buy less pre-crash history exactly where U1/U2 '
        'add triage value', () {
      expect(options.maxBreadcrumbs, 100);
    });

    test('the five Flutter-side breadcrumb toggles stay at their mobile '
        'defaults (all false) -- flipping one without '
        'enableAutoNativeBreadcrumbs would double-record', () {
      expect(options.enableAppLifecycleBreadcrumbs, isFalse);
      expect(options.enableWindowMetricBreadcrumbs, isFalse);
      expect(options.enableBrightnessChangeBreadcrumbs, isFalse);
      expect(options.enableTextScaleChangeBreadcrumbs, isFalse);
      expect(options.enableMemoryPressureBreadcrumbs, isFalse);
    });

    test('anrTimeoutInterval is untouched at the SDK default of 5s', () {
      expect(options.anrTimeoutInterval, const Duration(seconds: 5));
    });

    test('the KTD12 privacy-floor options this unit does not touch keep '
        'their values (a regression guard alongside the new options in the '
        'same cascade)', () {
      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      // ignore: experimental_member_use
      expect(options.attachViewHierarchy, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.enableUserInteractionTracing, isFalse);
      expect(options.sampleRate, 1.0);
      // ignore: experimental_member_use
      expect(options.profilesSampleRate, anyOf(isNull, 0.0));
      expect(options.enableAutoSessionTracking, isTrue);
      expect(options.maxRequestBodySize, MaxRequestBodySize.never);
      expect(options.replay.sessionSampleRate, anyOf(isNull, 0.0));
      expect(options.replay.onErrorSampleRate, anyOf(isNull, 0.0));
    });
  });
}
