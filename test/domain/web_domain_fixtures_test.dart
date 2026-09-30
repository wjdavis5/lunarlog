/// Parity-fixture pinning for the web domain facade (issue #1251).
///
/// `webapp/test/domain/fixtures.json` is the committed middle between two
/// directions of the same pin:
///
/// * THIS test re-runs every case through `handleFacadeCall` and fails when
///   the Dart domain's output drifts from the committed file — a domain
///   change that moves an output must consciously regenerate the fixtures
///   (`dart run tool/web_domain/generate_fixtures.dart`), which puts the
///   output change in the PR diff.
/// * `webapp/test/domain/parity.test.ts` runs every case through the
///   compiled dart2js module against the same file — so the compiled
///   module and the Dart domain can never disagree silently.
///
/// The comparison is structural (numbers compared numerically, so Dart's
/// `29.0` matches JavaScript's `29` after JSON round-trip; object key order
/// ignored; array order significant).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_domain/facade.dart';

void main() {
  // `flutter test` runs from the package root; the fixtures live next to
  // the Vitest parity suite that consumes the same file.
  final fixturesFile = File('webapp/test/domain/fixtures.json');
  final cases = jsonDecode(fixturesFile.readAsStringSync()) as List<Object?>;

  test('fixture file exists and carries cases', () {
    expect(cases, isNotEmpty);
  });

  for (final raw in cases) {
    final case_ = raw! as Map<String, Object?>;
    final name = case_['name']! as String;
    final method = case_['method']! as String;
    final request = case_['request']! as Map<String, Object?>;
    final expected = case_['expected']! as Map<String, Object?>;

    test('parity: $name', () {
      final actual = handleFacadeCall(method, jsonEncode(request));
      expect(
        deepJsonEquals(jsonDecode(actual), expected),
        isTrue,
        reason:
            'Dart facade output drifted from the committed fixture '
            'for "$name". If the domain change is intentional, regenerate '
            'with: dart run tool/web_domain/generate_fixtures.dart',
      );
    });
  }
}

/// Structural JSON equality: numbers numerically (int/double interchange),
/// maps key-order-insensitive, lists order-significant.
bool deepJsonEquals(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepJsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
