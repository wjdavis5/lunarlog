// U7 (KTD12, R17-R19, AE7): the Sentry privacy floor as pure functions.
//
// Every event test serializes the scrubbed event with `toJson()` and asserts
// the forbidden substrings are absent from the whole payload, not just from
// the field they were planted in: a note that survived by moving somewhere
// unexpected still fails the test.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/scrub.dart';
import 'package:lunarlog/observability/sentry_bootstrap.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _note = 'private note about cramps';
const _sql = "INSERT INTO day_entries (note) VALUES ('$_note')";
const _email = 'kid@example.com';
const _query = 'profile_id=eq.01HZY8PQ9K3M2N4R5T6V7W8X9Y';
const _url = 'https://x.supabase.co/rest/v1/day_entries?$_query';
const _bearer = 'Bearer eyJhbGciOiJIUzI1NiJ9.secret';
const _apikey = 'sb_publishable_abc123';

String _json(SentryEvent event) => jsonEncode(event.toJson());

SentryStackTrace _dataLayerStack() => SentryStackTrace(frames: [
      SentryStackFrame(
        absPath: 'package:lunarlog/data/db/native_db.dart',
        function: 'openEncrypted',
        lineNo: 42,
      ),
      SentryStackFrame(
        absPath: 'package:lunarlog/app_lifecycle.dart',
        function: '_openDatabase',
      ),
    ]);

SentryEvent _fullEvent() => SentryEvent(
      logger: 'day_entries.note',
      serverName: 'wills-iphone',
      message: SentryMessage('saved note $_note', params: [_note]),
      exceptions: [
        SentryException(
          type: 'SqliteException',
          value: 'SqliteException(19): constraint failed, $_sql',
          stackTrace: _dataLayerStack(),
        ),
      ],
      // ignore: deprecated_member_use
      extra: {'note': _note, 'harmless': 'x'},
      tags: {'note': _note, 'environment': 'development'},
      user: SentryUser(id: 'user-1', email: _email),
      contexts: Contexts(
        device: SentryDevice(name: 'Wills iPhone', model: 'iPhone15,2'),
        operatingSystem: SentryOperatingSystem(name: 'iOS', version: '18.0'),
        runtimes: [SentryRuntime(name: 'Dart', version: '3.13')],
        app: SentryApp(name: 'lunarlog', version: '1.0.0', build: '1'),
      )..['profile'] = {'display_name': 'Piper', 'id': 'p1'},
      request: SentryRequest(
        url: _url,
        method: 'POST',
        queryString: _query,
        headers: {'Authorization': _bearer, 'apikey': _apikey},
        data: {'note': _note, 'local_date': '2026-09-02'},
      ),
      breadcrumbs: [
        Breadcrumb(category: 'navigation', data: {'to': '/entry/2026-09-02'}),
        Breadcrumb(category: 'ui.click', data: {'email': _email}),
      ],
    );

void main() {
  group('scrubEvent', () {
    test('AE7: SqliteException with SQL + note becomes the type name only',
        () {
      final out = scrubEvent(SentryEvent(exceptions: [
        SentryException(
          type: 'SqliteException',
          value: 'SqliteException(19): constraint failed, $_sql',
          stackTrace: _dataLayerStack(),
        ),
      ]))!;
      final ex = out.exceptions!.single;
      expect(ex.type, 'SqliteException');
      expect(ex.value, 'SqliteException');
      expect(ex.stackTrace, isNotNull, reason: 'stack survives (AE7)');
      expect(ex.stackTrace!.frames, hasLength(2));
      final json = _json(out);
      expect(json, isNot(contains(_note)));
      expect(json, isNot(contains('INSERT INTO')));
      expect(json, isNot(contains('day_entries')));
    });

    test('PostgrestException and AuthException reduce to their type names',
        () {
      final out = scrubEvent(SentryEvent(exceptions: [
        SentryException(
          type: 'PostgrestException',
          value: 'details: row note=$_note',
        ),
        SentryException(
          type: 'AuthException',
          value: 'Invalid login for $_email',
        ),
      ]))!;
      expect(out.exceptions!.map((e) => e.value),
          ['PostgrestException', 'AuthException']);
      final json = _json(out);
      expect(json, isNot(contains(_note)));
      expect(json, isNot(contains(_email)));
    });

    test('an exception raised from lib/data is reduced even with a neutral '
        'type name', () {
      final out = scrubEvent(SentryEvent(exceptions: [
        SentryException(
          type: 'StateError',
          value: 'Bad state: $_note',
          stackTrace: _dataLayerStack(),
        ),
      ]))!;
      expect(out.exceptions!.single.value, 'StateError');
      expect(_json(out), isNot(contains(_note)));
    });

    test('an exception from outside lib/data keeps its message', () {
      final out = scrubEvent(SentryEvent(exceptions: [
        SentryException(
          type: 'FlutterError',
          value: 'RenderFlex overflowed by 12 pixels',
          stackTrace: SentryStackTrace(frames: [
            SentryStackFrame(absPath: 'package:flutter/src/rendering/flex.dart'),
          ]),
        ),
      ]))!;
      expect(out.exceptions!.single.value,
          'RenderFlex overflowed by 12 pixels');
    });

    test('request keeps the path, loses query, headers, and data', () {
      final out = scrubEvent(SentryEvent(
        request: SentryRequest(
          url: _url,
          method: 'POST',
          queryString: _query,
          headers: {'Authorization': _bearer, 'apikey': _apikey},
          data: {'note': _note},
        ),
      ))!;
      final request = out.request!;
      expect(request.url, 'https://x.supabase.co/rest/v1/day_entries');
      expect(request.method, 'POST');
      expect(request.headers, isEmpty);
      expect(request.data, isNull);
      expect(request.queryString, isNull);
      final json = _json(out);
      expect(json, isNot(contains(_query)));
      expect(json, isNot(contains('01HZY8')));
      expect(json, isNot(contains(_bearer)));
      expect(json, isNot(contains(_apikey)));
      expect(json, isNot(contains('Authorization')));
      expect(json, isNot(contains('apikey')));
      expect(json, isNot(contains(_note)));
    });

    test('extra, device name, and custom contexts go; os/runtime/app.version '
        'survive', () {
      final out = scrubEvent(_fullEvent())!;
      // ignore: deprecated_member_use
      expect(out.extra, isNull);
      expect(out.contexts.device, isNull);
      expect(out.contexts['profile'], isNull);
      expect(out.contexts.operatingSystem?.name, 'iOS');
      expect(out.contexts.operatingSystem?.version, '18.0');
      expect(out.contexts.runtimes.single.name, 'Dart');
      expect(out.contexts.app?.version, '1.0.0');
      expect(out.contexts.app?.name, isNull);
      final json = _json(out);
      expect(json, isNot(contains('Wills iPhone')));
      expect(json, isNot(contains('iPhone15,2')));
      expect(json, isNot(contains('Piper')));
      expect(json, isNot(contains('display_name')));
      expect(json, isNot(contains('wills-iphone')));
      expect(json, contains('"os"'));
      expect(json, contains('"runtime"'));
      expect(json, contains('"1.0.0"'));
    });

    test('user is null even when set upstream', () {
      final out = scrubEvent(_fullEvent())!;
      expect(out.user, isNull);
      final json = _json(out);
      expect(json, isNot(contains(_email)));
      expect(json, isNot(contains('user-1')));
    });

    test('message and logger carrying deny-listed keys are scrubbed', () {
      final out = scrubEvent(_fullEvent())!;
      expect(out.logger, isNull);
      expect(out.message?.params, isNull);
      final json = _json(out);
      expect(json, isNot(contains(_note)));
      expect(json, isNot(contains('day_entries.note')));
    });

    test('a message without deny-listed content survives, params dropped', () {
      final out = scrubEvent(SentryEvent(
        logger: 'startup',
        message: SentryMessage('database opened in %d ms', params: [12]),
      ))!;
      expect(out.logger, 'startup');
      expect(out.message?.formatted, 'database opened in %d ms');
      expect(out.message?.params, isNull);
    });

    test('U6/KTD7: extra carrying user_metadata is removed', () {
      final out = scrubEvent(SentryEvent(
        // ignore: deprecated_member_use
        extra: {
          'user_metadata': {'full_name': 'Piper Davis', 'picture': 'https://p'},
          'harmless': 'x',
        },
      ))!;
      // ignore: deprecated_member_use
      expect(out.extra, isNull);
      final json = _json(out);
      expect(json, isNot(contains('user_metadata')));
      expect(json, isNot(contains('Piper Davis')));
      expect(json, isNot(contains('harmless')));
    });

    test('U6/KTD7: the bare words user, name, and session do not scrub a '
        'message', () {
      const text = 'session refresh failed: user name lookup timed out';
      final out = scrubEvent(SentryEvent(
        logger: 'auth.session',
        message: SentryMessage(text),
      ))!;
      expect(out.message?.formatted, text);
      expect(out.logger, 'auth.session');
    });

    test('U6/KTD7: a message mentioning id_token or refresh_token is '
        'scrubbed', () {
      for (final text in [
        'id_token expired',
        'refreshToken rotated',
        'auth.nonce mismatch',
      ]) {
        final out = scrubEvent(SentryEvent(message: SentryMessage(text)))!;
        expect(out.message?.formatted, '[scrubbed]', reason: text);
      }
    });

    test('U6/KTD7: GoogleSignInException reduces to its type name', () {
      final out = scrubEvent(SentryEvent(exceptions: [
        SentryException(
          type: 'GoogleSignInException',
          value: 'GoogleSignInException(code: canceled, account $_email)',
          stackTrace: SentryStackTrace(frames: [
            SentryStackFrame(absPath: 'package:lunarlog/ui/sign_in.dart'),
          ]),
        ),
      ]))!;
      final ex = out.exceptions!.single;
      expect(ex.type, 'GoogleSignInException');
      expect(ex.value, 'GoogleSignInException');
      expect(ex.stackTrace, isNotNull);
      expect(_json(out), isNot(contains(_email)));
    });

    test('event tags lose deny-listed keys but keep the rest', () {
      final out = scrubEvent(_fullEvent())!;
      expect(out.tags, {'environment': 'development'});
    });

    test('attached breadcrumbs are re-scrubbed', () {
      final out = scrubEvent(_fullEvent())!;
      expect(out.breadcrumbs, hasLength(1));
      expect(out.breadcrumbs!.single.category, 'navigation');
      // U1: an unregistered, path-shaped `to` becomes 'unknown' rather than
      // being dropped outright — the navigation shape survives.
      expect(out.breadcrumbs!.single.data, {'state': 'unknown', 'to': 'unknown'});
      expect(_json(out), isNot(contains(_email)));
    });

    test('U1/KTD4: event.transaction is scrubbed through scrubRouteName', () {
      final registered = scrubEvent(SentryEvent(transaction: 'SettingsScreen'))!;
      expect(registered.transaction, 'SettingsScreen');

      final pathShaped =
          scrubEvent(SentryEvent(transaction: '/profiles/8f2c'))!;
      expect(pathShaped.transaction, 'unknown');

      final nullTransaction = scrubEvent(SentryEvent(transaction: null))!;
      expect(nullTransaction.transaction, isNull);
    });

    test('U1: contexts.app is reduced to version even when it carries '
        'view_names (FlutterEnricherEventProcessor output)', () {
      final out = scrubEvent(SentryEvent(
        contexts: Contexts(
          app: SentryApp(
            version: '1.0.0',
            viewNames: ['SettingsScreen', 'ProfileDetailScreen'],
          ),
        ),
      ))!;
      final json = _json(out);
      expect(json, isNot(contains('view_names')));
      expect(json, isNot(contains('ProfileDetailScreen')));
      expect(out.contexts.app?.version, '1.0.0');
      expect(out.contexts.app?.viewNames, isNull);
    });

    test('the whole serialized full event carries none of the planted values',
        () {
      final json = _json(scrubEvent(_fullEvent())!);
      for (final forbidden in [
        _note,
        _email,
        _query,
        _bearer,
        _apikey,
        'INSERT INTO',
        'Wills iPhone',
        'Piper',
        'user-1',
        'wills-iphone',
        '/entry/2026-09-02',
      ]) {
        expect(json, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('scrubBreadcrumb', () {
    test('null in, null out', () {
      expect(scrubBreadcrumb(null), isNull);
    });

    // U1/AE1: a navigation breadcrumb's state/from/to survive verbatim when
    // they are registered, well-shaped route names.
    test('AE1: navigation breadcrumb keeps state/from/to verbatim when '
        'registered', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {
          'state': 'didPush',
          'from': 'ProfilePickerScreen',
          'to': 'SettingsScreen',
        },
      ))!;
      expect(out.category, 'navigation');
      expect(out.data, {
        'state': 'didPush',
        'from': 'ProfilePickerScreen',
        'to': 'SettingsScreen',
      });
    });

    // U1/AE2: the single most important test in this plan. `to_arguments`
    // arrives as a scalar string (RouteObserverBreadcrumb._formatArgs on a
    // non-map argument) that containsDenyListedKey cannot see inside. The
    // rebuild must drop the whole field regardless, not scan its value.
    test('AE2: to_arguments as a scalar string carrying a profile id and a '
        'date never survives, even though no deny-list key check can see '
        'inside it', () {
      const leaking =
          '{profile: 8f2c-4a1b, local_date: 2026-09-06}';
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {
          'state': 'didPush',
          'from': 'ProfilePickerScreen',
          'to': 'ProfileDetailScreen',
          'to_arguments': leaking,
        },
      ))!;
      expect(out.data!.keys.toSet(), {'state', 'from', 'to'});
      final json = jsonEncode(out.toJson());
      expect(json, isNot(contains('local_date')));
      expect(json, isNot(contains('8f2c-4a1b')));
    });

    test('AE2: from_arguments as a scalar string never survives', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {
          'state': 'didPush',
          'from': 'ProfileDetailScreen',
          'from_arguments': '{note: private thoughts, local_date: 2026-01-01}',
          'to': 'SettingsScreen',
        },
      ))!;
      expect(out.data!.keys.toSet(), {'state', 'from', 'to'});
      final json = jsonEncode(out.toJson());
      expect(json, isNot(contains('private thoughts')));
      expect(json, isNot(contains('local_date')));
    });

    test('AE2: an additionalInfoProvider-style nested data map carrying a '
        'note never survives — caught by containsDenyListedKey before the '
        'navigation rebuild even runs, so the whole breadcrumb is dropped',
        () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {
          'state': 'didPush',
          'to': 'SettingsScreen',
          'data': {'note': 'private note'},
        },
      ));
      expect(out, isNull);
    });

    // U1/AE2b: a MAP argument is the branch containsDenyListedKey does
    // reach — it drops the whole breadcrumb via the early return, before
    // the navigation rebuild ever runs.
    test('AE2b: to_arguments as a map carrying local_date drops the whole '
        'breadcrumb via containsDenyListedKey', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {
          'state': 'didPush',
          'to': 'ProfileDetailScreen',
          'to_arguments': {'local_date': '2026-01-01'},
        },
      ));
      expect(out, isNull);
    });

    // U1/AE3: an unregistered, path-shaped route name becomes 'unknown'.
    test('AE3: a path-shaped route name becomes unknown', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {'to': '/profiles/8f2c-4a1b'},
      ))!;
      expect(out.data!['to'], 'unknown');
    });

    test('an unregistered route name that matches the shape is kept '
        'verbatim', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {'to': 'SomeThirdPartyRoute'},
      ))!;
      expect(out.data!['to'], 'SomeThirdPartyRoute');
    });

    test('a shape-legal but deny-listed route name becomes unknown', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {'to': 'DisplayName'},
      ))!;
      expect(out.data!['to'], 'unknown');
    });

    test('a null to yields no to key, not a present unknown key', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {'state': 'didPush', 'from': 'SettingsScreen'},
      ))!;
      expect(out.data!.containsKey('to'), isFalse);
    });

    test('an unrecognized state becomes unknown', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'navigation',
        data: {'state': 'somethingElse', 'to': 'SettingsScreen'},
      ))!;
      expect(out.data!['state'], 'unknown');
    });

    test('a navigation breadcrumb with null data yields null data', () {
      final out = scrubBreadcrumb(Breadcrumb(category: 'navigation'))!;
      expect(out.data, isNull);
    });

    test('breadcrumb message mentioning a deny-listed key is scrubbed, not '
        'passed through raw', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'console',
        message: "DatabaseException: UNIQUE constraint failed: "
            "day_entries.note ($_note)",
      ))!;
      expect(out.message, '[scrubbed]');
      expect(jsonEncode(out.toJson()), isNot(contains(_note)));
    });

    test('breadcrumb message with nothing deny-listed passes through', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'console',
        message: 'database opened in 12 ms',
      ))!;
      expect(out.message, 'database opened in 12 ms');
    });

    test('http breadcrumb URL is truncated at ? and query fields dropped', () {
      final out = scrubBreadcrumb(Breadcrumb.http(
        url: Uri.parse(_url),
        method: 'GET',
        statusCode: 200,
        httpQuery: _query,
        httpFragment: 'frag',
      ))!;
      expect(out.data!['url'], 'https://x.supabase.co/rest/v1/day_entries');
      expect(out.data!['method'], 'GET');
      expect(out.data!['status_code'], 200);
      expect(out.data!.containsKey('http.query'), isFalse);
      expect(out.data!.containsKey('http.fragment'), isFalse);
      expect(jsonEncode(out.toJson()), isNot(contains('01HZY8')));
    });

    test('breadcrumb whose data contains email is dropped', () {
      expect(
        scrubBreadcrumb(
            Breadcrumb(category: 'auth', data: {'email': _email})),
        isNull,
      );
    });

    test('breadcrumb whose data contains record is dropped', () {
      expect(
        scrubBreadcrumb(
            Breadcrumb(category: 'sync', data: {'record': {'id': 1}})),
        isNull,
      );
    });

    test('deny-listed keys are found at any depth and in either case', () {
      for (final key in [
        'note',
        'tags',
        'display_name',
        'displayName',
        'local_date',
        'localDate',
        'old_record',
        'oldRecord',
        'p_day_entries',
        'pDayEntries',
        'p_profiles',
        'Authorization',
        'authorization',
        'apikey',
        'APIKEY',
      ]) {
        expect(
          scrubBreadcrumb(Breadcrumb(category: 'x', data: {
            'outer': {
              'list': [
                {'inner': {key: 'v'}}
              ]
            }
          })),
          isNull,
          reason: key,
        );
      }
    });

    test('U6/KTD7: identity payload keys drop the breadcrumb at any depth',
        () {
      for (final key in [
        'identities',
        'identity_data',
        'idToken',
        'id_token',
        'identity_token',
        'access_token',
        'accessToken',
        'refresh_token',
        'provider_token',
        'provider_refresh_token',
        'authorization_code',
        'serverAuthCode',
        'server_auth_code',
        'token_hash',
        'code_verifier',
        'nonce',
        'full_name',
        'given_name',
        'family_name',
        'picture',
        'avatar_url',
        'photo_url',
        'hd',
        'user_metadata',
        'userMetadata',
      ]) {
        expect(
          scrubBreadcrumb(Breadcrumb(category: 'auth', data: {key: 'v'})),
          isNull,
          reason: 'top-level $key',
        );
        expect(
          scrubBreadcrumb(Breadcrumb(category: 'auth', data: {
            'session': {
              'user': {key: 'v'}
            }
          })),
          isNull,
          reason: 'nested $key',
        );
      }
    });

    test('U6/KTD7: an auth breadcrumb with only allowed keys passes', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'auth',
        message: 'sign-in finished',
        data: {'provider': 'google', 'code': 'canceled', 'user': 'present'},
      ))!;
      expect(out.category, 'auth');
      expect(out.data,
          {'provider': 'google', 'code': 'canceled', 'user': 'present'});
    });

    test('an ordinary breadcrumb passes through unchanged', () {
      final out = scrubBreadcrumb(Breadcrumb(
        category: 'app.lifecycle',
        message: 'resumed',
        data: {'state': 'resumed'},
      ))!;
      expect(out.category, 'app.lifecycle');
      expect(out.data, {'state': 'resumed'});
    });
  });

  group('sentryDenyListedKeys', () {
    test('matches both cases of every documented key', () {
      expect(isDenyListedKey('display_name'), isTrue);
      expect(isDenyListedKey('displayName'), isTrue);
      expect(isDenyListedKey('p_day_entries'), isTrue);
      expect(isDenyListedKey('pDayEntries'), isTrue);
      expect(isDenyListedKey('Authorization'), isTrue);
      expect(isDenyListedKey('status_code'), isFalse);
      expect(isDenyListedKey('url'), isFalse);
      for (final key in [
        'identities',
        'identityData',
        'id_token',
        'idToken',
        'refresh_token',
        'providerRefreshToken',
        'authorization_code',
        'token_hash',
        'code_verifier',
        'nonce',
        'fullName',
        'avatar_url',
        'hd',
        'user_metadata',
      ]) {
        expect(isDenyListedKey(key), isTrue, reason: key);
      }
      // KTD7: bare words stay out so ordinary messages are not scrubbed.
      for (final word in ['name', 'token', 'user', 'sub', 'session', 'id']) {
        expect(isDenyListedKey(word), isFalse, reason: word);
      }
    });
  });

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
      expect(o.tracesSampleRate, anyOf(isNull, 0.0));
      // ignore: experimental_member_use
      expect(o.profilesSampleRate, anyOf(isNull, 0.0));
      expect(o.sampleRate, 1.0);
      expect(o.enableAutoSessionTracking, isTrue);
      expect(o.maxRequestBodySize, MaxRequestBodySize.never);
      expect(o.beforeSend, isNotNull);
      expect(o.beforeBreadcrumb, isNotNull);

      // The wired callbacks are the scrubbers.
      final scrubbed = await o.beforeSend!(_fullEvent(), Hint());
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
}
