import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/invite_links.dart';

void main() {
  group('normalizeLinkDomain', () {
    test('empty stays empty', () {
      expect(normalizeLinkDomain(''), isEmpty);
      expect(normalizeLinkDomain('   '), isEmpty);
    });

    test('a bare domain passes through lowercased', () {
      expect(normalizeLinkDomain('Links.Example.COM'), 'links.example.com');
    });

    test('strips a scheme prefix, path, and trailing slash', () {
      expect(
        normalizeLinkDomain('https://links.example.com/invite?code=x'),
        'links.example.com',
      );
      expect(normalizeLinkDomain('http://links.example.com/'), 'links.example.com');
    });
  });

  group('buildInviteLink', () {
    test('defaults to the custom scheme with code and profile', () {
      final uri = buildInviteLink(code: 'raw-token', profileId: 'p-1');

      expect(uri.scheme, 'lunarlog');
      expect(uri.host, 'invite');
      expect(uri.queryParameters['code'], 'raw-token');
      expect(uri.queryParameters['profile'], 'p-1');
      expect(uri.queryParameters.containsKey('kind'), isFalse);
    });

    test('carries kind when supplied (claim and prediction)', () {
      expect(
        buildInviteLink(code: 'c', profileId: 'p', kind: 'claim')
            .queryParameters['kind'],
        'claim',
      );
      expect(
        buildInviteLink(code: 'c', kind: 'prediction').queryParameters['kind'],
        'prediction',
      );
    });

    test('emits the HTTPS form when a domain is configured', () {
      final uri = buildInviteLink(
        code: 'raw-token',
        profileId: 'p-1',
        linkDomain: 'links.example.com',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'links.example.com');
      expect(uri.path, '/invite');
      expect(uri.queryParameters['code'], 'raw-token');
      expect(uri.queryParameters['profile'], 'p-1');
    });

    test('normalizes the configured domain before emitting', () {
      final uri = buildInviteLink(
        code: 'c',
        linkDomain: 'https://Links.Example.COM/',
      );

      expect(uri.host, 'links.example.com');
    });

    test('an empty domain keeps the custom scheme (AC5)', () {
      final uri = buildInviteLink(code: 'c', profileId: 'p', linkDomain: '');

      expect(uri.scheme, 'lunarlog');
      expect(uri.host, 'invite');
    });
  });

  group('parseInviteLink / isInviteLink', () {
    test('accepts the custom-scheme invite form', () {
      final link = parseInviteLink(
        Uri.parse('lunarlog://invite?code=raw-token&profile=p-1'),
      );

      expect(link, isNotNull);
      expect(link!.code, 'raw-token');
      expect(link.profileId, 'p-1');
      expect(link.kind, isNull);
      expect(link.isClaim, isFalse);
      expect(link.isPrediction, isFalse);
    });

    test('accepts the HTTPS form when the domain matches', () {
      final link = parseInviteLink(
        Uri.parse('https://links.example.com/invite?code=raw-token&profile=p-1'),
        linkDomain: 'links.example.com',
      );

      expect(link, isNotNull);
      expect(link!.code, 'raw-token');
      expect(link.profileId, 'p-1');
      expect(isInviteLink(
        Uri.parse('https://links.example.com/invite?code=raw-token'),
        linkDomain: 'links.example.com',
      ), isTrue);
    });

    test('accepts a trailing slash on the HTTPS path', () {
      expect(
        parseInviteLink(
          Uri.parse('https://links.example.com/invite/?code=c'),
          linkDomain: 'links.example.com',
        )!.code,
        'c',
      );
    });

    test('keeps kind=claim and kind=prediction on both forms', () {
      const domain = 'links.example.com';
      final claimCustom =
          parseInviteLink(Uri.parse('lunarlog://invite?code=c&kind=claim'))!;
      final claimHttps = parseInviteLink(
        Uri.parse('https://links.example.com/invite?code=c&kind=claim'),
        linkDomain: domain,
      )!;
      expect(claimCustom.isClaim, isTrue);
      expect(claimHttps.isClaim, isTrue);
      expect(claimHttps.isPrediction, isFalse);

      final predictionHttps = parseInviteLink(
        Uri.parse('https://links.example.com/invite?code=c&kind=prediction'),
        linkDomain: domain,
      )!;
      expect(predictionHttps.isPrediction, isTrue);
      expect(predictionHttps.isClaim, isFalse);
    });

    test('rejects an HTTPS invite URL when no domain is configured (AC5)', () {
      expect(
        parseInviteLink(
          Uri.parse('https://links.example.com/invite?code=c'),
        ),
        isNull,
      );
      expect(
        isInviteLink(Uri.parse('https://links.example.com/invite?code=c')),
        isFalse,
      );
    });

    test('rejects a mismatched domain, wrong path, and plain http', () {
      const domain = 'links.example.com';
      expect(
        parseInviteLink(
          Uri.parse('https://other.example.com/invite?code=c'),
          linkDomain: domain,
        ),
        isNull,
      );
      expect(
        parseInviteLink(
          Uri.parse('https://links.example.com/other?code=c'),
          linkDomain: domain,
        ),
        isNull,
      );
      expect(
        parseInviteLink(
          Uri.parse('http://links.example.com/invite?code=c'),
          linkDomain: domain,
        ),
        isNull,
      );
    });

    test('rejects null, code-less, and unrelated links', () {
      expect(parseInviteLink(null), isNull);
      expect(parseInviteLink(Uri.parse('lunarlog://invite')), isNull);
      expect(parseInviteLink(Uri.parse('lunarlog://invite?code=')), isNull);
      expect(parseInviteLink(Uri.parse('lunarlog://auth-callback?code=c')), isNull);
      expect(parseInviteLink(Uri.parse('https://example.com/?code=c')), isNull);
      expect(
        isInviteLink(Uri.parse('lunarlog://other?code=c')),
        isFalse,
      );
    });

    test('InviteLink equality distinguishes code, profile, and kind', () {
      const base = InviteLink(code: 'c', profileId: 'p', kind: 'claim');
      expect(base, const InviteLink(code: 'c', profileId: 'p', kind: 'claim'));
      expect(base == const InviteLink(code: 'x', profileId: 'p', kind: 'claim'), isFalse);
      expect(base == const InviteLink(code: 'c', profileId: 'q', kind: 'claim'), isFalse);
      expect(base == const InviteLink(code: 'c', profileId: 'p'), isFalse);
      expect(base.hashCode, const InviteLink(code: 'c', profileId: 'p', kind: 'claim').hashCode);
    });
  });
}
