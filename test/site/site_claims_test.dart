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
///   (PRIVACY.md §6) and keeps the genuinely unshipped features unclaimed
///   (store badges, waitlist/email capture — background health sync is NOT
///   one of them: it shipped in-app with issue #993 and the ledger must
///   never again list it as unshipped or deferred, issue #1306).
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

    // Issue #1395: the page kept telling visitors a signed-in browser
    // stores synced data and the session in browser storage, after #1384
    // shipped the opposite and rewrote PRIVACY.md §6 to say so.
    test('the browser paragraph states the nothing-at-rest posture, citing '
        'the bullet that exists', () {
      final privacyPage = flat(
        File(pages['/privacy-security']!).readAsStringSync(),
      );
      expect(
        privacyPage,
        contains('cite: PRIVACY.md §6 "Browser Client (Web)"'),
      );
      expect(
        File('PRIVACY.md').readAsStringSync(),
        contains('- **Browser Client (Web):**'),
        reason: 'the page cites this bullet by name; it must exist',
      );
      expect(privacyPage, contains('it keeps nothing at rest'));
      expect(
        privacyPage,
        contains('No copy of your entries is ever written to browser storage'),
      );
      expect(privacyPage, contains('a cookie that no script on the page can read'));
      // The retired Flutter build's posture, in the page's old words.
      expect(privacyPage, isNot(contains('Signed-In Browser Build')));
      expect(
        privacyPage,
        isNot(contains('keeps synced data and the session in browser storage')),
      );
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

    test('the Health Connect import claim covers flow and spotting (#1180)',
        () {
      // Issue #1180: the type axis of the health-import read. On Android,
      // Health Connect returns menstrual-flow AND intermenstrual-bleeding
      // records — the latter stored as spotting observations, the shape
      // the app logs spotting in (PRIVACY.md §4) — so a flow-only claim
      // understates a health-data read, the one direction a store-facing
      // disclosure must not err in. The /import page, its cite comment,
      // and its ledger claim must all keep the spotting half.
      final importPage =
          flat(File('site/src/pages/import.astro').readAsStringSync());
      expect(importPage, contains('flow and spotting history'));
      expect(importPage, contains('intermenstrual-bleeding'));
      expect(
        importPage,
        isNot(contains('on Android, the same from Health Connect')),
        reason: 'the narrowing the page used to carry, verbatim',
      );
      // The ledger claim paraphrases the page; the two cannot drift apart.
      expect(flat(ledger), contains('flow and spotting history'));
      expect(
        flat(ledger),
        isNot(contains('Android) imports read menstrual-flow history')),
      );
      // The facts the claim paraphrases, read from their sources of record.
      final privacy = flat(File('PRIVACY.md').readAsStringSync());
      expect(
        privacy,
        contains('read menstrual flow and intermenstrual-bleeding records'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android.permission.health.READ_INTERMENSTRUAL_BLEEDING'),
        reason: 'the permission behind the Android spotting read',
      );
    });

    test('the background-import disclosure states the shipped truth (#993)',
        () {
      // Issue #993 shipped background imports; the pages and the ledger
      // used to deny them outright ("no background read and no schedule",
      // "no background reading — no observer, no timer", "nothing runs in
      // the background or on a schedule"). The same discipline #1180
      // applied to the type axis applies to the trigger axis: a retired
      // denial may not resurface, and the new truth must actually claim
      // the shipped background behavior — never the reverse narrowing.
      final importPage =
          flat(File('site/src/pages/import.astro').readAsStringSync());
      expect(importPage, contains('in the background'));
      expect(importPage, contains('You start the first import yourself'));
      // Issue #1304: binding alone opens nothing — the shipped gate (issue
      // #1215) is the COMPLETED first import, so the page must state the
      // condition its own cite comment names (PRIVACY.md §4), and the
      // retired after-binding shorthand may not resurface.
      expect(
        importPage,
        contains('and that first import has completed'),
        reason: 'the background pass waits for the completed first import, '
            'not merely a bound profile (PRIVACY.md §4, issue #1304)',
      );
      expect(
        importPage,
        isNot(contains('Settings; after that, the same import')),
        reason: 'the retired after-binding shorthand, verbatim (issue #1304)',
      );
      // Issue #1365: the lede used to hand the background pass to every
      // source, Clue included — it belongs to the health stores alone;
      // the Clue import is a one-off file pick.
      expect(
        importPage,
        contains(
          'Apple Health and Health Connect imports then keep themselves '
          'current in the background',
        ),
        reason: 'the lede scopes the background pass to the health '
            'stores; Clue is a one-off file import (issue #1365)',
      );
      expect(
        importPage,
        isNot(contains('no background read and no schedule')),
        reason: 'the pre-#993 denial, verbatim',
      );
      // Issue #1340: the import.astro lede still carried the pre-#993
      // "always started by you" absolute after the body had been flipped
      // (the #1304 round fixed the body and the ledger, not the lede), and
      // the home page's import sentence carried it too while its ledger
      // row claimed the background pass on the page's behalf. Both pages
      // now state the bounded truth; the retired absolute may not
      // resurface on either, and the home page must keep carrying the
      // claim its ledger row asserts for it.
      final homePage = flat(File(pages['/']!).readAsStringSync());
      expect(
        importPage,
        contains('The first import is started by you'),
        reason: "the /import lede states the user-started first import, "
            "not the pre-#993 absolute (issue #1340)",
      );
      expect(
        homePage,
        contains('you start the first import'),
        reason: "the home page's import sentence states the user-started "
            "first import (issue #1340)",
      );
      expect(
        homePage,
        contains('and that first import has completed'),
        reason: 'the home page states the completed-first-import gate, '
            'not binding alone (PRIVACY.md §4, issue #1340)',
      );
      // Issue #1365: the background pass belongs to the health stores
      // alone — the Clue import is a one-off file pick with no observer,
      // worker, or schedule — so the home page must name the two health
      // stores when it claims the pass, not let it read as a Clue
      // promise.
      expect(
        homePage,
        contains(
          'Apple Health and Health Connect imports then keep themselves '
          'current in the background',
        ),
        reason: "the home page's background pass is scoped to the health "
            'stores; Clue is a one-off file import (issue #1365)',
      );
      expect(
        homePage,
        isNot(contains('the same import keeps itself current')),
        reason: 'the unscoped phrasing that promised the background pass '
            'for Clue too, verbatim (issue #1365)',
      );
      for (final page in [homePage, importPage]) {
        expect(
          page,
          isNot(contains('always started by you')),
          reason: 'the pre-#993 absolute, verbatim (issue #1340)',
        );
      }
      final guide = flat(
        File('site/src/pages/guides/moving-your-data.astro')
            .readAsStringSync(),
      );
      expect(guide, contains('in the background'));
      // Issue #1304: the guide carries the gate in §4's own words — in the
      // lede and in the background list item alike — not the retired
      // after-start shorthand.
      expect(
        guide,
        contains('and you have run the first import yourself'),
        reason: 'the §4 gate framing, in both guide spans (issue #1304)',
      );
      expect(
        guide,
        isNot(contains('Settings. After that, the same import')),
        reason: 'the retired after-start shorthand, verbatim (issue #1304)',
      );
      expect(
        guide,
        isNot(contains('no background reading')),
        reason: 'the pre-#993 denial, verbatim',
      );
      expect(guide, isNot(contains('no observer, no timer')));
      // The ledger claim paraphrases the pages; the retired stance may not
      // survive there either, and the shipped triggers must be cited.
      expect(
        flat(ledger),
        isNot(contains('nothing runs in the background or on a schedule')),
        reason: 'the pre-#993 ledger claim, verbatim',
      );
      expect(
        flat(ledger),
        contains('keeps itself current in the background'),
      );
      // Issue #1365: the home-page row carries the health-store scoping —
      // it names the two health stores for the background pass and pins
      // the Clue import as a one-off file pick, so the ledger cannot
      // promise Clue a background current-keeping it does not have.
      expect(
        flat(ledger),
        contains(
          'Apple Health and Health Connect imports then keep themselves '
          'current in the background',
        ),
        reason: 'the home-page ledger row scopes the background pass to '
            'the health stores; Clue is a one-off file import '
            '(issue #1365)',
      );
      // Issue #1304: both claim rows carrying the background pass must
      // state the completed-first-import condition the inventory paragraph
      // already had — binding-alone shorthand may not come back.
      expect(
        flat(ledger),
        contains('bound and its first import has completed'),
        reason: 'the claim rows state the completed-first-import gate '
            '(PRIVACY.md §4, issue #1304)',
      );
      expect(
        flat(ledger),
        isNot(contains('once a profile is bound it keeps itself current')),
        reason: 'the retired binding-alone shorthand, verbatim (issue #1304)',
      );
      expect(
        flat(ledger),
        isNot(contains('once a profile is bound, the same import keeps')),
        reason: 'the retired binding-alone shorthand, verbatim (issue #1304)',
      );
      // The flip missed the ledger's own inventory paragraph (issue #1306):
      // it kept listing the shipped background pass as unshipped —
      // "Unshipped features are deliberately absent: background
      // health-platform sync (issue #993, deferred) ..." — contradicting
      // the Home and Import claim rows and PRIVACY.md §4. The framing is
      // the pin, not one retired sentence: every sentence naming the
      // feature must frame it as shipped, so a re-wrapped or re-worded
      // "deferred"/"unshipped"/"deliberately absent" phrasing fails too.
      expect(
        flat(ledger),
        isNot(contains(
          'deliberately absent: background health-platform sync',
        )),
        reason: 'the retired inventory framing, verbatim (issue #1306)',
      );
      expect(
        flat(ledger),
        contains('Background health-platform sync ships in-app'),
        reason: 'the inventory paragraph states the shipped truth '
            '(issue #993)',
      );
      for (final window in RegExp(
        r'[^.]*[Bb]ackground health[^.]*\.',
      ).allMatches(flat(ledger))) {
        final sentence = window.group(0)!;
        final lowercased = sentence.toLowerCase();
        for (final banned in const [
          'deferred',
          'unshipped',
          'deliberately absent',
        ]) {
          expect(
            lowercased,
            isNot(contains(banned)),
            reason: 'background health-platform sync shipped (issue #993); '
                'the ledger may not frame it as "$banned": "$sentence" '
                '(issue #1306)',
          );
        }
      }
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('enableBackgroundDelivery'),
        reason: 'the iOS trigger behind the claim',
      );
      expect(
        File('android/app/src/main/kotlin/com/wjdavis5/lunarlog/'
                'HealthBackgroundImportWorker.kt')
            .existsSync(),
        isTrue,
        reason: 'the Android trigger the ledger cites must exist',
      );
    });

    test('unshipped features stay unclaimed', () {
      for (final entry in pages.entries) {
        final source = flat(File(entry.value).readAsStringSync());
        // Background health sync shipped in-app with #993, but the store
        // listings are not live (#830) and the site pages (unchanged here)
        // still make no such claim -- the guard stays conservative: a
        // marketing claim must be added deliberately, not drift in. The
        // site collects nothing (#830 out-of-scope).
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
      // The address itself lives in one module, which the home page and
      // every in-text link read it from.
      expect(home, contains('const browserUrl = WEB_APP_URL;'));
      expect(
        File('site/src/lib/web-app.mjs').readAsStringSync(),
        contains('export const WEB_APP_URL = "https://app.lunarlog.app";'),
      );
    });

    // In October 2026 app.lunarlog.app answered a Cloudflare error page for
    // hours while the home page's one button, and links on three other
    // pages, went on leading there. The deploy now asks the address first
    // and the site says "not available right now" in their place.
    test('no page links to the browser version except through the switch', () {
      final direct = RegExp(r'href="https://app\.lunarlog\.app');
      final offenders = <String>[];
      for (final file in Directory('site/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.astro'))) {
        if (direct.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'a hard-coded link stays up when the address is down: use '
            '<WebAppLink /> in running text, or webAppIsLive() as the home '
            'page does',
      );

      final home = File(pages['/']!).readAsStringSync();
      expect(home, contains('const browserLive = webAppIsLive();'));
      expect(home, contains('The browser version is not available right now.'));
      final link =
          File('site/src/components/WebAppLink.astro').readAsStringSync();
      expect(link, contains('webAppIsLive()'));
      expect(link, contains('(not available right now)'));
    });

    test('the deploy asks the address before it builds, and rebuilds when '
        'the browser version deploys', () {
      final deploy =
          File('.github/workflows/site-deploy.yml').readAsStringSync();
      final probe = deploy.indexOf('node scripts/probe-web-app.mjs');
      final build = deploy.indexOf('npm run build');
      expect(probe, greaterThan(0));
      expect(build, greaterThan(probe),
          reason: 'the answer has to be in the environment before the build');
      expect(deploy, contains(r'echo "LUNARLOG_WEB_APP_LIVE=${live}" >> "$GITHUB_ENV"'));
      expect(deploy, contains("workflows: ['Web app staging deploy (Cloudflare Workers)']"));
      // The name it waits for has to be the workflow's real name.
      expect(
        File('.github/workflows/webapp-deploy.yml').readAsStringSync(),
        contains('name: Web app staging deploy (Cloudflare Workers)'),
      );
      // And the down build is exercised on every site change, not only
      // during an outage.
      final ci = File('.github/workflows/site.yml').readAsStringSync();
      expect(ci, contains("LUNARLOG_WEB_APP_LIVE: 'false'"));
      expect(ci, contains('node scripts/check-web-app-down.mjs'));
    });

    // Issue #1208 put a browser-width capture under the CTA, captioned as
    // what the button opens; the #1258 cutover made that picture the
    // Flutter app at desktop width — a screen the browser version does
    // not have — and #1432 removed it. Issue #1431 puts a real one back:
    // the React web client's own signed-in home, captured from its e2e
    // fixture render (webapp/e2e/browser-home-capture.spec.ts) at build
    // time. The site test pins the wiring as well as the figure: the
    // capture must run in both site workflows, before the Astro build.
    void verifyBrowserFigureWiring(String home) {
      final blocks = RegExp(r'<Screenshot[^>]*?>', dotAll: true)
          .allMatches(home)
          .map((match) => match.group(0)!)
          .toList();
      final browserBlocks = blocks
          .where((block) => block.contains('device="browser"'))
          .toList();
      expect(browserBlocks, hasLength(1),
          reason: 'the home page carries exactly one browser-class capture');
      final block = browserBlocks.single;
      expect(block, contains('screen="today"'),
          reason: 'the capture shows the home the CTA lands on');
      expect(block, contains('loading="lazy"'),
          reason: 'the hero eager/LCP slot is taken; a second near-the-fold '
              'PNG must lazy-load or the 0.90 floor loses its margin '
              '(issue #1172)');
      // The issue #1172 convention: the page's FIRST screenshot stays the
      // eager LCP candidate, so the browser capture must sit after it in
      // the source (site/scripts/lighthouse-budget.test.mjs pins the same
      // rule from the site side).
      expect(blocks.first, contains('loading="eager"'),
          reason: 'the hero phone capture must remain the eager one');
      // The caption names what the picture really is — the web client —
      // so the Flutter-app caption #1432 removed cannot come back, and
      // the cite names the capture script that produces the PNG. The
      // region runs from the cite comment (which sits above the block)
      // to the figure's end, so both pins travel with the figure.
      final blockIndex = home.indexOf(browserBlocks.single);
      final cite = home.lastIndexOf('<!-- cite:', blockIndex);
      final figureEnd = home.indexOf('</figure>', blockIndex);
      expect(cite, greaterThan(0), reason: 'the figure carries a cite');
      expect(figureEnd, greaterThan(blockIndex),
          reason: 'the figure closes');

      // Issue #1657: verify cite belongs directly to this figure and doesn't
      // skip across intervening screenshots, earlier figures, or section boundaries.
      final preamble = home.substring(cite, blockIndex);
      expect(preamble, isNot(contains('<Screenshot')),
          reason: 'the cite belongs directly to the browser figure, with no intervening screenshots');
      expect(preamble, isNot(contains('</figure>')),
          reason: 'the cite comment sits within the same figure boundary');
      expect(preamble, isNot(contains('<section')),
          reason: 'no section boundary sits between the cite and the browser figure');

      final figureRegion = home.substring(cite, figureEnd);
      expect(flat(figureRegion), contains('the React web client'));
      expect(figureRegion, contains('browser-home-capture.spec.ts'));
      // Up-variant only, like the button it backs (issue #1482): the
      // source guards the figure behind browserLive, so the down build
      // drops it — a caption quoting the button's label in the down
      // build is exactly what check-web-app-down.mjs reads as "the
      // button is still there". The guard must still be open at the
      // block, i.e. the figure sits inside the conditional expression.
      // (The hero's ternary reads `browserLive ?`, so `browserLive &&`
      // names this guard and only this guard.)
      final guard = home.lastIndexOf('browserLive && (', blockIndex);
      expect(guard, greaterThan(0),
          reason: 'the browser figure is guarded by browserLive');

      // Issue #1657: allow whitespace when checking if the guard closed early.
      // In Astro formatting, `)\n  }` closes the JSX block across lines.
      expect(
        home.substring(guard, blockIndex),
        isNot(matches(RegExp(r'\)\s*\}'))),
        reason: 'the browser figure sits inside the browserLive guard — '
            'unconditional rendering puts the button-label caption into '
            'the down build',
      );
      final afterFigure = home.substring(
        figureEnd,
        home.indexOf('<section', figureEnd),
      );
      expect(
        afterFigure,
        matches(RegExp(r'\)\s*\}')),
        reason: 'the browserLive guard closes after the figure',
      );
    }

    test('the browser CTA is backed by a capture of the web client itself '
        '(issue #1431)', () {
      final home = File(pages['/']!).readAsStringSync();
      verifyBrowserFigureWiring(home);
    });

    test('the browser figure guard assertion catches an early close with whitespace or missing cite (issue #1657)', () {
      final validHome = File(pages['/']!).readAsStringSync();

      // Negative case 1: the guard closes on separate lines before the figure.
      // Prior to issue #1657, `contains(')}')` failed to detect `)\n  }`.
      final earlyClosed = validHome.replaceFirst(
        'browserLive && (',
        'browserLive && (\n    )\n  }',
      );
      expect(
        () => verifyBrowserFigureWiring(earlyClosed),
        throwsA(isA<TestFailure>()),
        reason: 'closing the guard before the figure must fail the test',
      );

      // Negative case 2: the cite comment is removed.
      // Prior to issue #1657, `lastIndexOf('<!-- cite:')` fell back to the
      // preceding section's cite and passed silently.
      final missingCite = validHome.replaceFirst(
        RegExp(r'<!-- cite: webapp/e2e/browser-home-capture\.spec\.ts[^>]*?-->'),
        '',
      );
      expect(
        () => verifyBrowserFigureWiring(missingCite),
        throwsA(isA<TestFailure>()),
        reason: 'omitting the browser figure cite comment must fail the test',
      );
    });

    test('the site workflows capture the web client before the site build '
        '(issue #1431)', () {
      const captureScript = 'browser-home-capture.spec.ts';
      const captureOut = 'LUNARLOG_BROWSER_CAPTURE_OUT';
      // Each workflow's site-build step — the Astro build the figure must
      // ride into dist/ — named precisely, so the webapp build inside the
      // capture sequence itself cannot satisfy the ordering pin.
      const buildMarkers = <String, String>{
        '.github/workflows/site.yml': 'Build and type-check the site',
        '.github/workflows/site-deploy.yml': 'name: Build the site',
      };
      buildMarkers.forEach((workflow, buildMarker) {
        final source = File(workflow).readAsStringSync();
        expect(source, contains(captureScript),
            reason: '$workflow must run the capture');
        expect(source, contains(captureOut),
            reason: '$workflow must aim the capture at '
                'site/public/screenshots/');
        // In place of the Flutter browser render means after it: the
        // capture step follows the screenshot step, and both precede the
        // Astro build the figure rides into dist/. The needle is the
        // capture's own invocation (not the script's name, which the
        // path-filter comments may also carry).
        const captureInvocation =
            'npx playwright test e2e/browser-home-capture.spec.ts';
        final flutter = source.indexOf('npm run screenshots');
        final capture = source.indexOf(captureInvocation);
        final build = source.indexOf(buildMarker);
        expect(flutter, greaterThan(0), reason: workflow);
        expect(build, greaterThan(0), reason: workflow);
        expect(capture, greaterThan(flutter),
            reason: '$workflow: the web client capture follows the Flutter '
                'renders');
        expect(build, greaterThan(capture),
            reason: '$workflow: the PNGs exist before the Astro build');
      });
    });

    test('site-deploy.yml guards the browser capture sequence behind LUNARLOG_WEB_APP_LIVE (issue #1656)', () {
      final deploySource =
          File('.github/workflows/site-deploy.yml').readAsStringSync();
      const captureSteps = [
        "name: Compile the browser version's domain module",
        "name: Install the web app's dependencies and Playwright Chromium",
        'name: Build the browser version',
        "name: Capture the browser version's home screenshot",
        'name: Verify the browser home screenshot was captured',
      ];
      for (final step in captureSteps) {
        final stepIndex = deploySource.indexOf(step);
        expect(stepIndex, greaterThan(0), reason: 'missing step $step');
        final nextStepIndex =
            deploySource.indexOf('- name:', stepIndex + step.length);
        final stepBlock = deploySource.substring(
          stepIndex,
          nextStepIndex > 0 ? nextStepIndex : deploySource.length,
        );
        expect(
          stepBlock,
          contains("if: env.LUNARLOG_WEB_APP_LIVE != 'false'"),
          reason: '$step must skip when the browser version is down (issue #1656)',
        );
      }
    });

    test("Screenshot.astro's kDevices mirror carries every manifest device "
        'at its PNG size', () {
      // The component's doc comment promises the mirror fails when it and
      // the manifest drift; its build-time check only covers ids, so the
      // pixel sizes are pinned here (test/tool/screenshots/manifest_test.dart
      // pins the same numbers on the manifest side). Issue #1208: the
      // browser entry must record the PNG size (1280x800 @1.5 DPR), not
      // the viewport.
      final component =
          File('site/src/components/Screenshot.astro').readAsStringSync();
      final tableMatch =
          RegExp(r'const kDevices[^;]*?};', dotAll: true).firstMatch(component);
      expect(tableMatch, isNotNull,
          reason: 'Screenshot.astro still declares kDevices');
      final table = tableMatch!.group(0)!;
      for (final device in screenshots.kScreenshotDevices) {
        final entry = RegExp(
          "['\"]?${device.id}['\"]?\\s*:\\s*\\[(\\d+),\\s*(\\d+)\\]",
        ).firstMatch(table);
        expect(entry, isNotNull,
            reason: 'kDevices misses ${device.id} — the mirror and the '
                'manifest have drifted');
        expect(int.parse(entry!.group(1)!), device.pngWidth,
            reason: '${device.id}: kDevices width must be the PNG width');
        expect(int.parse(entry.group(2)!), device.pngHeight,
            reason: '${device.id}: kDevices height must be the PNG height');
      }
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
