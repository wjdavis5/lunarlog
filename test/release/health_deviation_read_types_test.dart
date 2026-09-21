/// Issue #799: the regression guard for the read-only computed-cycle-deviation
/// contract.
///
/// Two languages own the same four Apple types and cannot share code: Dart
/// sends the canonical `HKCategoryTypeIdentifier` **raw-value** strings and
/// the Swift handler resolves them through its own `deviationKinds` table.
/// This test parses that table (never merely `contains`-checks it) and pins
/// it to [HealthDeviationKind] — a rename or a typo on either side fails
/// here rather than shipping a read that silently asks for nothing.
///
/// It also pins the safety property issue #799 exists to preserve: Apple
/// computes these deviations from the user's own data, and App Review 5.1.3
/// forbids writing derived data back, so the four types must be absent from
/// every written/deleted/`toShare` set — read set only, permanently.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';

import 'repo_text_helpers.dart';

const _appDelegatePath = 'ios/Runner/AppDelegate.swift';

/// Strips `//` line comments so a commented-out identifier cannot satisfy a
/// parse (mirrors `health_deletion_types_test.dart`'s helper).
String _stripLineComments(String text) => text
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index >= 0 ? line.substring(0, index) : line;
    })
    .join('\n');

/// The `wire`/`identifier` pairs of the Swift `deviationKinds` table.
List<(String wire, String identifier)> _deviationTable(String source) {
  final start = source.indexOf('static let deviationKinds');
  expect(start, isNonNegative,
      reason: 'deviationKinds was not found in AppDelegate.swift');
  final open = source.indexOf('= [', start);
  expect(open, isNonNegative, reason: 'deviationKinds has no array literal');
  final close = source.indexOf(']', open);
  expect(close, greaterThan(open), reason: 'deviationKinds is unterminated');
  final block = source.substring(open, close);
  final matches = RegExp(
    r'wire:\s*"([^"]+)"\s*,\s*identifier:\s*"([^"]+)"',
  ).allMatches(block);
  return [for (final match in matches) (match.group(1)!, match.group(2)!)];
}

/// The `.caseName` members of a Swift array literal assigned to
/// [declaration].
Set<String> _swiftArrayCases(String source, String declaration) {
  final start = source.indexOf(declaration);
  expect(start, isNonNegative,
      reason: '$declaration was not found in the native source');
  final open = source.indexOf('= [', start);
  expect(open, isNonNegative, reason: '$declaration has no array literal');
  final close = source.indexOf(']', open);
  expect(close, greaterThan(open),
      reason: '$declaration array is unterminated');
  final block = source.substring(open + 2, close);
  return RegExp(r'\.([A-Za-z]\w*)')
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

/// The Swift case name for a canonical `HKCategoryTypeIdentifier` raw value
/// (`HKCategoryTypeIdentifierFoo` -> `foo`).
String _swiftCaseName(String identifier) {
  final remainder =
      identifier.replaceFirst('HKCategoryTypeIdentifier', '');
  return remainder.isEmpty
      ? remainder
      : remainder[0].toLowerCase() + remainder.substring(1);
}

void main() {
  group('Dart <-> Swift deviation identifier contract', () {
    late String swift;

    setUpAll(() {
      swift = _stripLineComments(readRepoFile(_appDelegatePath));
    });

    test('the Swift resolver table is exactly the Dart enum', () {
      final table = _deviationTable(swift);
      expect(table, isNotEmpty, reason: 'the deviationKinds table did not parse');
      expect(
        {for (final (wire, identifier) in table) wire: identifier},
        {
          for (final kind in HealthDeviationKind.values)
            kind.wire: kind.healthKitIdentifier,
        },
      );
    });

    test('every Dart identifier is the canonical HealthKit raw value', () {
      expect(
        [for (final kind in HealthDeviationKind.values) kind.healthKitIdentifier],
        [
          'HKCategoryTypeIdentifierIrregularMenstrualCycles',
          'HKCategoryTypeIdentifierInfrequentMenstrualCycles',
          'HKCategoryTypeIdentifierProlongedMenstrualPeriods',
          'HKCategoryTypeIdentifierPersistentIntermenstrualBleeding',
        ],
      );
    });

    test('the resolver accepts a wire name or the canonical identifier', () {
      // The Dart read sends identifiers; the Swift table is keyed by wire
      // name. Accepting both keeps the contract honest either way.
      expect(swift, contains(r'$0.wire == wire || $0.identifier == wire'));
    });
  });

  group('the deviation types are read-only, never written (5.1.3)', () {
    late String swift;

    setUpAll(() {
      swift = _stripLineComments(readRepoFile(_appDelegatePath));
    });

    test('no deviation case name appears in the written category set', () {
      final written = _swiftArrayCases(swift, 'writtenCategoryTypeIdentifiers');
      for (final kind in HealthDeviationKind.values) {
        expect(
          written,
          isNot(contains(_swiftCaseName(kind.healthKitIdentifier))),
          reason: '${kind.wire} must never be a written HealthKit type',
        );
      }
    });

    test('the share set is still built only from writtenSampleTypes', () {
      expect(swift, contains('let toShare = Set(writtenSampleTypes)'));
    });

    test('the deviation types join the read set and nothing else', () {
      expect(swift, contains('deviationReadTypes'));
      expect(
        swift,
        contains(
          'let toRead: Set<HKObjectType> = Set(\n'
          '        [menstrualFlowType as HKObjectType]\n'
          '          + deviationReadTypes.map { \$0 as HKObjectType })',
        ),
      );
    });
  });
}
