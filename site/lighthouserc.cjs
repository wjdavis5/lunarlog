// Lighthouse CI budgets for the marketing site (issue #1099).
//
// `lhci autorun` serves `site/dist` itself, so this needs no separate server.
// The budgets gate the home page and every later page as they are added to
// `url` (#1102, #1105, #1106).
//
// Three runs per URL, not one: with a single run the scores are noisy
// enough to fail a budget by luck — on issue #1102's first CI run the
// smaller /support/ scored 0.92 while the heavier /delete-account/ passed
// 0.95 on identical CSS, so single-run comparisons were demonstrably not
// measuring the pages. LHCI's assertion aggregation is optimistic (best of
// the runs), so three runs keep the bar at 0.95 while no longer failing a
// page for one slow simulated load.
//
// Issue #1172: even three runs stopped being enough for the six
// screenshot-bearing pages. Their first-viewport figure is a full-size app
// PNG (1290×2796), and its emulated slow-4G LCP wobbles right around where
// the performance category crosses 0.95: the same /tracking/ bytes measured
// 1.0 locally and 0.92-0.95 in CI, with one main dispatch failing all three
// runs at 0.92 and content-only PRs gated by luck. The screenshot pages
// (home + the five feature pages — exactly the pages that render a
// <Screenshot>) therefore assert performance at 0.90, a floor their steady
// state clears with margin; the LCP wobble itself is attacked at the source
// by Screenshot.astro's eager-implies-fetchpriority="high" wiring. Every
// text-only page (guides, support, delete-account, privacy-security) keeps
// the original 0.95. Each matrix entry matches exactly one URL set (LHCI
// filters each entry's LHRs by matchingUrlPattern — a plain RegExp against
// the served URL, whose port is random and so optional here), so every URL
// is asserted exactly once, and a future page defaults to the stricter set.
//
// Accessibility must be perfect (100); best-practices must stay at 95 or
// above on every page.
const kPerformanceStrict = ["error", { minScore: 0.95 }];
const kPerformanceScreenshotPages = ["error", { minScore: 0.9 }];
const kScreenshotPagePattern =
  "^http://localhost(:\\d+)?/(?:index\\.html|(?:tracking|family-sharing|life-stage-modes|import|export)/)$";
// Anything else — including every page added later — gets the strict floor.
const kStrictPattern =
  "^http://localhost(:\\d+)?/(?!(?:index\\.html|tracking/|family-sharing/|life-stage-modes/|import/|export/))";
module.exports = {
  ci: {
    collect: {
      staticDistDir: "./dist",
      url: [
        "http://localhost/index.html",
        "http://localhost/delete-account/",
        "http://localhost/support/",
        // Issue #1105 feature pages (home is index.html above).
        "http://localhost/tracking/",
        "http://localhost/family-sharing/",
        "http://localhost/life-stage-modes/",
        "http://localhost/import/",
        "http://localhost/export/",
        "http://localhost/privacy-security/",
        // The how-to guides (issue #1106).
        "http://localhost/guides/",
        "http://localhost/guides/getting-started/",
        "http://localhost/guides/household-setup/",
        "http://localhost/guides/inviting-someone/",
        "http://localhost/guides/transferring-ownership/",
        "http://localhost/guides/logging-a-day/",
        "http://localhost/guides/reading-estimates/",
        "http://localhost/guides/moving-your-data/",
        "http://localhost/guides/browser-version/",
      ],
      numberOfRuns: 3,
      settings: {
        chromeFlags: ["--no-sandbox", "--disable-dev-shm-usage"],
      },
    },
    assert: {
      // LHCI 0.15 has no per-assertion URL scoping; assertMatrix entries
      // each carry a whole assertion set scoped by matchingUrlPattern.
      assertMatrix: [
        {
          matchingUrlPattern: kScreenshotPagePattern,
          assertions: {
            "categories:accessibility": ["error", { minScore: 1 }],
            "categories:performance": kPerformanceScreenshotPages,
            "categories:best-practices": ["error", { minScore: 0.95 }],
          },
        },
        {
          matchingUrlPattern: kStrictPattern,
          assertions: {
            "categories:accessibility": ["error", { minScore: 1 }],
            "categories:performance": kPerformanceStrict,
            "categories:best-practices": ["error", { minScore: 0.95 }],
          },
        },
      ],
    },
    upload: {
      target: "filesystem",
      outputDir: "./.lighthouseci",
    },
  },
};
