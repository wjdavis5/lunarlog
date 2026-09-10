import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the issue #129 hosted-surface drafts (AC6): the well-known
/// templates and the neutral landing page must never gain a third-party
/// script, an analytics/cookie/storage mechanism, or identity information,
/// and the redeemable token must appear nowhere except the URL it arrived
/// in.
void main() {
  group('universal-link hosted artifacts (issue #129, AC6)', () {
    late String aasa;
    late String assetlinks;
    late String landing;

    setUpAll(() {
      aasa = File('docs/links/apple-app-site-association').readAsStringSync();
      assetlinks = File('docs/links/assetlinks.json').readAsStringSync();
      landing = File('docs/links/invite.html').readAsStringSync();
    });

    test('AASA pins the bundle id and the invite path only', () {
      expect(aasa, contains('com.wjdavis5.lunarlog'));
      expect(aasa, contains('/invite*'));
      // The Team ID is a human-filled placeholder until #384 provisions it.
      expect(aasa, contains('__TEAMID__'));
    });

    test('assetlinks pins the package name with a placeholder fingerprint', () {
      expect(assetlinks, contains('com.wjdavis5.lunarlog'));
      expect(assetlinks, contains('__SHA256_CERT_FINGERPRINT__'));
    });

    test('no artifact phones home or persists anything', () {
      for (final content in [aasa, assetlinks, landing]) {
        expect(content, isNot(contains('analytics')));
        expect(content, isNot(contains('googletag')));
        expect(content, isNot(contains('gtag')));
      }
      // No third-party or analytics script, no cookie/storage/network
      // mechanism anywhere in the landing page (its one inline script only
      // reads its own query string and sets one anchor href).
      expect(landing, isNot(contains('src=')));
      expect(landing, isNot(contains('cookie')));
      expect(landing, isNot(contains('localStorage')));
      expect(landing, isNot(contains('fetch(')));
      expect(landing, isNot(contains('XMLHttpRequest')));
      // No Referer leak on the way out.
      expect(landing, contains('no-referrer'));
      expect(landing, contains('noreferrer'));
    });

    test('no artifact names a profile, child, or inviter', () {
      for (final content in [aasa, assetlinks, landing]) {
        expect(content.toLowerCase(), isNot(contains('profile_name')));
        expect(content.toLowerCase(), isNot(contains('inviter')));
      }
      // Neutral copy: an invitation notice with install-then-reopen steps,
      // never a name.
      expect(landing, contains('invitation'));
      expect(landing, contains('Install'));
    });

    test('the token appears nowhere except the URL it arrived in', () {
      // No rendered token/hash text, no persisted copy: the page holds the
      // code only inside link hrefs it builds from its own query string.
      expect(landing.toLowerCase(), isNot(contains('token_hash')));
      expect(landing, isNot(contains('>code<')));
      expect(landing, contains('open-in-app'));
    });
  });
}
