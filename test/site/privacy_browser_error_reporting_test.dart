import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the signed-in-browser error-reporting disclosure (issue #1187).
///
/// PRIVACY.md §6's "Signed-In Browser Build (Web)" bullet used to describe
/// the pre-#1110 state — browser crash reporting "unverified" and blocked by
/// the CSP — while the deployed `LUNARLOG_WEB_SYNC=true` build actually
/// POSTs scrubbed error envelopes straight to Sentry's ingest host over the
/// CSP's `connect-src` allowance (`WebDartSentryTransport` in
/// `lib/observability/sentry_bootstrap.dart`). A user-facing privacy ledger
/// that denies a transmission the build performs is the one error a
/// disclosure must not make, so these assertions keep the ledger, the
/// shipped behavior, and `docs/web/security-posture.md` from drifting apart
/// again:
///
/// - the stale "unverified" sentence is gone from the browser bullet;
/// - the bullet names the scrubbed envelopes, the ingest host, and the
///   `connect-src` entries that allow the send;
/// - `web/_headers` still pins the ingest host the bullet cites;
/// - `docs/web/security-posture.md` still records the same fix.
void main() {
  final privacy =
      File('PRIVACY.md').readAsStringSync().replaceAll('\r\n', '\n');

  // The §6 bullet runs from its heading to the next top-level bullet; the
  // markdown keeps each bullet on one line, exactly the shape
  // `privacy_header_test.dart` reads.
  final bulletStart = privacy.indexOf('- **Signed-In Browser Build (Web):**');
  final bullet = bulletStart < 0
      ? ''
      : privacy.substring(bulletStart, privacy.indexOf('\n- **', bulletStart));

  test('the browser bullet discloses the scrubbed envelope send', () {
    expect(
      bulletStart,
      greaterThanOrEqualTo(0),
      reason: "Section 6's Signed-In Browser Build bullet is the ledger's "
          'browser story; it must exist',
    );
    expect(
      bullet,
      contains('scrubbed error envelopes'),
      reason: 'the ledger must state what the signed-in browser build '
          'actually sends',
    );
    expect(
      bullet,
      contains("Sentry's ingest host"),
      reason: 'the send destination is part of the disclosure',
    );
    expect(
      bullet,
      contains('connect-src'),
      reason: 'the CSP allowance that permits the send is part of it',
    );
    expect(
      bullet,
      isNot(contains('unverified')),
      reason: 'the pre-#1110 "unverified" claim is stale: the direct-to-ingest '
          'transport shipped and issue #1110 is closed',
    );
    expect(
      bullet,
      isNot(contains('tracked in issue #1110')),
      reason: 'a closed tracking reference no longer belongs in the '
          'user-facing policy',
    );
  });

  test('the CSP still allows the ingest host the bullet cites', () {
    final headers =
        File('web/_headers').readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      headers,
      contains('https://*.ingest.sentry.io'),
      reason: 'the bullet says the CSP explicitly allows the ingest host; '
          'the header must keep pinning it',
    );
  });

  test('security-posture.md and the ledger tell the same story', () {
    // When the audit found the gap, these two documents disagreed: the
    // posture doc recorded the shipped Dart-side transport ("resolved with
    // option 2") while the ledger still called browser reporting unverified.
    final posture = File('docs/web/security-posture.md')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      posture,
      contains('WebDartSentryTransport'),
      reason: 'the posture doc records the Dart-side transport the bullet '
          'now discloses',
    );
    expect(
      posture,
      contains('resolved with option 2'),
      reason: 'the posture doc still records the issue #1110 resolution',
    );
    expect(
      bullet,
      contains('scrubbed error envelopes'),
      reason: 'the ledger carries the same fact the posture doc records',
    );
  });
}
