// Issue #6, U4: the bounded breadcrumb ring feeding feedback diagnostics.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';

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
}
