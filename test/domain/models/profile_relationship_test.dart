/// Unit tests for the pure ProfileRelationship closed-set enum (Issue #4,
/// KTD8).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

void main() {
  group('ProfileRelationship.toDb/fromDb', () {
    test('every value round-trips through toDb/fromDb and has a label', () {
      for (final value in ProfileRelationship.values) {
        expect(ProfileRelationship.fromDb(value.toDb()), value);
        expect(value.label.isNotEmpty, isTrue);
      }
    });

    test('fromDb matches the server check constraint\'s exact set', () {
      expect(ProfileRelationship.fromDb('self'), ProfileRelationship.self);
      expect(
          ProfileRelationship.fromDb('daughter'), ProfileRelationship.daughter);
      expect(ProfileRelationship.fromDb('son'), ProfileRelationship.son);
      expect(ProfileRelationship.fromDb('child'), ProfileRelationship.child);
      expect(
          ProfileRelationship.fromDb('partner'), ProfileRelationship.partner);
      expect(ProfileRelationship.fromDb('other'), ProfileRelationship.other);
    });

    test('an unrecognised value returns null rather than throwing', () {
      expect(ProfileRelationship.fromDb('cousin'), isNull);
      expect(ProfileRelationship.fromDb(''), isNull);
      expect(ProfileRelationship.fromDb('Daughter'), isNull,
          reason: 'toDb()/fromDb() are lowercase-exact, matching the server '
              'check constraint');
    });

    test('labels are distinct across the closed set', () {
      final labels = ProfileRelationship.values.map((v) => v.label).toSet();
      expect(labels, hasLength(ProfileRelationship.values.length));
    });
  });
}
