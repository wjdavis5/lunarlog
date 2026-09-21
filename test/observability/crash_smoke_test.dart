/// Issue #973: the dev-only crash-report smoke trigger's two error paths,
/// run through the `scrub.dart` allowlist the real `beforeSend` hook applies.
///
/// Each probe is invoked through its production capture entry point (with a
/// reporter that captures the thrown pair), the real Sentry SDK converts
/// that `(error, stackTrace)` pair into the event its `beforeSend` hook
/// would receive, and [scrubEvent] — the same function
/// `configureSentryOptions` wires as `beforeSend` — is then applied
/// directly. No global hub, no transport, no network: the assertions are on
/// the scrubbed payload's field *names* and on the specific values that
/// must not survive, exactly the #19 checklist.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/crash_smoke.dart';
import 'package:lunarlog/observability/scrub.dart';
import 'package:lunarlog/ui/settings/crash_smoke_trigger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _healthNote = 'private health note';
const _email = 'kid@example.com';
const _bearer = 'Bearer eyJhbGciOiJIUzI1NiJ9.secret';
const _query = 'profile_id=eq.01HZY8PQ9K3M2N4R5T6V7W8X9Y';

class _NoopTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}

/// Runs [invoke] with a reporter that captures the thrown `(error,
/// stackTrace)` pair, then lets the real SDK convert that pair into the
/// event `beforeSend` receives. Returns the raw (unscrubbed) event.
Future<SentryEvent> _rawEventFrom(
  void Function(CrashSmokeReporter report) invoke,
) async {
  Object? error;
  StackTrace? stackTrace;
  invoke((e, st) {
    error = e;
    stackTrace = st;
  });
  expect(error, isNotNull, reason: 'the probe did not throw');
  expect(stackTrace, isNotNull, reason: 'the probe reported no stack trace');

  final options = SentryOptions(dsn: 'https://public@o0.ingest.sentry.io/1')
    ..transport = _NoopTransport();
  SentryEvent? captured;
  options.beforeSend = (event, hint) {
    captured = event;
    return null;
  };
  final hub = Hub(options);
  await hub.captureException(error!, stackTrace: stackTrace);
  expect(captured, isNotNull, reason: 'beforeSend did not observe an event');
  return captured!;
}

/// Wraps a probe's captured event with the sensitive shape a real crash
/// report can carry — identity, health content in `extra`/`tags`/
/// breadcrumbs, and a request with query, headers, and a body — so
/// [scrubEvent]'s allowlist is exercised against the fields it exists to
/// strip, not just against the exception itself.
SentryEvent _enriched(SentryEvent base) => SentryEvent(
      eventId: base.eventId,
      timestamp: base.timestamp,
      platform: base.platform,
      logger: 'crash_smoke.note',
      message: SentryMessage('saved $_healthNote', params: [_healthNote]),
      exceptions: base.exceptions,
      // ignore: deprecated_member_use
      extra: {'note': _healthNote, 'harmless': 'x'},
      tags: {'note': _healthNote, 'environment': 'development'},
      user: SentryUser(id: 'user-1', email: _email),
      contexts: Contexts(
        device: SentryDevice(name: 'Wills iPhone', model: 'iPhone15,2'),
        operatingSystem: SentryOperatingSystem(name: 'iOS', version: '18.0'),
        runtimes: [SentryRuntime(name: 'Dart', version: '3.13')],
        app: SentryApp(name: 'lunarlog', version: '1.0.0', build: '1'),
      )..['profile'] = {'display_name': 'Piper'},
      request: SentryRequest(
        url: 'https://x.supabase.co/rest/v1/day_entries?$_query',
        method: 'POST',
        queryString: _query,
        headers: {'Authorization': _bearer, 'apikey': 'sb_publishable_abc123'},
        data: {'note': _healthNote, 'local_date': '2026-09-02'},
      ),
      breadcrumbs: [
        Breadcrumb(category: 'navigation', data: {'to': '/entry/2026-09-02'}),
        Breadcrumb(category: 'sync', data: {'note': _healthNote}),
        Breadcrumb.http(
          url: Uri.parse('https://x.supabase.co/rest/v1/rpc/sync_push?foo=bar'),
          method: 'POST',
          statusCode: 200,
        ),
      ],
    );

Future<SentryEvent> _dataProbeRaw() => _rawEventFrom(
      (report) => captureDataLayerCrashSmoke(report: report),
    );

Future<SentryEvent> _uiProbeRaw() => _rawEventFrom(
      (report) => captureUiCrashSmoke(probe: throwUiCrashSmoke, report: report),
    );

void main() {
  group('data-layer probe (#973)', () {
    test('reports a real lib/data exception with a lib/data stack frame',
        () async {
      final raw = await _dataProbeRaw();
      final ex = raw.exceptions!.single;
      expect(ex.type, 'StateError');
      final paths = ex.stackTrace!.frames
          .map((frame) => frame.absPath ?? '')
          .join('\n');
      expect(
        paths,
        contains('lunarlog/data/diagnostics/crash_smoke_probe.dart'),
        reason: 'the scrubber reduces by stack path when the type is neutral',
      );
    });

    test('reduces to its type name: the message does not survive', () async {
      final out = scrubEvent(_enriched(await _dataProbeRaw()))!;
      final ex = out.exceptions!.single;
      expect(ex.type, 'StateError');
      expect(ex.value, 'StateError');
      final json = jsonEncode(out.toJson());
      expect(json, isNot(contains('must be reduced to the type name')));
      expect(json, isNot(contains('crash-report smoke probe')));
    });
  });

  group('UI-layer probe (#973)', () {
    test('keeps its message: FlutterError is the one safe, non-data type',
        () async {
      final out = scrubEvent(_enriched(await _uiProbeRaw()))!;
      final ex = out.exceptions!.single;
      expect(ex.type, 'FlutterError');
      expect(ex.value, contains('UI layer'));
    });
  });

  group('scrubbed payload shape (the #19 checklist)', () {
    test('only contexts.os, contexts.runtime, and contexts.app.version '
        'survive; user and extra are gone', () async {
      final out = scrubEvent(_enriched(await _uiProbeRaw()))!;
      expect(out.contexts.operatingSystem?.name, 'iOS');
      expect(out.contexts.runtimes.single.name, 'Dart');
      expect(out.contexts.app?.version, '1.0.0');
      // Everything else the event carried:
      expect(out.contexts.device, isNull);
      expect(out.contexts['profile'], isNull);
      expect(out.contexts.app?.name, isNull);
      expect(out.contexts.app?.build, isNull);
      expect(out.user, isNull);
      // ignore: deprecated_member_use
      expect(out.extra, isNull);
    });

    test('the request keeps its path and method; query, headers, and body '
        'are gone', () async {
      final out = scrubEvent(_enriched(await _uiProbeRaw()))!;
      final request = out.request!;
      expect(request.url, 'https://x.supabase.co/rest/v1/day_entries');
      expect(request.method, 'POST');
      expect(request.queryString, isNull);
      expect(request.headers, isEmpty);
      expect(request.data, isNull);
    });

    test('breadcrumbs drop health content and truncate HTTP URLs at ?',
        () async {
      final out = scrubEvent(_enriched(await _uiProbeRaw()))!;
      // The `sync` breadcrumb carried a `note` key — dropped wholesale.
      expect(out.breadcrumbs!.map((b) => b.category), isNot(contains('sync')));
      final http =
          out.breadcrumbs!.firstWhere((b) => b.category == 'http');
      expect(http.data!['url'], 'https://x.supabase.co/rest/v1/rpc/sync_push');
      final json = jsonEncode(out.toJson());
      expect(json, isNot(contains('foo=bar')));
    });

    test('the whole serialized payload carries none of the planted values',
        () async {
      for (final raw in [await _dataProbeRaw(), await _uiProbeRaw()]) {
        final json = jsonEncode(scrubEvent(_enriched(raw))!.toJson());
        for (final forbidden in [
          _healthNote,
          _email,
          _query,
          _bearer,
          'sb_publishable_abc123',
          'user-1',
          'Wills iPhone',
          'iPhone15,2',
          'Piper',
          'display_name',
          '/entry/2026-09-02',
        ]) {
          expect(json, isNot(contains(forbidden)), reason: forbidden);
        }
      }
    });

    test('a breadcrumb carrying an HTTP URL with a query string is '
        'truncated at ?', () {
      final out = scrubBreadcrumb(Breadcrumb.http(
        url: Uri.parse('https://x.supabase.co/rest/v1/rpc/sync_push?foo=bar'),
        method: 'POST',
        statusCode: 200,
      ))!;
      expect(out.data!['url'], 'https://x.supabase.co/rest/v1/rpc/sync_push');
      expect(out.data!.containsKey('http.query'), isFalse);
      expect(jsonEncode(out.toJson()), isNot(contains('foo=bar')));
    });
  });
}
