// Issue #6, U4: the bounded breadcrumb ring feeding feedback diagnostics.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('BreadcrumbLog', () {
    test('keeps the newest entries and evicts in insertion order when full', () {
      final log = BreadcrumbLog(capacity: 25);
      for (var i = 0; i < 30; i++) {
        log.record('nav', 'step-$i');
      }
      final snapshot = log.snapshot();
      expect(snapshot.length, 25);
      expect(snapshot.first, 'nav: step-5');
      expect(snapshot.last, 'nav: step-29');
    });

    test('a breadcrumb whose category matches a deny-listed key is not recorded', () {
      final log = BreadcrumbLog();
      log.record('note', 'private detail');
      expect(log.snapshot(), isEmpty);
    });

    test('a breadcrumb whose name matches a deny-listed key is not recorded', () {
      final log = BreadcrumbLog();
      log.record('field', 'email');
      log.record('field', 'access_token');
      expect(log.snapshot(), isEmpty);
    });

    test('a raw DB error whose free text merely mentions a deny-listed key '
        'is not recorded (not just an exact-key match)', () {
      final log = BreadcrumbLog();
      // Shaped like the console breadcrumb sentry_flutter's
      // DebugPrintIntegration builds from
      // `debugPrint('lunarlog reset failed: $error\n$stackTrace')` in
      // release builds: a SQL statement with a bound argument that names a
      // health-log column, nowhere near being itself exactly `note`.
      log.record('console',
          'lunarlog reset failed: SqliteException: near "note": syntax '
          'error, bound arguments: [note=feeling off today]');
      expect(log.snapshot(), isEmpty);
    });

    test('an ordinary breadcrumb is recorded', () {
      final log = BreadcrumbLog();
      log.record('nav', 'overview');
      expect(log.snapshot(), ['nav: overview']);
    });

    test('snapshot returns an unmodifiable list unaffected by later mutation', () {
      final log = BreadcrumbLog();
      log.record('nav', 'overview');
      final snapshot = log.snapshot();
      expect(() => snapshot.add('nav: calendar'), throwsUnsupportedError);

      log.record('nav', 'calendar');
      expect(snapshot, ['nav: overview'],
          reason: 'a prior snapshot must not change when the log gains a new entry');
    });

    test('clear empties the log', () {
      final log = BreadcrumbLog();
      log.record('nav', 'overview');
      log.clear();
      expect(log.snapshot(), isEmpty);
    });
  });

  group('breadcrumbLabel (U1; KTD5)', () {
    test('returns the message when present, ignoring category', () {
      expect(
        breadcrumbLabel(Breadcrumb(category: 'navigation', message: 'hi')),
        'hi',
      );
    });

    test('returns the already-scrubbed to route for a data-only navigation '
        'breadcrumb', () {
      expect(
        breadcrumbLabel(
          Breadcrumb(category: 'navigation', data: {'to': 'SettingsScreen'}),
        ),
        'SettingsScreen',
      );
    });

    test('returns empty string for a data-only breadcrumb of any other '
        'category', () {
      expect(
        breadcrumbLabel(Breadcrumb(category: 'http', data: {'to': 'x'})),
        '',
      );
    });

    test('returns empty string for a navigation breadcrumb with no message '
        'and no to', () {
      expect(
        breadcrumbLabel(
          Breadcrumb(category: 'navigation', data: {'state': 'didPop'}),
        ),
        '',
      );
    });

    test('returns empty string for a breadcrumb with no message and no '
        'data at all', () {
      expect(breadcrumbLabel(Breadcrumb(category: 'console')), '');
    });
  });
}
