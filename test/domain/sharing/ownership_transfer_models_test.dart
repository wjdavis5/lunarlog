/// Unit tests for domain models and value types in
/// ownership_transfer_service.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';

void main() {
  group('ParentPostTransferRole', () {
    test('toDb maps to the server check-constraint values', () {
      expect(ParentPostTransferRole.coManager.toDb(), 'co_parent');
      expect(ParentPostTransferRole.viewer.toDb(), 'viewer');
    });

    test('label is human readable and distinct per role', () {
      expect(ParentPostTransferRole.coManager.label, 'Co-manager');
      expect(ParentPostTransferRole.viewer.label, 'Viewer');
      expect(
        ParentPostTransferRole.coManager.label,
        isNot(ParentPostTransferRole.viewer.label),
      );
    });
  });

  group('GeneratedTransfer equality and hashCode', () {
    final now = DateTime.utc(2026, 9, 6);
    final later = DateTime.utc(2026, 9, 7);

    GeneratedTransfer make({
      String transferId = 'transfer-1',
      String profileId = 'profile-1',
      ParentPostTransferRole role = ParentPostTransferRole.coManager,
      String rawToken = 'raw-token',
      String tokenHash = 'token-hash',
      Uri? claimUri,
      DateTime? expiresAt,
    }) =>
        GeneratedTransfer(
          transferId: transferId,
          profileId: profileId,
          parentPostTransferRole: role,
          rawToken: rawToken,
          tokenHash: tokenHash,
          claimUri: claimUri ??
              Uri.parse(
                  'lunarlog://invite?code=raw-token&profile=profile-1&kind=claim'),
          expiresAt: expiresAt ?? now,
        );

    test('identical and equal instances compare equal', () {
      final a = make();
      final b = make();
      expect(a, a);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(make() == 'not a transfer', isFalse);
    });

    test('differing transferId compares unequal', () {
      expect(make(), isNot(make(transferId: 'transfer-2')));
    });

    test('differing profileId compares unequal', () {
      expect(make(), isNot(make(profileId: 'profile-2')));
    });

    test('differing parentPostTransferRole compares unequal', () {
      expect(make(), isNot(make(role: ParentPostTransferRole.viewer)));
    });

    test('differing rawToken compares unequal', () {
      expect(make(), isNot(make(rawToken: 'other-token')));
    });

    test('differing tokenHash compares unequal', () {
      expect(make(), isNot(make(tokenHash: 'other-hash')));
    });

    test('differing claimUri compares unequal', () {
      expect(
        make(),
        isNot(make(claimUri: Uri.parse('lunarlog://invite?code=other'))),
      );
    });

    test('differing expiresAt compares unequal', () {
      expect(make(), isNot(make(expiresAt: later)));
    });

    test('the documented claim URI shape is exposed verbatim', () {
      final transfer = make();
      expect(
        transfer.claimUri.toString(),
        'lunarlog://invite?code=raw-token&profile=profile-1&kind=claim',
      );
    });
  });

  group('ClaimedProfileResult equality and hashCode', () {
    ClaimedProfileResult make({
      String profileId = 'profile-1',
      String profileName = 'Luna',
      String parentRole = 'co_parent',
      int entriesTransferred = 12,
    }) =>
        ClaimedProfileResult(
          profileId: profileId,
          profileName: profileName,
          parentRole: parentRole,
          entriesTransferred: entriesTransferred,
        );

    test('identical and equal instances compare equal', () {
      final a = make();
      final b = make();
      expect(a, a);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(make() == 'not a result', isFalse);
    });

    test('differing profileId compares unequal', () {
      expect(make(), isNot(make(profileId: 'profile-2')));
    });

    test('differing profileName compares unequal', () {
      expect(make(), isNot(make(profileName: 'Nova')));
    });

    test('differing parentRole compares unequal', () {
      expect(make(), isNot(make(parentRole: 'viewer')));
    });

    test('differing entriesTransferred compares unequal', () {
      expect(make(), isNot(make(entriesTransferred: 0)));
    });
  });

  group('TransferFailure types', () {
    test('constructors produce the expected subclass', () {
      expect(const TransferFailure.network(), isA<TransferNetworkFailure>());
      expect(const TransferFailure.notFound(), isA<TransferNotFoundFailure>());
      expect(const TransferFailure.expired(), isA<TransferExpiredFailure>());
      expect(
          const TransferFailure.cancelled(), isA<TransferCancelledFailure>());
      expect(const TransferFailure.alreadyAccepted(),
          isA<TransferAlreadyAcceptedFailure>());
      expect(const TransferFailure.selfTransfer(),
          isA<TransferSelfTransferFailure>());
      expect(const TransferFailure.staleOwner(),
          isA<TransferStaleOwnerFailure>());
      expect(const TransferFailure.unauthorized(),
          isA<TransferUnauthorizedFailure>());
      expect(const TransferFailure.invalidToken(),
          isA<TransferInvalidTokenFailure>());
      expect(const TransferFailure.other('boom'), isA<TransferOtherFailure>());
    });

    const allFailures = <TransferFailure>[
      TransferFailure.network(),
      TransferFailure.notFound(),
      TransferFailure.expired(),
      TransferFailure.cancelled(),
      TransferFailure.alreadyAccepted(),
      TransferFailure.selfTransfer(),
      TransferFailure.staleOwner(),
      TransferFailure.unauthorized(),
      TransferFailure.invalidToken(),
      TransferFailure.other('boom'),
    ];

    test('every subclass has a non-empty userFacingMessage', () {
      for (final failure in allFailures) {
        expect(failure.userFacingMessage, isNotEmpty,
            reason: '${failure.runtimeType} has an empty userFacingMessage');
      }
    });

    test('every subclass has a distinct userFacingMessage', () {
      final messages = allFailures.map((f) => f.userFacingMessage).toSet();
      expect(messages.length, allFailures.length,
          reason: 'two TransferFailure subclasses share a userFacingMessage');
    });

    test('every subclass has a sensible, distinct toString', () {
      final strings = allFailures.map((f) => f.toString()).toSet();
      expect(strings.length, allFailures.length);
      for (final failure in allFailures) {
        expect(failure.toString(), contains('TransferFailure'));
      }
    });

    test('two instances of the same fieldless subclass are equal', () {
      expect(const TransferFailure.expired(), const TransferFailure.expired());
      expect(const TransferFailure.expired().hashCode,
          const TransferFailure.expired().hashCode);
      expect(const TransferFailure.cancelled(),
          const TransferFailure.cancelled());
      expect(const TransferFailure.alreadyAccepted(),
          const TransferFailure.alreadyAccepted());
      expect(const TransferFailure.selfTransfer(),
          const TransferFailure.selfTransfer());
      expect(
          const TransferFailure.staleOwner(), const TransferFailure.staleOwner());
    });

    test('two instances of TransferOtherFailure with the same message are equal', () {
      expect(const TransferFailure.other('boom'),
          const TransferFailure.other('boom'));
      expect(const TransferFailure.other('boom').hashCode,
          const TransferFailure.other('boom').hashCode);
    });

    test('different subclasses are not equal to each other', () {
      for (var i = 0; i < allFailures.length; i++) {
        for (var j = 0; j < allFailures.length; j++) {
          if (i == j) continue;
          expect(allFailures[i], isNot(allFailures[j]),
              reason:
                  '${allFailures[i].runtimeType} should not equal ${allFailures[j].runtimeType}');
        }
      }
    });

    test('TransferOtherFailure carries its diagnostic message', () {
      const failure = TransferFailure.other('rpc exploded');
      expect(failure, isA<TransferOtherFailure>());
      expect((failure as TransferOtherFailure).message, 'rpc exploded');
      expect(failure.toString(), contains('rpc exploded'));
    });
  });
}
