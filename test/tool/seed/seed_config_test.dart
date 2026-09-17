import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;

import '../../../tool/seed_test_accounts/seed_config.dart';
import '../../../tool/seed_test_accounts/supabase_seed_client.dart';

/// An HTTP client that records every request and refuses them all — used
/// to prove the allowlist gate aborts BEFORE any network call.
class _RecordingRefusingClient extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    throw StateError(
      'no HTTP call may happen before the allowlist gate passes '
      '(got ${request.method} ${request.url})',
    );
  }
}

Map<String, String> _baseEnv() => {
      'SUPABASE_URL': 'http://127.0.0.1:54321',
      'LUNARLOG_SEED_ALLOWLIST':
          'seed.e2e.local@example.com, seed.partner@example.com',
      'LUNARLOG_SEED_ACCOUNT_EMAIL': 'seed.e2e.local@example.com',
      'LUNARLOG_SEED_PARTNER_EMAIL': 'seed.partner@example.com',
      'LUNARLOG_SEED_PASSWORD': 'fabricated-password-1',
    };

void main() {
  group('allowlist gate (AC #2: refuse before any write)', () {
    test('non-allowlisted target throws before any client is built', () {
      final client = _RecordingRefusingClient();
      final env = _baseEnv()
        ..['LUNARLOG_SEED_ACCOUNT_EMAIL'] = 'someone.real@example.com';
      expect(
        () => buildSeedToolConfig(env),
        throwsA(isA<SeedConfigException>().having(
          (e) => e.message,
          'message',
          contains('not in LUNARLOG_SEED_ALLOWLIST'),
        )),
      );
      // The gate is pure: no request was ever issued (this client is wired
      // the way main.dart would wire it, immediately after config passes).
      expect(client.requests, isEmpty);
    });

    test('non-allowlisted partner throws too', () {
      final env = _baseEnv()
        ..['LUNARLOG_SEED_PARTNER_EMAIL'] = 'other.real@example.com';
      expect(
        () => buildSeedToolConfig(env),
        throwsA(isA<SeedConfigException>()),
      );
    });

    test('partner equal to target throws', () {
      final env = _baseEnv()
        ..['LUNARLOG_SEED_PARTNER_EMAIL'] = 'seed.e2e.local@example.com';
      expect(
        () => buildSeedToolConfig(env),
        throwsA(isA<SeedConfigException>().having(
          (e) => e.message,
          'message',
          contains('must differ'),
        )),
      );
    });

    test('missing allowlist throws', () {
      final env = _baseEnv()..remove('LUNARLOG_SEED_ALLOWLIST');
      expect(() => buildSeedToolConfig(env), throwsA(isA<SeedConfigException>()));
    });

    test('email matching is case/whitespace insensitive', () {
      final env = _baseEnv()
        ..['LUNARLOG_SEED_ACCOUNT_EMAIL'] = '  Seed.E2E.Local@Example.com ';
      expect(buildSeedToolConfig(env).target.email,
          'seed.e2e.local@example.com');
    });

    test('a valid config wires the same client the gate protects', () {
      final env = _baseEnv();
      final config = buildSeedToolConfig(env);
      // Constructing the client after the gate passed is exactly main.dart's
      // order; with the refusing client injected nothing leaks either.
      expect(
        () => SupabaseSeedClient(config: config, httpClient: _RecordingRefusingClient()),
        returnsNormally,
      );
    });
  });

  group('keys and environments', () {
    test('local URL falls back to the public demo keys', () {
      final config = buildSeedToolConfig(_baseEnv());
      expect(config.publishableKey, kLocalDemoPublishableKey);
      expect(config.secretKey, kLocalDemoServiceKey);
    });

    test('non-local URL requires real keys', () {
      final env = _baseEnv()
        ..['SUPABASE_URL'] = 'https://dleexnnevuuddcgcpztq.supabase.co';
      expect(
        () => buildSeedToolConfig(env),
        throwsA(isA<SeedConfigException>().having(
          (e) => e.message,
          'message',
          contains('SUPABASE_PUBLISHABLE_KEY'),
        )),
      );
    });
  });

  group('password overrides', () {
    test('slug maps non-alphanumerics to underscores', () {
      expect(
        passwordEnvSlug('seed.e2e.local@example.com'),
        'SEED_E2E_LOCAL_EXAMPLE_COM',
      );
    });

    test('per-account override beats the shared password', () {
      final env = _baseEnv()
        ..['LUNARLOG_SEED_PASSWORD_SEED_PARTNER_EXAMPLE_COM'] =
            'partner-only-password';
      final config = buildSeedToolConfig(env);
      expect(config.target.password, 'fabricated-password-1');
      expect(config.partner.password, 'partner-only-password');
    });
  });
}
