/// Issue #151: value-type equality/hashCode coverage for the
/// prediction-connection domain models (the CRAP gate counts each
/// untested `==` branch; these tests drive every one).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';

GeneratedPredictionInvite _invite({String id = 'c1'}) =>
    GeneratedPredictionInvite(
      connectionId: id,
      profileId: 'p1',
      rawToken: 'token',
      tokenHash: 'hash',
      inviteUri: Uri.parse('lunarlog://invite?code=token&kind=prediction'),
      expiresAt: DateTime.utc(2026, 9, 10),
    );

ActivePredictionConnection _active({String id = 'c1', bool pending = false}) =>
    ActivePredictionConnection(
      connectionId: id,
      profileId: 'p1',
      pending: pending,
      recipientLabel: 'Partner',
      createdAt: DateTime.utc(2026, 9, 1),
      expiresAt: DateTime.utc(2026, 9, 8),
    );

IncomingPredictionConnection _incoming({String id = 'c1'}) =>
    IncomingPredictionConnection(
      connectionId: id,
      profileId: 'p1',
      acceptedAt: DateTime.utc(2026, 9, 1),
    );

AcceptedPredictionConnection _accepted({String id = 'c1'}) =>
    AcceptedPredictionConnection(
      connectionId: id,
      profileId: 'p1',
      profileName: 'Riley',
    );

void main() {
  group('GeneratedPredictionInvite', () {
    test('equal instances match and hash equally', () {
      expect(_invite(), _invite());
      expect(_invite().hashCode, _invite().hashCode);
      expect(_invite(), isNot(_invite(id: 'c2')));
    });

    test('every field participates in equality', () {
      final base = _invite();
      expect(base, isNot(base.copyWithConnectionId('x')));
      expect(base, isNot(base.copyWithProfileId('x')));
      expect(base, isNot(base.copyWithRawToken('x')));
      expect(base, isNot(base.copyWithTokenHash('x')));
      expect(base, isNot(base.copyWithUri(Uri.parse('lunarlog://other'))));
      expect(base, isNot(base.copyWithExpiresAt(DateTime.utc(2027))));
      expect(base, isNot('not an invite'));
    });
  });

  group('ActivePredictionConnection', () {
    test('equal instances match and hash equally', () {
      expect(_active(), _active());
      expect(_active().hashCode, _active().hashCode);
      expect(_active(), isNot(_active(id: 'c2')));
    });

    test('every field participates in equality', () {
      final base = _active();
      expect(base, isNot(base.rebuild(connectionId: 'x')));
      expect(base, isNot(base.rebuild(profileId: 'x')));
      expect(base, isNot(base.rebuild(pending: true)));
      expect(base, isNot(base.rebuild(recipientLabel: 'x')));
      expect(base, isNot(base.rebuild(createdAt: DateTime.utc(2027))));
      expect(base, isNot(base.rebuild(expiresAt: DateTime.utc(2027))));
      expect(base, isNot('not a connection'));
    });
  });

  group('IncomingPredictionConnection', () {
    test('equal instances match and hash equally, and every field '
        'participates', () {
      expect(_incoming(), _incoming());
      expect(_incoming().hashCode, _incoming().hashCode);
      expect(_incoming(), isNot(_incoming(id: 'c2')));
      expect(
        _incoming(),
        isNot(IncomingPredictionConnection(
          connectionId: 'c1',
          profileId: 'other',
          acceptedAt: DateTime.utc(2026, 9, 1),
        )),
      );
      expect(
        _incoming(),
        isNot(IncomingPredictionConnection(
          connectionId: 'c1',
          profileId: 'p1',
          acceptedAt: DateTime.utc(2027, 1, 1),
        )),
      );
      expect(_incoming(), isNot('not incoming'));
    });
  });

  group('AcceptedPredictionConnection', () {
    test('equal instances match and hash equally, and every field '
        'participates', () {
      expect(_accepted(), _accepted());
      expect(_accepted().hashCode, _accepted().hashCode);
      expect(_accepted(), isNot(_accepted(id: 'c2')));
      expect(
        _accepted(),
        isNot(AcceptedPredictionConnection(
          connectionId: 'c1',
          profileId: 'other',
          profileName: 'Riley',
        )),
      );
      expect(
        _accepted(),
        isNot(AcceptedPredictionConnection(
          connectionId: 'c1',
          profileId: 'p1',
          profileName: 'Other',
        )),
      );
      expect(_accepted(), isNot('not accepted'));
    });
  });
}

extension on GeneratedPredictionInvite {
  GeneratedPredictionInvite copyWithConnectionId(String v) =>
      GeneratedPredictionInvite(
        connectionId: v,
        profileId: profileId,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: inviteUri,
        expiresAt: expiresAt,
      );

  GeneratedPredictionInvite copyWithProfileId(String v) =>
      GeneratedPredictionInvite(
        connectionId: connectionId,
        profileId: v,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: inviteUri,
        expiresAt: expiresAt,
      );

  GeneratedPredictionInvite copyWithRawToken(String v) =>
      GeneratedPredictionInvite(
        connectionId: connectionId,
        profileId: profileId,
        rawToken: v,
        tokenHash: tokenHash,
        inviteUri: inviteUri,
        expiresAt: expiresAt,
      );

  GeneratedPredictionInvite copyWithTokenHash(String v) =>
      GeneratedPredictionInvite(
        connectionId: connectionId,
        profileId: profileId,
        rawToken: rawToken,
        tokenHash: v,
        inviteUri: inviteUri,
        expiresAt: expiresAt,
      );

  GeneratedPredictionInvite copyWithUri(Uri v) => GeneratedPredictionInvite(
        connectionId: connectionId,
        profileId: profileId,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: v,
        expiresAt: expiresAt,
      );

  GeneratedPredictionInvite copyWithExpiresAt(DateTime v) =>
      GeneratedPredictionInvite(
        connectionId: connectionId,
        profileId: profileId,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: inviteUri,
        expiresAt: v,
      );
}

extension on ActivePredictionConnection {
  ActivePredictionConnection rebuild({
    String? connectionId,
    String? profileId,
    bool? pending,
    String? recipientLabel,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) =>
      ActivePredictionConnection(
        connectionId: connectionId ?? this.connectionId,
        profileId: profileId ?? this.profileId,
        pending: pending ?? this.pending,
        recipientLabel: recipientLabel ?? this.recipientLabel,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}
