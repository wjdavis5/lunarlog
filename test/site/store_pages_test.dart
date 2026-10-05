import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the issue #1102 store-facing web pages and worksheet rows.
///
/// Play's Data safety form requires a public **Delete account URL** and App
/// Store Connect requires a **Support URL**; both now point at pages built
/// from this repo's `site/` Astro project. The issue's acceptance criteria:
/// every factual claim about deletion cites `PRIVACY.md` §7 or the
/// `delete-account` Edge Function, the worksheet carries the two new URL
/// rows, and the #1100 owner inputs (the public support address and the
/// response-time commitment) are left as clearly-marked pending rather than
/// invented.
///
/// These assertions read the source files the same way
/// `test/domain/sharing/link_artifacts_test.dart` reads its hosted
/// artifacts: the pages are static text, so their invariants are pinned as
/// file-content tests.
void main() {
  group('site store pages (issue #1102)', () {
    late String deleteAccountPage;
    late String supportPage;
    late String sitemap;
    late String axePages;
    late String lighthouseConfig;
    late String storeDeclarations;

    /// The Astro sources wrap prose across lines, so phrase assertions run
    /// against a whitespace-flattened copy; a re-wrapped paragraph must not
    /// break the pin.
    String flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

    setUpAll(() {
      deleteAccountPage = flat(
        File('site/src/pages/delete-account.astro').readAsStringSync(),
      );
      supportPage = flat(
        File('site/src/pages/support.astro').readAsStringSync(),
      );
      sitemap = File('site/src/pages/sitemap.xml.ts').readAsStringSync();
      axePages = File('site/scripts/check-axe.mjs').readAsStringSync();
      lighthouseConfig = File('site/lighthouserc.cjs').readAsStringSync();
      storeDeclarations =
          File('docs/ops/store-declarations.md').readAsStringSync();
    });

    test('both pages exist and render through the shared layout', () {
      expect(deleteAccountPage, contains('import BaseLayout'));
      expect(supportPage, contains('import BaseLayout'));
      // One h1 per page, matching the page's purpose.
      expect(deleteAccountPage, contains('<h1 class="doc__title">'));
      expect(supportPage, contains('<h1 class="doc__title">'));
    });

    test('delete page walks the real in-app flow, per platform', () {
      // The steps must match the shipped UI: More tab → Settings →
      // Account → Delete account (lib/ui/settings/settings_screen.dart,
      // lib/ui/account/account_section.dart), identical on iOS and Android.
      expect(deleteAccountPage, contains('Delete from inside the app'));
      expect(deleteAccountPage, contains('iPhone'));
      expect(deleteAccountPage, contains('Android'));
      expect(deleteAccountPage, contains('app.lunarlog.app'));
      expect(deleteAccountPage, contains('<strong>More</strong>'));
      expect(deleteAccountPage, contains('<strong>Settings</strong>'));
      expect(deleteAccountPage, contains('<strong>Account</strong>'));
      expect(deleteAccountPage, contains('<strong>Delete account</strong>'));
      // The dialog's escape hatches (lib/ui/account/delete_account_dialog.dart).
      expect(deleteAccountPage, contains('<strong>Export first</strong>'));
      expect(
        deleteAccountPage,
        contains('<strong>Transfer ownership first</strong>'),
      );
      // Deletion is immediate, not a reviewed request (PRIVACY.md §7).
      expect(
        deleteAccountPage,
        contains('normally gone by the time the confirmation completes'),
      );
    });

    // The browser version is the React web client. It has no More tab and
    // no Settings screen: deletion is a card on its Account page, reached
    // from the header. The page used to say the phone steps applied to the
    // browser too, which sent a reader looking for a tab that is not
    // there, on the page a store links to for account deletion.
    test('delete page gives the browser version its own steps', () {
      expect(
        deleteAccountPage,
        isNot(contains('iPhone, Android, and the browser version')),
        reason: 'the phone steps (More, Settings) do not exist in the browser',
      );
      final start = deleteAccountPage.indexOf('<section id="browser">');
      expect(start, greaterThanOrEqualTo(0));
      final browser = deleteAccountPage.substring(
        start,
        deleteAccountPage.indexOf('</section>', start),
      );
      expect(browser, contains('Delete from the browser version'));
      expect(browser, contains('https://app.lunarlog.app'));
      // Every control is named through UiLabel, so a renamed label fails
      // the site build instead of leaving a stale instruction.
      expect(browser, contains('<UiLabel key="accountSectionTitle" />'));
      expect(browser, contains('<UiLabel key="yourDataExportTitle" />'));
      expect(browser, contains('<UiLabel key="accountSectionDelete" />'));
      expect(
        browser,
        contains('<UiLabel key="accountDeleteDialogConfirm" />'),
      );
      expect(browser, isNot(contains('<strong>More</strong>')));
      expect(browser, isNot(contains('<strong>Settings</strong>')));
      // The claim is tied to the client that ships it.
      expect(browser, contains('webapp/src/pages/AccountPage.tsx'));
      // The phone section links down to it.
      expect(deleteAccountPage, contains('<a href="#browser">'));
    });

    test('delete page covers what is deleted, kept, shared, and minors', () {
      // The issue's required sections, in the issue's own terms.
      expect(deleteAccountPage, contains('What is deleted'));
      expect(deleteAccountPage, contains('What is kept'));
      expect(deleteAccountPage, contains('Shared profiles'));
      expect(deleteAccountPage, contains("A minor's profile"));
      expect(deleteAccountPage, contains('Deleting less than everything'));
      expect(deleteAccountPage, contains('Without the app'));

      // Shared profiles: owned profile + its other guardians go; profiles
      // owned by others survive with re-attributed entries
      // (delete_account_data() step 0, PRIVACY.md §7).
      expect(deleteAccountPage, contains('lose access'));
      expect(deleteAccountPage, contains('re-attributed to its owner'));

      // Minor's profile after an ownership transfer (PRIVACY.md §5,
      // two-stage custodian model).
      expect(deleteAccountPage, contains('does not touch'));
      expect(deleteAccountPage, contains('owns minor profiles'));

      // Health-store writes stay on the device (the dialog's guardian note).
      expect(deleteAccountPage, contains('health store'));

      // Partial deletion: per-entry/profile deletion and the single-ticket
      // email path with its screenshot caveat (PRIVACY.md §7,
      // store-declarations.md §5).
      expect(
        deleteAccountPage,
        contains('without closing your account'),
      );
      expect(
        deleteAccountPage,
        contains('screenshot'),
      );
    });

    // Issue #1395's bug class on this page: it said the browser version
    // holds a copy of your data. The React client keeps nothing at rest.
    test('delete page does not claim the browser holds a copy', () {
      final page = flat(deleteAccountPage);
      expect(page, isNot(contains('the copy the browser holds')));
      expect(page, contains('The browser version keeps no copy to begin with'));
      expect(page, contains('cite: PRIVACY.md §6 "Browser Client (Web)"'));
    });

    test('every deletion claim carries a source citation', () {
      // The acceptance criterion: claims cite PRIVACY.md §7 or the Edge
      // Function. Each cite comment names its source of record; the test
      // pins the ones that must exist so a rewrite cannot silently drop
      // them.
      for (final citation in <String>[
        'cite: PRIVACY.md §7',
        'cite: PRIVACY.md §5',
        'supabase/functions/delete-account/index.ts',
        'supabase/migrations/20260905110000_account_deletion.sql',
        'lib/ui/account/delete_account_dialog.dart',
      ]) {
        expect(deleteAccountPage, contains(citation), reason: citation);
      }
      // The visible footer ties the page back to the policy.
      expect(deleteAccountPage, contains('our privacy policy'));
    });

    test('support page leads with in-app feedback and stays honest', () {
      // In-app feedback first (issue #6 surface: Settings → Send feedback,
      // replies in Support history).
      expect(supportPage, contains('Send feedback from the app'));
      expect(supportPage, contains('<strong>Send feedback</strong>'));
      expect(supportPage, contains('Support history'));
      expect(supportPage, contains('Contact support'));

      // The FAQ links the deletion walkthrough instead of duplicating it.
      expect(supportPage, contains('const deleteAccountUrl ='));
      expect(supportPage, contains('"/delete-account"'));

      // No contact form: the site collects nothing (#830 out-of-scope).
      expect(supportPage, isNot(contains('<form')));

      // The guides exist (#1106): the FAQ links them instead of
      // duplicating them, and the pending-TODO state is gone. The links
      // point at real pages — site.yml's internal-link check fails on a
      // missing target, so a renamed guide fails CI rather than 404ing.
      expect(supportPage, contains('href="/guides/household-setup/"'));
      expect(supportPage, contains('href="/guides/inviting-someone/"'));
      expect(supportPage, contains('href="/guides/moving-your-data/"'));
      expect(supportPage, isNot(contains('TODO(#1106)')));
    });

    test('health-import answer states the full-history fact (#1153)', () {
      // Issue #1153: the answer used to say the import covers "the last
      // 30 days" — a fact PRIVACY.md's change history (September 21, 2026)
      // and the app itself retired in issue #992. A page written for the
      // store listing must not understate the read scope of a health-data
      // permission, so the stale window may not appear anywhere on the
      // page, in either phrasing.
      expect(supportPage, isNot(contains('30 days')));
      expect(supportPage, isNot(contains('30-day')));

      // The full-history wording the issue expects, plus the invariant
      // that travels with it (never overwrite a hand-logged value).
      expect(supportPage, contains('as far back as your health app has it'));
      expect(
        supportPage,
        contains('never overwrite a value you logged by hand'),
      );
      // The cite comment points at the documents of record and carries
      // the issue that lifted the cap, not the stale fact itself.
      expect(supportPage, contains('issue #992'));

      // The shared facts the answer paraphrases, read from their sources
      // of record so the page and the app cannot drift apart again.
      final arb = RegExp(
        r'"healthSyncFullHistoryNote":\s*"([^"]*)"',
      ).firstMatch(File('lib/l10n/app_en.arb').readAsStringSync())!;
      expect(
        arb.group(1)!,
        contains('everything the health store makes available'),
      );
      expect(arb.group(1)!, isNot(contains('30 days')));
      expect(
        File('lib/domain/health/health_import.dart').readAsStringSync(),
        contains('const int kHealthImportPageSize = 500'),
        reason: 'the paging constant behind the paged full-history read',
      );

      // AGENTS.md carried the same stale phrase and seeded the page's
      // wording (issue #1153); it must not inherit it back.
      expect(
        File('AGENTS.md').readAsStringSync(),
        isNot(contains('bounded to the last 30 days')),
      );
    });

    test('health-import answer keeps the spotting half of the '
        'Health Connect read (#1180)', () {
      // Issue #1180: the #1153 rewrite fixed the time axis ("30 days" →
      // full history) but narrowed the type axis to "menstrual-flow
      // history" for both platforms. On Android the import also reads
      // intermenstrual-bleeding records — stored as spotting observations,
      // the same shape the app logs spotting in (PRIVACY.md §4) — and the
      // site's own guide already said "flow and spotting". An understated
      // read scope is the one direction a health-data disclosure must not
      // err in, so the flow-only qualifier may not be applied to both
      // platforms again.
      expect(
        supportPage,
        contains('flow and spotting history from Health Connect'),
      );
      expect(
        supportPage,
        isNot(contains(
          'menstrual-flow history from Apple Health or Health Connect',
        )),
        reason: 'the #1153 type-axis narrowing, verbatim',
      );
      // The cite comment carries the spot-worthiness note naming the
      // Health Connect read types, so a rewrite that reads only the
      // ledger annotation cannot re-narrow the axis either.
      expect(supportPage, contains('intermenstrual-bleeding'));
      expect(supportPage, contains('READ_INTERMENSTRUAL_BLEEDING'));

      // The facts the answer paraphrases, read from their sources of
      // record so the page and the app cannot drift apart.
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
      // The guide (moving-your-data.astro) always carried the correct
      // per-platform split; the two pages must agree.
      final guide = flat(
        File('site/src/pages/guides/moving-your-data.astro')
            .readAsStringSync(),
      );
      expect(guide, contains('flow and spotting'));
    });

    test('health-import answer states the background-trigger truth (#993)',
        () {
      // Issue #993 shipped background imports; the answer used to deny
      // them outright ("It's user-initiated only; lunarlog never reads
      // your health store in the background"). A retired denial may not
      // survive the feature it denies: the answer now states the bounded
      // truth — the FIRST import is user-initiated, and once a profile is
      // bound the same import keeps itself current in the background,
      // never prompting, never writing, stopping on unbind or revocation.
      expect(supportPage, contains('in the background'));
      expect(supportPage, contains('You start the first import yourself'));
      // Issue #1304: binding alone opens nothing — the shipped gate (issue
      // #1215) is the COMPLETED first import, so the answer must state
      // that condition, in PRIVACY.md §4's framing, and may not revert to
      // the retired binding-alone shorthand.
      expect(
        supportPage,
        contains('and that first import has completed'),
        reason: 'the background pass waits for the completed first import, '
            'not merely a bound profile (PRIVACY.md §4, issue #1304)',
      );
      expect(
        supportPage,
        isNot(contains('once a profile is bound, the same import')),
        reason: 'the retired binding-alone shorthand, verbatim (issue #1304)',
      );
      expect(supportPage, isNot(contains("It's user-initiated only")),
          reason: 'the pre-#993 denial, verbatim');
      expect(supportPage, isNot(contains('never reads your')));
      // The page cites the feature that ships the claim.
      expect(supportPage, contains('#993'));
      // The facts the answer paraphrases, read from their sources of
      // record so the page and the app cannot drift apart.
      final privacy = flat(File('PRIVACY.md').readAsStringSync());
      expect(
        privacy,
        contains('same import pass can also run in the background'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND'),
        reason: 'the permission behind the background read',
      );
      // The in-app scope note carries the same flip: it used to say
      // background sync was "not available yet".
      final arb = RegExp(
        r'"healthSyncFullHistoryNote":\s*"([^"]*)"',
      ).firstMatch(File('lib/l10n/app_en.arb').readAsStringSync())!;
      expect(arb.group(1)!, contains('in the background'));
      expect(arb.group(1)!, isNot(contains('not available yet')),
          reason: 'the pre-#993 scope note, verbatim');

      // Issue #1215: the gate is real now — a background pass runs only
      // after the person's own first import completes — so the in-app
      // disclosures that promised "nothing is read unless you start that
      // import yourself" state the same bounded truth the site states:
      // you start the first import, the background current-keeping
      // follows it. Both platform variants are pinned; a half-updated
      // disclosure would leave the other platform claiming the old,
      // false absolute.
      final arbSource = File('lib/l10n/app_en.arb').readAsStringSync();
      final writeForwardOnly = RegExp(
        r'"healthSyncWriteForwardOnly":\s*"([^"]*)"',
      ).firstMatch(arbSource)!;
      expect(writeForwardOnly.group(1)!,
          contains('you start the first import yourself'));
      expect(writeForwardOnly.group(1)!,
          contains('after it lunarlog keeps the import current'));
      expect(writeForwardOnly.group(1)!,
          isNot(contains('nothing is read unless')),
          reason: 'the pre-#1215 claim, verbatim');
      final importOnly = RegExp(
        r'"healthSyncImportOnly":\s*"([^"]*)"',
      ).firstMatch(arbSource)!;
      expect(importOnly.group(1)!,
          contains('You start the first import yourself'));
      expect(importOnly.group(1)!,
          contains('after it, lunarlog keeps the import current'));
      expect(importOnly.group(1)!,
          isNot(contains('nothing is read or written automatically')),
          reason: 'the pre-#1215 claim, verbatim');
    });

    test('pages ship zero client-side JavaScript', () {
      // The site's own acceptance criterion (#1099): no client JS. A page
      // that grows a script tag fails here before the CSP in _headers does.
      expect(deleteAccountPage, isNot(contains('<script')));
      expect(supportPage, isNot(contains('<script')));
    });

    test('#1100 inputs stay pending, never invented', () {
      // The owner picks the public address (issue #1100, item 1). Neither
      // the personal address already in PRIVACY.md nor the recommended
      // candidate may be baked into the pages, and both pages must mark the
      // pending state visibly.
      for (final page in [deleteAccountPage, supportPage]) {
        expect(page, contains('note--pending'));
        expect(page, contains('Pending publication'));
        expect(page, isNot(contains('will@wjdavis5.net')));
        expect(page, isNot(contains('support@lunarlog.app')));
        expect(page, contains('response time'));
      }
    });

    test('both pages are discoverable: sitemap, axe, and lighthouse', () {
      // The sitemap carries both paths (site/src/pages/sitemap.xml.ts).
      expect(sitemap, contains('"/delete-account"'));
      expect(sitemap, contains('"/support"'));
      // The axe check runs against both built pages, not just the home page
      // (built as dist/<path>/index.html, hence the trailing slashes).
      expect(axePages, contains('"/delete-account/"'));
      expect(axePages, contains('"/support/"'));
      // The Lighthouse budgets gate both new pages.
      expect(
        lighthouseConfig,
        contains('"http://localhost/delete-account/"'),
      );
      expect(lighthouseConfig, contains('"http://localhost/support/"'));
    });

    test('worksheet carries the two store URL rows', () {
      // Play Data safety's Delete account URL (issue #1102).
      expect(storeDeclarations, contains('**Delete account URL**'));
      expect(
        storeDeclarations,
        contains('`https://lunarlog.app/delete-account`'),
      );
      // App Store Connect's Support URL (issue #1102).
      expect(storeDeclarations, contains('**Support URL**'));
      expect(storeDeclarations, contains('`https://lunarlog.app/support`'));
      // Both rows gate on the #1100 inputs landing before the consoles are
      // pointed at the pages.
      expect(storeDeclarations, contains('#1100'));
    });

    test('internal page cross-links resolve to files that exist', () {
      // The support page links /delete-account; the Astro build emits
      // site/src/pages/delete-account.astro at that path. If the target page
      // is ever renamed, this fails before check:links does in CI.
      expect(File('site/src/pages/delete-account.astro').existsSync(), isTrue);
      expect(File('site/src/pages/support.astro').existsSync(), isTrue);
    });
  });
}
