import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/screenshots/manifest.dart' as screenshots;

/// Guards the issue #1105 home and feature pages and their claims ledger.
///
/// The site lives in this repo, which makes an unusual review contract
/// possible: every factual claim on lunarlog.app must cite the repo path or
/// issue that ships it, and a machine — not a reviewer's memory — can check
/// those citations. `site/claims.md` is the ledger; this file is the check:
///
/// - every `ships:` path in the ledger must exist (the acceptance
///   criterion "a site test that fails when a cited path no longer
///   exists");
/// - every claim carries at least one citation;
/// - every role name on the sharing page renders through the UiLabel ARB
///   component (#1106's pattern), so a rename in `lib/l10n/app_en.arb`
///   surfaces here and at the Astro build, never as stale prose;
/// - both invitation directions are present with equal weight;
/// - the page states plainly that sync is not end-to-end encrypted
///   (PRIVACY.md §6) and keeps the unshipped features unclaimed
///   (background health sync, store badges, waitlist/email capture).
///
/// These assertions read the source files the same way
/// `test/site/store_pages_test.dart` reads its pages: the pages are static
/// text, so their invariants are pinned as file-content tests.
void main() {
  group('site claims ledger (issue #1105)', () {
    late String ledger;

    /// Prose wraps across lines in the Astro sources, so phrase assertions
    /// run against a whitespace-flattened copy; a re-wrapped paragraph must
    /// not break the pin.
    String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

    /// The product-claiming pages and the route each is served at.
    /// `site/src/pages/sitemap.xml.ts` must carry the same list (asserted
    /// below), so the site cannot grow a claiming page outside it.
    const pages = <String, String>{
      '/': 'site/src/pages/index.astro',
      '/tracking': 'site/src/pages/tracking.astro',
      '/family-sharing': 'site/src/pages/family-sharing.astro',
      '/life-stage-modes': 'site/src/pages/life-stage-modes.astro',
      '/import': 'site/src/pages/import.astro',
      '/export': 'site/src/pages/export.astro',
      '/privacy-security': 'site/src/pages/privacy-security.astro',
    };

    setUpAll(() {
      // Normalize line endings: on a Windows checkout (core.autocrlf) the
      // working copy carries CRLF, on CI it is LF — the ledger must parse
      // identically in both.
      ledger =
          File('site/claims.md').readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('ledger parses into claims with page and citation fields', () {
      final claims = parseLedger(ledger);
      expect(claims, isNotEmpty, reason: 'site/claims.md has claim bullets');
      for (final claim in claims) {
        expect(claim.page, isNotNull,
            reason: 'claim has no `page:` field: ${claim.text}');
        expect(pages, contains(claim.page),
            reason: 'claim names unknown page ${claim.page}');
        final hasShips = claim.ships.isNotEmpty;
        final hasIssue = claim.issues.isNotEmpty;
        expect(hasShips || hasIssue, isTrue,
            reason: 'claim cites nothing: ${claim.text}');
        for (final issue in claim.issues) {
          expect(RegExp(r'^#\d+$').hasMatch(issue), isTrue,
              reason: 'issue citation is not #<number>: $issue');
        }
      }
    });

    test('every ledger-cited path exists (the #1105 acceptance criterion)',
        () {
      final missing = <String>[];
      for (final claim in parseLedger(ledger)) {
        for (final cited in claim.ships) {
          final path = cited;
          expect(path, isNot(contains(' ')),
              reason: 'cited path carries prose: "$cited"');
          if (!File(path).existsSync() && !Directory(path).existsSync()) {
            missing.add('${claim.page}: $path '
                '(cited by "${claim.text}")');
          }
        }
      }
      expect(missing, isEmpty,
          reason: 'ledger cites paths that no longer exist — '
              'update the ledger with the code that ships the claim now');
    });

    test('every claiming page is ledger-covered and exists', () {
      final claimedPages = parseLedger(ledger)
          .map((claim) => claim.page)
          .whereType<String>()
          .toSet();
      for (final entry in pages.entries) {
        expect(File(entry.value).existsSync(), isTrue,
            reason: '${entry.key} page file missing: ${entry.value}');
        expect(claimedPages, contains(entry.key),
            reason: '${entry.key} makes claims but has no ledger section');
      }
    });

    test('every UiLabel key in the site sources exists in the app ARB', () {
      final arb =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final astroSources = Directory('site/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.astro'))
          .toList();

      var usages = 0;
      for (final file in astroSources) {
        final source = file.readAsStringSync();
        for (final match
            in RegExp(r'<UiLabel\s[^>]*key="([^"]+)"').allMatches(source)) {
          usages++;
          final key = match.group(1)!;
          final value = arb[key];
          expect(value, isA<String>(),
              reason: '${file.path} renders UiLabel key "$key", '
                  'which is not a string in lib/l10n/app_en.arb — '
                  'the app renamed it; update the site in the same change');
          expect((value as String).isNotEmpty, isTrue,
              reason: 'ARB key $key is empty');
        }
      }
      expect(usages, greaterThanOrEqualTo(6),
          reason: 'the four role names plus the subject-invitation labels '
              'must render through UiLabel');
    });

    test('role names never appear as hardcoded site prose', () {
      final sharingPage = flat(
        File('site/src/pages/family-sharing.astro').readAsStringSync(),
      );
      // The page renders the names from the ARB (checked above); the point
      // of the component is that the literals do not live in the page.
      expect(sharingPage, isNot(contains('Primary Guardian')));
      expect(sharingPage, isNot(contains('Co-Parent')));
    });

    test('both invitation directions get equal weight', () {
      for (final path in const ['/', '/family-sharing']) {
        final source = File(pages[path]!).readAsStringSync();
        expect('class="direction-card"'.allMatches(source).length, 2,
            reason: '$path must carry exactly two direction cards');
      }
      final home = flat(File(pages['/']!).readAsStringSync());
      expect(home, contains('You track for yourself'));
      expect(home, contains('You set it up for someone else'));
      final sharing = flat(File(pages['/family-sharing']!).readAsStringSync());
      expect(sharing, contains('You track, and invite someone in'));
      expect(sharing, contains('You set up, and invite them in'));
    });

    test('sync is stated as not end-to-end encrypted, citing PRIVACY.md §6',
        () {
      final privacyPage = flat(
        File(pages['/privacy-security']!).readAsStringSync(),
      );
      expect(privacyPage, contains('not end-to-end encrypted'));
      expect(privacyPage, contains('cite: PRIVACY.md §6'));
      // The whole stance block the issue requires, in one pin.
      expect(
        privacyPage,
        contains('No advertising, no data brokers, no behavioral tracking'),
      );
      expect(privacyPage, contains('href="/privacy"'));
    });

    test('the full-policy claim names the app screen as a summary that '
        'links here, not "the same document" (issue #1164)', () {
      // The app's screen renders a 1.2k-char ARB summary, so the old
      // "the same document the app's own privacy dialog reads" wording did
      // not trace to shipped code. Both claiming pages now say the app
      // screen summarizes /privacy and links to it.
      for (final entry in const ['/', '/privacy-security']) {
        final source = flat(File(pages[entry]!).readAsStringSync());
        expect(source, contains('Privacy screen summarizes it and links here'),
            reason: entry);
        expect(source, isNot(contains('the same document')), reason: entry);
      }
      // …and the app side of the claim really ships: the summary screen
      // opens the canonical URL through the scheme-allowlisted launcher.
      final screen =
          File('lib/ui/settings/privacy_policy_screen.dart').readAsStringSync();
      expect(screen, contains("https://lunarlog.app/privacy"));
      expect(screen, contains('safeLaunchUrl'));
    });

    test('unshipped features stay unclaimed', () {
      for (final entry in pages.entries) {
        final source = flat(File(entry.value).readAsStringSync());
        // Background health sync is deferred (#993); the store listings are
        // not live (#830); the site collects nothing (#830 out-of-scope).
        expect(source, isNot(contains('background sync')),
            reason: entry.key);
        expect(source, isNot(contains('Download on the')),
            reason: entry.key);
        expect(source, isNot(contains('GET IT ON')), reason: entry.key);
        expect(source, isNot(contains('waitlist')), reason: entry.key);
        expect(source, isNot(contains('<form')), reason: entry.key);
      }
    });

    test('the default call to action stays the browser app', () {
      final home = File(pages['/']!).readAsStringSync();
      expect(home, contains('Use lunarlog in your browser'));
      expect(home, contains('https://app.lunarlog.app'));
    });

    test('every Screenshot usage names a manifest triple', () {
      final knownScreens =
          screenshots.kScreenshotScreens.map((s) => s.id).toSet();
      final knownDevices =
          screenshots.kScreenshotDevices.map((d) => d.id).toSet();
      final knownThemes =
          screenshots.ScreenshotTheme.values.map((t) => t.id).toSet();

      for (final entry in pages.entries) {
        final source = File(entry.value).readAsStringSync();
        for (final block
            in RegExp(r'<Screenshot[^>]*?>', dotAll: true).allMatches(source)) {
          final text = block.group(0)!;
          String attr(String name) =>
              RegExp('$name="([^"]+)"').firstMatch(text)?.group(1) ??
              (throw StateError(
                  '${entry.value}: Screenshot block lacks $name='));
          final screen = attr('screen');
          final device = attr('device');
          final theme = attr('theme');
          expect(knownScreens, contains(screen),
              reason: '${entry.value}: unknown screenshot screen "$screen"');
          expect(knownDevices, contains(device),
              reason: '${entry.value}: unknown screenshot device "$device"');
          expect(knownThemes, contains(theme),
              reason: '${entry.value}: unknown screenshot theme "$theme"');
        }
      }
    });

    test('pages ship zero client-side JavaScript', () {
      for (final entry in pages.entries) {
        final source = File(entry.value).readAsStringSync();
        expect(source, isNot(contains('<script')),
            reason: '${entry.key} grew a script tag');
      }
    });

    test('the new pages are wired into sitemap, axe, and Lighthouse', () {
      final sitemap =
          File('site/src/pages/sitemap.xml.ts').readAsStringSync();
      final axe = File('site/scripts/check-axe.mjs').readAsStringSync();
      final lighthouse = File('site/lighthouserc.cjs').readAsStringSync();
      for (final route in pages.keys) {
        if (route == '/') continue; // the home page is sitemap's "/" entry.
        expect(sitemap, contains('"$route"'), reason: route);
        expect(axe, contains('"$route/"'), reason: route);
        expect(
          lighthouse,
          contains('"http://localhost$route/"'),
          reason: route,
        );
      }
    });
  });
}

/// One parsed `- claim:` bullet from `site/claims.md`.
class LedgerClaim {
  LedgerClaim(this.text, this.page, this.ships, this.issues);

  final String text;
  final String? page;
  final List<String> ships;
  final List<String> issues;
}

/// Strips the parenthesized annotations from a ledger `ships:` line
/// *before* it is split on `;` — an annotation may itself contain
/// semicolons (`PRIVACY.md (§2.A "X"; §7 "Y")`), and it is prose, not
/// part of any path.
String stripAnnotations(String line) => line.replaceAll(
      RegExp(r'\([^)]*\)'),
      '',
    );

/// Parses the ledger's claim bullets: `- claim:` opens a claim; the
/// indented `page:` / `ships:` / `issue:` lines are its fields until the
/// next bullet, heading, or rule. Fenced code blocks (the ledger's format
/// example) are skipped entirely.
List<LedgerClaim> parseLedger(String source) {
  final claims = <LedgerClaim>[];
  String? text;
  String? page;
  final ships = <String>[];
  final issues = <String>[];
  var inCodeFence = false;

  void flush() {
    // Copy to a local: `text` is captured by this closure, so type
    // promotion does not apply to it directly.
    final current = text;
    if (current != null) {
      claims.add(LedgerClaim(current, page, List.of(ships), List.of(issues)));
    }
    text = null;
    page = null;
    ships.clear();
    issues.clear();
  }

  for (final line in source.split('\n')) {
    if (line.startsWith('```')) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (inCodeFence) continue;
    final claimMatch = RegExp(r'^- claim: (.*)$').firstMatch(line);
    if (claimMatch != null) {
      flush();
      text = claimMatch.group(1)!.trim();
      continue;
    }
    if (text == null) continue;
    final pageMatch = RegExp(r'^\s+page: (.*)$').firstMatch(line);
    if (pageMatch != null) {
      page = pageMatch.group(1)!.trim();
      continue;
    }
    final shipsMatch = RegExp(r'^\s+ships: (.*)$').firstMatch(line);
    if (shipsMatch != null) {
      ships.addAll(
        stripAnnotations(shipsMatch.group(1)!)
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
      );
      continue;
    }
    final issueMatch = RegExp(r'^\s+issue: (.*)$').firstMatch(line);
    if (issueMatch != null) {
      issues.addAll(issueMatch.group(1)!.split(';').map((s) => s.trim()));
      continue;
    }
    // A claim's fields end at the next bullet, heading, or rule.
    if (line.startsWith('- ') ||
        line.startsWith('## ') ||
        line.startsWith('---')) {
      flush();
    }
  }
  flush();
  return claims;
}
