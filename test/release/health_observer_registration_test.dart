/// Issue #1212: the iOS background-import trigger's observer registration
/// is idempotent per session and the queries are stopped on unbind.
///
/// `bind` arrives on every health write pass — `HealthFlowWriteService`
/// re-asserts the native binding mirror per pass
/// (`health_flow_write_service.dart`'s "every pass re-asserts the same
/// binding") — so the Swift handler's `registerBackgroundImportTriggerIfBound`
/// runs that often too. Before #1212 every call executed two brand-new
/// `HKObserverQuery` objects, kept no reference, and stopped nothing:
/// after N write passes one HealthKit change fired 2N+2 handlers, each a
/// full background import pass, and `unbind` only disabled delivery (its
/// own comment admitted the queries stayed registered forever).
///
/// CI cannot run HealthKit, so the invariant is pinned the way
/// `health_deviation_read_types_test.dart` pins its cross-language
/// contract: parsing `ios/Runner/AppDelegate.swift` (line comments
/// stripped, blocks brace-matched) and asserting the registry, the
/// already-registered skip before the single `store.execute`, and the
/// stop-on-unbind shapes. The on-device half of the check (that a re-bind
/// really registers no second observer and an unbind really stops the
/// first ones) is not reproducible under `flutter test` — it stays on the
/// device checklist; this test only pins the source shapes.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _appDelegatePath = 'ios/Runner/AppDelegate.swift';

/// Strips `//` line comments so a commented-out identifier cannot satisfy a
/// parse (mirrors `health_deviation_read_types_test.dart`'s helper).
String _stripLineComments(String text) => text
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index >= 0 ? line.substring(0, index) : line;
    })
    .join('\n');

/// Extracts one declaration's block by brace matching: from the first
/// occurrence of [startPattern] to the closing brace of the `{` that
/// follows it. Throws when the pattern is gone (the structure this test
/// pins was renamed — update the test, don't loosen it). The blocks this
/// test extracts contain no brace characters inside string literals.
String _block(String source, RegExp startPattern) {
  final start = startPattern.firstMatch(source);
  if (start == null) {
    throw StateError('expected block not found: $startPattern');
  }
  final open = source.indexOf('{', start.start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start.start, i + 1);
    }
  }
  throw StateError('unbalanced braces after: $startPattern');
}

/// The `case "bind":` block: the source between that case label and the
/// next one (a case body is statements, not a braced block).
String _caseBlock(String source, String label, String nextLabel) {
  final start = source.indexOf(label);
  expect(start, isNonNegative, reason: '$label was not found');
  final end = source.indexOf(nextLabel, start);
  expect(end, greaterThan(start), reason: '$nextLabel was not found');
  return source.substring(start, end);
}

void main() {
  group('Issue #1212: the observer queries are registered exactly once', () {
    late String swift;
    late String raw;

    setUpAll(() {
      raw = readRepoFile(_appDelegatePath);
      swift = _stripLineComments(raw);
    });

    test('registration keeps its queries in a static per-type registry',
        () {
      expect(
        swift,
        contains(
          'static var registeredObserverQueries: '
          '[HKCategoryType: HKObserverQuery]',
        ),
      );
    });

    test('a re-bind cannot execute a second query (registration is '
        'idempotent)', () {
      final body = _block(
        swift,
        RegExp(r'static func registerBackgroundImportTriggerIfBound\(\)'),
      );

      // The already-registered skip, before any execute: a re-bind can
      // only reach the re-enable path.
      final skip = body.indexOf('registeredObserverQueries[type] == nil');
      expect(skip, isNonNegative,
          reason: 'the register function never checks the registry');
      final execute = body.indexOf('store.execute(query)');
      expect(execute, greaterThan(skip));

      // Exactly one execute site — the first-registration path. A second
      // one would pile observers up again.
      expect('store.execute('.allMatches(body), hasLength(1));

      // The new query is registered before it runs, so even a synchronous
      // re-entry cannot execute twice.
      final insert = body.indexOf('registeredObserverQueries[type] = query');
      expect(insert, isNonNegative);
      expect(insert, lessThan(execute));

      // The re-enable path shares the one best-effort enable helper.
      expect(
        'enableBackgroundDelivery(for: type)'.allMatches(body),
        hasLength(2),
        reason: 'both the skip path and the first-registration path must '
            '(re-)enable background delivery',
      );
    });

    test('unbind stops the queries and empties the registry', () {
      final body = _block(
        swift,
        RegExp(r'static func disableBackgroundImportTrigger\(\)'),
      );

      expect(
        body,
        contains('registeredObserverQueries.removeValue(forKey: type)'),
      );
      expect(body, contains('store.stop(query)'));
      // Delivery is still disabled alongside the stop.
      expect(body, contains('store.disableBackgroundDelivery(for: type)'));
    });

    test('the pre-#1212 "queries stay registered" comment is gone', () {
      // The old unbind doc claimed the left-behind queries were harmless.
      // They were the bug: live forever, added to on every re-bind.
      expect(raw, isNot(contains('queries stay registered')));
    });

    test('bind still routes through the (now idempotent) register '
        'function', () {
      final body =
          _caseBlock(swift, 'case "bind":', 'case "unbind":');
      expect(body, contains('registerBackgroundImportTriggerIfBound()'));
    });

    test('unbind still routes through the stop-and-disable function', () {
      final body = _caseBlock(
        swift,
        'case "unbind":',
        'case "consumePendingBackgroundImportTrigger":',
      );
      expect(body, contains('disableBackgroundImportTrigger()'));
    });
  });
}
