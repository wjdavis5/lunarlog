import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the browser client's crash-reporting disclosure (issues #1187 and
/// #1258).
///
/// History: the Flutter web build POSTed scrubbed error envelopes straight
/// to Sentry's ingest host (issue #1110's fix), and this test kept that
/// disclosure honest. The React web client (#1258) sends **nothing** to
/// Sentry — no third-party script loads on it at all — so the ledger now
/// discloses the absence, and these assertions keep the policy, the shipped
/// client, and `docs/web/security-posture.md` from drifting apart again:
///
/// - §6's "Browser Client (Web)" bullet states the web client sends nothing
///   to Sentry and no third-party script loads;
/// - the deployed Worker's CSP allows only the app and Supabase (the
///   functional block on any Sentry send);
/// - `docs/web/security-posture.md` records the retirement.
void main() {
  final privacy =
      File('PRIVACY.md').readAsStringSync().replaceAll('\r\n', '\n');

  // The §6 bullet runs from its heading to the next top-level bullet; the
  // markdown keeps each bullet on one line.
  final bulletStart = privacy.indexOf('- **Browser Client (Web):**');
  final bullet = bulletStart < 0
      ? ''
      : privacy.substring(bulletStart, privacy.indexOf('\n- **', bulletStart));

  test('the browser bullet discloses the no-Sentry posture', () {
    expect(
      bulletStart,
      greaterThanOrEqualTo(0),
      reason: "Section 6's Browser Client bullet is the ledger's browser "
          'story; it must exist',
    );
    expect(
      bullet,
      contains('sends nothing to Sentry'),
      reason: 'the ledger must state what the web client actually does: '
          'no error reporting runs on it',
    );
    expect(
      bullet,
      contains('no third-party script loads'),
      reason: 'the functional block is part of the disclosure',
    );
  });

  // Issue #1396: the bullet named "the native Google sign-in" alone while
  // the web client offered Google and Apple, both by redirect. The pin
  // reads the provider list from the client itself, so adding or removing
  // a provider there fails here until the policy says so.
  test('the browser bullet names every sign-in provider the web client '
      'offers', () {
    final auth = File('webapp/src/lib/auth.ts').readAsStringSync();
    final union = RegExp(r"export type OAuthProvider = ([^;]+);")
        .firstMatch(auth);
    expect(union, isNotNull,
        reason: 'webapp/src/lib/auth.ts no longer declares OAuthProvider');
    final providers = RegExp(r"'([a-z]+)'")
        .allMatches(union!.group(1)!)
        .map((match) => match.group(1)!)
        .toList();
    expect(providers, isNotEmpty);
    for (final provider in providers) {
      final name = provider[0].toUpperCase() + provider.substring(1);
      expect(
        bullet,
        contains(name),
        reason: 'the web client offers $name sign-in; Section 6 must say so',
      );
    }
    expect(bullet, contains('password, Google and Apple'));
    expect(
      bullet,
      isNot(contains('native Google')),
      reason: 'no provider sign-in is native in a browser; both redirect',
    );
    expect(bullet, contains('through a redirect'));
  });

  // The web client's signed-out home tells the reader what the browser
  // keeps (`webWelcomeStorageNote`). That is a promise, and this bullet is
  // where the promise is made, so each half of the note is pinned to the
  // sentence that backs it: if the policy stops saying one, the note has to
  // change in the same PR.
  test("the web welcome's storage note says no more than the browser "
      'bullet does', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final note = arb['webWelcomeStorageNote'] as String?;
    expect(note, isNotNull,
        reason: 'the signed-out home renders webWelcomeStorageNote');

    expect(note, contains('keeps your sign-in and nothing else'));
    expect(
      bullet,
      contains('nothing at rest in the browser'),
      reason: '"nothing else" rests on this',
    );
    expect(
      bullet,
      contains('refresh token lives solely in an HttpOnly'),
      reason: '"your sign-in" is this cookie and nothing more',
    );

    expect(note, contains('profiles and entries are never saved here'));
    expect(
      bullet,
      contains('No copy of profiles or day entries is ever written to '
          'browser storage'),
    );

    expect(note, contains('sign out when you'));
    expect(
      bullet,
      contains('signing out clears it'),
      reason: 'the advice for a shared computer only holds if signing out '
          'removes the one thing the browser kept',
    );
  });

  test('the deployed Worker CSP allows only the app and Supabase', () {
    final headers = File('webapp/worker/headers.ts')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      headers,
      contains("script-src 'self'"),
      reason: 'the deployed policy is the functional enforcement behind the '
          'no-third-party-script claim',
    );
    expect(
      headers,
      isNot(contains('sentry')),
      reason: 'no Sentry host may appear in the web client CSP — the client '
          'sends nothing there (#1258)',
    );
  });

  test('security-posture.md records the retirement', () {
    final posture = File('docs/web/security-posture.md')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      posture,
      contains('sends nothing to Sentry'),
      reason: 'the posture doc and the ledger must tell the same story '
          '(issue #1187 kept them aligned for the Flutter build; the React '
          'retirement of that transport is the same discipline)',
    );
  });
}
