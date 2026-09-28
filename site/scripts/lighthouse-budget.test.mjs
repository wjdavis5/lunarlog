// Unit tests for the Lighthouse CI budget contract (issue #1172).
//
// lighthouserc.cjs is data — the config the Site workflow gates every PR
// with — so its invariants are pinned here directly: which URLs carry which
// performance floor, that the two assertMatrix entries partition the URL
// list with no gap and no overlap (LHCI runs every entry against every URL
// group, so an overlapping pattern would assert a URL twice and a gap
// would leave one unasserted), and that the eager-implies-fetchpriority
// wiring behind the LCP fix actually ships on every screenshot-bearing
// page. These read the same source files the way
// test/site/site_claims_test.dart reads them from the Dart side.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const siteDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = require(path.join(siteDir, "lighthouserc.cjs")).ci;

// The six pages whose first viewport embeds an app screenshot PNG (home
// included) — the exact URL set lighthouserc.cjs scopes to the 0.90 floor.
const kScreenshotPageUrls = [
  "http://localhost/index.html",
  "http://localhost/tracking/",
  "http://localhost/family-sharing/",
  "http://localhost/life-stage-modes/",
  "http://localhost/import/",
  "http://localhost/export/",
];

// The pages whose first viewport is text only — the strict-0.95 set.
const kTextOnlyPageUrls = [
  "http://localhost/delete-account/",
  "http://localhost/support/",
  "http://localhost/privacy-security/",
  "http://localhost/guides/",
  "http://localhost/guides/logging-a-day/",
];

/** Matches a finalUrl the way LHCI's doesLHRMatchPattern does. */
const matches = (pattern, url) => new RegExp(pattern).test(url);

/** LHCI serves on a random port; finalUrl carries it (issue #1172 run log). */
const withPort = (url) => url.replace("http://localhost", "http://localhost:35713");

function budgetEntry(url) {
  const hits = config.assert.assertMatrix.filter((entry) =>
    matches(entry.matchingUrlPattern, url),
  );
  assert.equal(
    hits.length,
    1,
    `${url} must match exactly one assertMatrix entry, got ${hits.length}`,
  );
  return hits[0];
}

test("the collect contract is unchanged", () => {
  assert.equal(config.collect.staticDistDir, "./dist");
  // Three runs per URL, kept from issue #1102: optimistic aggregation
  // takes the best of them, so one slow simulated load cannot fail a page.
  assert.equal(config.collect.numberOfRuns, 3);
  assert.ok(config.collect.url.length >= 18);
  for (const url of config.collect.url) {
    assert.match(url, /^http:\/\/localhost(:\d+)?\//);
  }
});

test("every collected URL matches exactly one budget entry", () => {
  for (const url of config.collect.url) {
    budgetEntry(url);
    budgetEntry(withPort(url));
  }
});

test("the screenshot pages get the 0.90 performance floor", () => {
  for (const url of kScreenshotPageUrls) {
    const entry = budgetEntry(withPort(url));
    assert.deepEqual(entry.assertions["categories:performance"], [
      "error",
      { minScore: 0.9 },
    ]);
  }
});

test("every other page keeps the strict 0.95 performance floor", () => {
  for (const url of kTextOnlyPageUrls) {
    const entry = budgetEntry(withPort(url));
    assert.deepEqual(entry.assertions["categories:performance"], kStrictPerformance());
  }
});

test("accessibility and best-practices hold on both sides of the split", () => {
  for (const url of [...kScreenshotPageUrls, ...kTextOnlyPageUrls]) {
    const entry = budgetEntry(withPort(url));
    assert.deepEqual(entry.assertions["categories:accessibility"], [
      "error",
      { minScore: 1 },
    ]);
    assert.deepEqual(entry.assertions["categories:best-practices"], [
      "error",
      { minScore: 0.95 },
    ]);
  }
});

test("a page added later defaults to the strict budget", () => {
  const entry = budgetEntry("http://localhost:35713/guides/a-future-guide/");
  assert.deepEqual(entry.assertions["categories:performance"], kStrictPerformance());
});

test("a renamed route cannot silently fall out of every budget", () => {
  // A moved page (say /tracking/ → /logging/) must land in one of the two
  // entries; the strict pattern is the catch-all, so this holds by
  // construction — pin it anyway so the patterns cannot grow a gap.
  for (const url of [
    "http://localhost:35713/logging/",
    "http://localhost:35713/index.html",
    "http://localhost:35713/",
  ]) {
    budgetEntry(url);
  }
});

test("every screenshot page ships the eager-implies-fetchpriority fix", () => {
  // The component must wire fetchpriority to eager (issue #1172: the LCP
  // candidate's request otherwise starts only after layout discovers it).
  const component = readFileSync(
    path.join(siteDir, "src/components/Screenshot.astro"),
    "utf8",
  );
  assert.match(
    component,
    /fetchpriority=\{loading === "eager" \? "high" : undefined\}/,
    "Screenshot.astro must raise the fetch priority of eager images",
  );

  // ...and every screenshot-bearing page's first <Screenshot> must be
  // eager — the site convention for the first-viewport LCP candidate.
  for (const url of kScreenshotPageUrls) {
    const route = url === "http://localhost/index.html" ? "index" : url.replace(/\/$/, "").split("/").pop();
    const source = readFileSync(
      path.join(siteDir, "src/pages", `${route}.astro`),
      "utf8",
    );
    const first = source.indexOf("<Screenshot");
    assert.ok(first >= 0, `${route}.astro renders a screenshot`);
    const block = source.slice(first, source.indexOf("/>", first));
    assert.match(
      block,
      /loading="eager"/,
      `${route}.astro's first screenshot must be eager (issue #1172)`,
    );
  }
});

function kStrictPerformance() {
  const entry = budgetEntry("http://localhost:35713/support/");
  return entry.assertions["categories:performance"];
}
