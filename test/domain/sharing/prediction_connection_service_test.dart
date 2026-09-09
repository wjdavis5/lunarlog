/// Issue #151 CRAP-gate fix-up: equality coverage for
/// prediction_connection_service.dart's four @immutable value types
/// (GeneratedPredictionInvite, ActivePredictionConnection,
/// IncomingPredictionConnection, AcceptedPredictionConnection). Each
/// derived operator== is a single `identical(this, other) || other is X
/// && f1 == f1 && ... && fN == fN` chain: getting full line coverage of
/// the `&&` chain requires calling == on two structurally-equal,
/// non-identical instances (so evaluation walks every field comparison
/// rather than short-circuiting on `identical`); the per-field
/// inequality cases below additionally verify the fields actually drive
/// the result, and each group's hashCode assertion checks the standard
/// `==` ⇒ same `hashCode` invariant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';

void main() {
  group('GeneratedPredictionInvite equality', () {
    GeneratedPredictionInvite make({
      String connectionId = 'conn-1',
      String profileId = 'p-1',
      String rawToken = 'raw-token',
      String tokenHash = 'token-hash',
      Uri? inviteUri,
      DateTime? expiresAt,
    }) => GeneratedPredictionInvite(
      connectionId: connectionId,
      profileId: profileId,
      rawToken: rawToken,
      tokenHash: tokenHash,
      inviteUri:
          inviteUri ??
          Uri.parse('lunarlog://invite?code=raw-token&kind=prediction'),
      expiresAt: expiresAt ?? DateTime.utc(2026, 9, 10),
    );

    test('two separately-built instances with the same fields are equal '
        'and share a hashCode', () {
      final a = make();
      final b = make();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('an instance is equal to itself', () {
      final a = make();
      expect(a, a);
    });

    test('differs in connectionId', () {
      expect(make(), isNot(make(connectionId: 'conn-2')));
    });

    test('differs in profileId', () {
      expect(make(), isNot(make(profileId: 'p-2')));
    });

    test('differs in rawToken', () {
      expect(make(), isNot(make(rawToken: 'other-token')));
    });

    test('differs in tokenHash', () {
      expect(make(), isNot(make(tokenHash: 'other-hash')));
    });

    test('differs in inviteUri', () {
      expect(
        make(),
        isNot(make(inviteUri: Uri.parse('lunarlog://invite?code=other'))),
      );
    });

    test('differs in expiresAt', () {
      expect(make(), isNot(make(expiresAt: DateTime.utc(2026, 9, 11))));
    });
  });

  group('ActivePredictionConnection equality', () {
    ActivePredictionConnection make({
      String connectionId = 'conn-1',
      String profileId = 'p-1',
      bool pending = true,
      String? recipientLabel = 'Partner',
      DateTime? createdAt,
      DateTime? expiresAt,
    }) => ActivePredictionConnection(
      connectionId: connectionId,
      profileId: profileId,
      pending: pending,
      recipientLabel: recipientLabel,
      createdAt: createdAt ?? DateTime.utc(2026, 9, 1),
      expiresAt: expiresAt ?? DateTime.utc(2026, 9, 8),
    );

    test('two separately-built instances with the same fields are equal '
        'and share a hashCode', () {
      final a = make();
      final b = make();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('an instance is equal to itself', () {
      final a = make();
      expect(a, a);
    });

    test('differs in connectionId', () {
      expect(make(), isNot(make(connectionId: 'conn-2')));
    });

    test('differs in profileId', () {
      expect(make(), isNot(make(profileId: 'p-2')));
    });

    test('differs in pending', () {
      expect(make(), isNot(make(pending: false)));
    });

    test('differs in recipientLabel, including null vs. set', () {
      expect(make(), isNot(make(recipientLabel: null)));
      expect(make(), isNot(make(recipientLabel: 'Aunt')));
    });

    test('differs in createdAt', () {
      expect(make(), isNot(make(createdAt: DateTime.utc(2026, 9, 2))));
    });

    test('differs in expiresAt', () {
      expect(make(), isNot(make(expiresAt: DateTime.utc(2026, 9, 9))));
    });
  });

  group('IncomingPredictionConnection equality', () {
    IncomingPredictionConnection make({
      String connectionId = 'conn-1',
      String profileId = 'p-1',
      DateTime? acceptedAt,
    }) => IncomingPredictionConnection(
      connectionId: connectionId,
      profileId: profileId,
      acceptedAt: acceptedAt ?? DateTime.utc(2026, 9, 1),
    );

    test('two separately-built instances with the same fields are equal '
        'and share a hashCode', () {
      final a = make();
      final b = make();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('an instance is equal to itself', () {
      final a = make();
      expect(a, a);
    });

    test('differs in connectionId', () {
      expect(make(), isNot(make(connectionId: 'conn-2')));
    });

    test('differs in profileId', () {
      expect(make(), isNot(make(profileId: 'p-2')));
    });

    test('differs in acceptedAt', () {
      expect(make(), isNot(make(acceptedAt: DateTime.utc(2026, 9, 2))));
    });
  });

  group('AcceptedPredictionConnection equality', () {
    AcceptedPredictionConnection make({
      String connectionId = 'conn-1',
      String profileId = 'p-1',
      String profileName = 'Riley',
    }) => AcceptedPredictionConnection(
      connectionId: connectionId,
      profileId: profileId,
      profileName: profileName,
    );

    test('two separately-built instances with the same fields are equal '
        'and share a hashCode', () {
      final a = make();
      final b = make();
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('an instance is equal to itself', () {
      final a = make();
      expect(a, a);
    });

    test('differs in connectionId', () {
      expect(make(), isNot(make(connectionId: 'conn-2')));
    });

    test('differs in profileId', () {
      expect(make(), isNot(make(profileId: 'p-2')));
    });

    test('differs in profileName', () {
      expect(make(), isNot(make(profileName: 'Avery')));
    });
  });
}
