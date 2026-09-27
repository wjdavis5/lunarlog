// Lighthouse CI budgets for the marketing site (issue #1099).
//
// `lhci autorun` serves `site/dist` itself, so this needs no separate server.
// The budgets gate the placeholder home page today and every later page as
// they are added to `url` (#1105, #1106).
//
// Accessibility must be perfect (100); performance and best-practices must
// stay at 95 or above.
module.exports = {
  ci: {
    collect: {
      staticDistDir: "./dist",
      url: ["http://localhost/index.html"],
      numberOfRuns: 1,
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
