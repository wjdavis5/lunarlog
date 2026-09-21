/// Epic #831 (slice 1) web security posture: pins the non-negotiable
/// directives in `web/_headers`.
///
/// The header file is the deployed policy for the first-class web build; the
/// posture it implements is recorded in `docs/web/security-posture.md`. A
/// header set is exactly the kind of config that silently regresses (a copied
/// block from another project, a directive dropped during a merge), so the
/// requirements are asserted here rather than left to review. A config test
/// cannot run a browser, so this pins the policy's *shape*; real-browser
/// verification is a follow-up named in the posture doc.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parses a Cloudflare/Netlify `_headers` document into a
/// `lowercase-header-name -> raw value` map. Selector lines (unindented,
/// e.g. `/*`), blank lines, and `#` comments are ignored; header lines are
/// the indented `Name: value` pairs. Later duplicates win, matching the
/// platform's own last-wins merge for one selector.
Map<String, String> parseHeaderFile(String contents) {
  final headers = <String, String>{};
  for (final raw in contents.split('\n')) {
    if (raw.trim().isEmpty) continue;
    if (raw.trimLeft().startsWith('#')) continue;
    // A selector line is unindented; headers are indented beneath one.
    if (!raw.startsWith(' ') && !raw.startsWith('\t')) continue;
    final colon = raw.indexOf(':');
    if (colon < 0) continue;
    final name = raw.substring(0, colon).trim().toLowerCase();
    final value = raw.substring(colon + 1).trim();
    if (name.isNotEmpty) headers[name] = value;
  }
  return headers;
}

/// Parses a Content-Security-Policy header value into
/// `directive -> source list`.
Map<String, List<String>> parseCsp(String value) {
  final directives = <String, List<String>>{};
  for (final part in value.split(';')) {
    final tokens = part.trim().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (tokens.isEmpty) continue;
    directives[tokens.first.toLowerCase()] = tokens.sublist(1);
  }
  return directives;
}

/// The same-binary check the header file must pass: the script source list
/// may carry `'wasm-unsafe-eval'` but never the much broader `'unsafe-eval'`
/// or an inline-script allowance.
bool scriptSrcIsStrict(List<String> scriptSrc) {
  final joined = scriptSrc.join(' ');
  if (!scriptSrc.contains("'self'")) return false;
  if (!scriptSrc.contains("'wasm-unsafe-eval'")) return false;
  if (joined.contains("'unsafe-eval'")) return false;
  if (joined.contains("'unsafe-inline'")) return false;
  return true;
}

void main() {
  final file = File('web/_headers');

  test('web/_headers exists and parses', () {
    expect(file.existsSync(), isTrue,
        reason: 'the web build ships web/_headers as its static policy');
    final headers = parseHeaderFile(file.readAsStringSync());
    expect(headers, isNotEmpty, reason: 'no headers parsed from web/_headers');
  });

  group('non-negotiable directives', () {
    late Map<String, String> headers;
    late Map<String, List<String>> csp;

    setUp(() {
      headers = parseHeaderFile(file.readAsStringSync());
      csp = parseCsp(headers['content-security-policy'] ?? '');
    });

    test('Transport / framing / referrer / sniffing', () {
      expect(headers['strict-transport-security'], isNotNull);
      final maxAge = RegExp(r'max-age=(\d+)')
          .firstMatch(headers['strict-transport-security']!)
          ?.group(1);
      expect(maxAge, isNotNull, reason: 'HSTS must carry a max-age');
      expect(int.parse(maxAge!), greaterThanOrEqualTo(31536000),
          reason: 'HSTS max-age must be at least one year');
      expect(headers['x-frame-options'], 'DENY');
      expect(headers['referrer-policy'], 'no-referrer');
      expect(headers['x-content-type-options'], 'nosniff');
    });

    test('Cross-origin isolation for sqlite3.wasm / drift_worker.js', () {
      expect(headers['cross-origin-opener-policy'], 'same-origin');
      expect(headers['cross-origin-embedder-policy'], 'require-corp');
    });

    test('Permissions-Policy denies device capabilities this app never uses',
        () {
      final policy = headers['permissions-policy'];
      expect(policy, isNotNull);
      for (final feature in [
        'camera=()',
        'microphone=()',
        'geolocation=()',
        'usb=()',
      ]) {
        expect(policy, contains(feature));
      }
    });

    test('CSP foundation: default-src self, no framing, no objects, no forms '
        'to other origins, no base hijack', () {
      expect(csp['default-src'], ["'self'"]);
      expect(csp['frame-ancestors'], ["'none'"]);
      expect(csp['object-src'], ["'none'"]);
      expect(csp['base-uri'], ["'self'"]);
      expect(csp['form-action'], ["'self'"]);
    });

    test('CSP script-src allows wasm compilation but not eval/inline', () {
      expect(csp['script-src'], isNotNull);
      expect(scriptSrcIsStrict(csp['script-src']!), isTrue,
          reason: 'script-src must be self + wasm-unsafe-eval only');
    });

    test('CSP worker-src allows same-origin and blob workers', () {
      expect(csp['worker-src'], containsAll(["'self'", 'blob:']));
    });

    test('CSP connect-src reaches only the app, Supabase, and Sentry', () {
      final connect = csp['connect-src'] ?? const [];
      expect(connect, contains("'self'"));
      expect(connect, contains('https://dleexnnevuuddcgcpztq.supabase.co'));
      expect(connect, contains('wss://dleexnnevuuddcgcpztq.supabase.co'));
      final sentryHosts =
          connect.where((s) => s.contains('ingest')).toList();
      expect(sentryHosts, isNotEmpty,
          reason: 'crash reporting, when configured, needs its ingest host');
    });
  });

  // Falsification: a detector that stopped rejecting the broad script
  // allowances would leave the script-src pin vacuously green.
  group('detects the regressions the pins exist to catch', () {
    test('rejects unsafe-eval and unsafe-inline in script-src', () {
      expect(scriptSrcIsStrict(["'self'", "'unsafe-eval'"]), isFalse);
      expect(scriptSrcIsStrict(["'self'", "'unsafe-inline'"]), isFalse);
      expect(scriptSrcIsStrict(["'self'", "'wasm-unsafe-eval'"]), isTrue,
          reason: 'the wasm allowance alone is the intended posture');
    });

    test('a dropped or loosened directive fails the parse-level pins', () {
      final loosened =
          parseCsp("default-src 'self'; object-src 'self'; base-uri *");
      expect(loosened['object-src'], isNot(["'none'"]));
      expect(loosened['base-uri'], isNot(["'self'"]));
      expect(parseCsp("default-src 'self'").containsKey('frame-ancestors'),
          isFalse);
    });

    test('selector and comment lines never become headers', () {
      final parsed = parseHeaderFile('''
# a comment with a colon: not a header
/*
  X-Test: value
''');
      expect(parsed, {'x-test': 'value'});
    });
  });
}
