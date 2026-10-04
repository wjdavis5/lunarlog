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
