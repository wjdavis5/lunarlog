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
// Accessibility must be perfect (100); performance and best-practices must
// stay at 95 or above.
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
      ],
      numberOfRuns: 3,
      settings: {
        chromeFlags: ["--no-sandbox", "--disable-dev-shm-usage"],
      },
    },
    assert: {
      assertions: {
        "categories:accessibility": ["error", { minScore: 1 }],
        "categories:performance": ["error", { minScore: 0.95 }],
        "categories:best-practices": ["error", { minScore: 0.95 }],
      },
    },
    upload: {
      target: "filesystem",
      outputDir: "./.lighthouseci",
    },
  },
};
