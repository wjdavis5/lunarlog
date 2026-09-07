/// `UnsupportedPasskeyCeremonyClient` (#30 U3; KTD2): the default
/// [PasskeyCeremonyClient] until a platform adapter is adopted at
/// activation. Pure Dart, no plugin import, so this is a plain unit test —
/// no fake gateway, no widget pump.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/passkey_ceremony_client.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

void main() {
  group('UnsupportedPasskeyCeremonyClient', () {
    const client = UnsupportedPasskeyCeremonyClient();

    test('create throws providerUnavailable, never a crash', () async {
      await expectLater(client.create(const {'challenge': 'x'}),
          throwsA(const AuthFailure.providerUnavailable()));
    });

    test('get throws providerUnavailable, never a crash', () async {
      await expectLater(client.get(const {'challenge': 'x'}),
          throwsA(const AuthFailure.providerUnavailable()));
    });

    test('the thrown failure carries no message or provider detail', () async {
      Object? error;
      try {
        await client.create(const {'challenge': 'x'});
      } catch (e) {
        error = e;
      }
      expect(error.toString(), 'AuthFailure.providerUnavailable');
    });
  });
}
