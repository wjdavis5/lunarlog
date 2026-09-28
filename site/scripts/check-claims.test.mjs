// Unit tests for the claims-ledger check (issue #1106). Plain `node --test`
// (`npm test` from site/): the checks themselves are pure functions above,
// so no fixtures on disk are needed beyond injected fakes.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  checkGuides,
  checkRefs,
  extractCiteRefs,
  githubSlug,
  isIssueRef,
  markdownAnchors,
  splitRepositoryRef,
} from "./check-claims.mjs";

test("extractCiteRefs collects every reference from cite comments", () => {
  const source = [
    "<p>Claim one.</p>",
    "<!-- cite: PRIVACY.md#1-core-principles -->",
    "<p>Claim two.</p>",
    "<!-- cite: lib/domain/help/help_cards.dart; #1106 -->",
    "<p>Uncited prose is allowed; only cite comments count.</p>",
  ].join("\n");
  assert.deepEqual(extractCiteRefs(source), [
    "PRIVACY.md#1-core-principles",
    "lib/domain/help/help_cards.dart",
    "#1106",
  ]);
});

test("extractCiteRefs returns an empty list without cite comments", () => {
  assert.deepEqual(extractCiteRefs("<p>nothing here</p>"), []);
});

test("issue references must be # plus digits", () => {
  assert.equal(isIssueRef("#1106"), true);
  assert.equal(isIssueRef("#1106 "), false); // untrimmed input never arrives
  assert.equal(isIssueRef("1106"), false);
  assert.equal(isIssueRef("#abc"), false);
  assert.equal(isIssueRef("issue:#1106"), false);
});

test("splitRepositoryRef splits path and anchor, rejecting non-paths", () => {
  assert.deepEqual(splitRepositoryRef("PRIVACY.md#5-minors-privacy--family-profiles"), {
    repoPath: "PRIVACY.md",
    anchor: "5-minors-privacy--family-profiles",
  });
  assert.deepEqual(splitRepositoryRef("lib/l10n/app_en.arb"), {
    repoPath: "lib/l10n/app_en.arb",
    anchor: null,
  });
  assert.equal(splitRepositoryRef("#123"), null); // issue ref
  assert.equal(splitRepositoryRef("https://example.com/x"), null);
  assert.equal(splitRepositoryRef("/absolute/path"), null);
  assert.equal(splitRepositoryRef("#anchor-only"), null);
});

test("splitRepositoryRef strips a trailing parenthetical ledger note", () => {
  assert.deepEqual(
    splitRepositoryRef("lib/domain/help/help_cards.dart (ownershipTransfer card)"),
    { repoPath: "lib/domain/help/help_cards.dart", anchor: null },
  );
  // The note goes first: a `#` inside it is annotation, never an anchor.
  assert.deepEqual(
    splitRepositoryRef("lib/data/health/health_import_service.dart (whole-history read, issue #992)"),
    { repoPath: "lib/data/health/health_import_service.dart", anchor: null },
  );
});

test("extractCiteRefs ignores the marker mentioned in frontmatter docs", () => {
  const source = [
    "---",
    "// Every claim carries a `<!-- cite: ... -->` ledger entry.",
    "---",
    "<p>Body.</p>",
    "<!-- cite: #1106 -->",
  ].join("\n");
  assert.deepEqual(extractCiteRefs(source), ["#1106"]);
});

test("githubSlug matches GitHub's heading anchors", () => {
  assert.equal(
    githubSlug("5. Minors' Privacy & Family Profiles"),
    "5-minors-privacy--family-profiles",
  );
  assert.equal(githubSlug("1. Core Principles"), "1-core-principles");
  assert.equal(
    githubSlug("7. Data Export & Retention & Deletion Rights"),
    "7-data-export--retention--deletion-rights",
  );
});

test("markdownAnchors collects every heading's slug", () => {
  const anchors = markdownAnchors(
    ["# Title", "## 1. Core Principles", "### A. Health & cycle info"].join("\n"),
  );
  assert.equal(anchors.has("title"), true);
  assert.equal(anchors.has("1-core-principles"), true);
  assert.equal(anchors.has("a-health--cycle-info"), true);
});

test("checkRefs passes issue refs and existing paths, fails missing ones", () => {
  const exists = (p) => p === "lib/l10n/app_en.arb";
  const errors = checkRefs(["#1106", "lib/l10n/app_en.arb", "lib/gone.dart"], {
    exists,
    anchorsFor: () => null,
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /lib\/gone\.dart/);
  assert.match(errors[0], /no longer exists/);
});

test("checkRefs validates PRIVACY.md anchors and skips other files'", () => {
  const anchors = new Set(["5-minors-privacy--family-profiles"]);
  const anchorsFor = (p) => (p === "PRIVACY.md" ? anchors : null);
  const ok = checkRefs(
    ["PRIVACY.md#5-minors-privacy--family-profiles", "AGENTS.md#anything-goes"],
    { exists: () => true, anchorsFor },
  );
  assert.deepEqual(ok, []);
  const bad = checkRefs(["PRIVACY.md#not-a-section"], {
    exists: () => true,
    anchorsFor,
  });
  assert.equal(bad.length, 1);
  assert.match(bad[0], /not a heading/);
});

test("checkRefs rejects references that are neither issues nor paths", () => {
  const errors = checkRefs(["mailto:someone"], {
    exists: () => true,
    anchorsFor: () => null,
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /neither an issue reference/);
});

test("checkGuides fails a guide without cite comments", async () => {
  const errors = await checkGuides({
    listDir: async () => ["bare.astro", "cited.astro"],
    readFileFn: async (_path, name) =>
      name === "utf8" && _path.endsWith("bare.astro")
        ? "<p>no ledger</p>"
        : "<!-- cite: #1106 --><p>ok</p>",
    exists: () => true,
    anchorsFor: () => null,
    guidesDirectory: "/unused",
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /bare\.astro: no <!-- cite: ... --> ledger entries/);
});
