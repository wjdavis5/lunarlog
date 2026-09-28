// Claims-ledger check for the how-to guides (issue #1106, applying the
// rule #1105 defines for the site).
//
// Every factual claim in a guide carries a `<!-- cite: ... -->` comment
// naming the repo path (optionally with an `#anchor`) or the GitHub issue
// (`#123`) that ships it — the ledger lives at the claim, the same
// convention `src/pages/support.astro` established. Because the site is
// in this repo, a cited path that no longer exists fails the site build
// here, and a reviewer checks the ledger instead of their memory:
//
//   node scripts/check-claims.mjs
//
// For `PRIVACY.md` the `#anchor` is validated too (its headings are the
// public deep-link contract, per check-privacy-anchors.mjs); for any
// other cited file the anchor is accepted but not parsed.
//
// Exits non-zero when a guide carries no cite comments at all, a cited
// path is missing, an issue reference is malformed, or a PRIVACY.md
// anchor does not resolve.

import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const siteDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(siteDir, "..");
const guidesDir = path.resolve(siteDir, "src/pages/guides");

/**
 * Split a cite-comment body on top-level `;` only — a `;` inside a
 * parenthetical ledger note ("(periodLate card; the safety rule)") is
 * part of the note, not a reference separator.
 * @param {string} body
 * @returns {string[]}
 */
function splitTopLevel(body) {
  const parts = [];
  let depth = 0;
  let current = "";
  for (const ch of body) {
    if (ch === "(") depth++;
    if (ch === ")") depth = Math.max(0, depth - 1);
    if (ch === ";" && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  parts.push(current);
  return parts;
}

/**
 * Extract the trimmed reference lists from every `<!-- cite: ... -->`
 * comment in one guide's source, in order. Only the page body is scanned —
 * the frontmatter is stripped first, so a component's own header
 * documentation can mention the marker without becoming a ledger entry.
 * @param {string} source an .astro page's source
 * @returns {string[]} every cited reference
 */
export function extractCiteRefs(source) {
  const body = source.replace(/^---[\s\S]*?---/, "");
  const refs = [];
  for (const match of body.matchAll(/<!--\s*cite:\s*([\s\S]*?)-->/g)) {
    for (const ref of splitTopLevel(match[1])) {
      const trimmed = ref.trim();
      if (trimmed !== "") refs.push(trimmed);
    }
  }
  return refs;
}

/** True when a reference names a GitHub issue (`#123`). */
export function isIssueRef(ref) {
  return /^#\d+$/.test(ref);
}

/**
 * Split a repo-path reference into its path and optional `#anchor`.
 * A trailing parenthetical note — `lib/foo.dart (the syncWhat card)` —
 * is ledger annotation, the convention `src/pages/support.astro`
 * established, and is stripped rather than treated as part of the path.
 * Returns null when the reference is not path-shaped (absolute URL,
 * another scheme, or an empty path).
 * @param {string} ref
 * @returns {{ repoPath: string, anchor: string | null } | null}
 */
export function splitRepositoryRef(ref) {
  if (ref.startsWith("#")) return null; // an issue ref, not a path
  if (/^[a-z][a-z0-9+.-]*:/i.test(ref)) return null; // https:, mailto:, ...
  // The trailing note goes first: it may itself carry `#` ("(issue #992)"),
  // which is annotation, never an anchor.
  const stripped = ref.replace(/\s*\([^()]*\)\s*$/, "");
  const hashAt = stripped.indexOf("#");
  const repoPath = hashAt === -1 ? stripped : stripped.slice(0, hashAt).trim();
  const anchor = hashAt === -1 ? null : stripped.slice(hashAt + 1);
  if (repoPath === "" || repoPath.startsWith("/")) return null;
  return { repoPath, anchor };
}

/**
 * GitHub-style anchor slug for one markdown heading's text: lowercase,
 * punctuation dropped (anything that is not a word character, space, or
 * hyphen), spaces collapsed into hyphens — so "5. Minors' Privacy &
 * Family Profiles" becomes `5-minors-privacy--family-profiles`.
 * @param {string} headingText
 */
export function githubSlug(headingText) {
  return headingText
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s/g, "-");
}

/**
 * The set of valid `#anchor`s of a markdown document's `#`-`######`
 * headings. Exported for the unit tests; `checkRefs` injects it.
 * @param {string} markdown
 * @returns {Set<string>}
 */
export function markdownAnchors(markdown) {
  const anchors = new Set();
  for (const match of markdown.matchAll(/^#{1,6}\s+(.+?)\s*$/gm)) {
    anchors.add(githubSlug(match[1].replace(/[#*`]/g, "")));
  }
  return anchors;
}

/**
 * Validate each reference. `exists(repoPath)` reports file existence;
 * `anchorsFor(repoPath)` returns the valid anchor set for a file that
 * supports anchor validation, or null to skip it.
 * @param {string[]} refs
 * @param {{ exists: (p: string) => boolean, anchorsFor: (p: string) => Set<string> | null }} io
 * @returns {string[]} one message per broken reference
 */
export function checkRefs(refs, { exists, anchorsFor }) {
  const errors = [];
  for (const ref of refs) {
    if (isIssueRef(ref)) continue;
    const split = splitRepositoryRef(ref);
    if (!split) {
      errors.push(
        `'${ref}' is neither an issue reference (#123) nor a repo path`,
      );
      continue;
    }
    if (!exists(split.repoPath)) {
      errors.push(
        `'${ref}' cites ${split.repoPath}, which no longer exists — the claim it supports needs a new home`,
      );
      continue;
    }
    if (split.anchor !== null) {
      const anchors = anchorsFor(split.repoPath);
      if (anchors && !anchors.has(split.anchor)) {
        errors.push(
          `'${ref}' cites an anchor that is not a heading in ${split.repoPath}`,
        );
      }
    }
  }
  return errors;
}

/** Run the check over every guide page; returns the error lines. */
export async function checkGuides({
  listDir = readdir,
  readFileFn = readFile,
  exists = (p) => existsSync(p),
  anchorsFor = () => null,
  guidesDirectory = guidesDir,
} = {}) {
  const files = (await listDir(guidesDirectory))
    .filter((name) => name.endsWith(".astro"))
    .sort();
  const errors = [];
  for (const name of files) {
    const source = await readFileFn(
      path.join(guidesDirectory, name),
      "utf8",
    );
    const refs = extractCiteRefs(source);
    if (refs.length === 0) {
      errors.push(
        `${name}: no <!-- cite: ... --> ledger entries — every factual claim in a guide cites the path or issue that ships it`,
      );
      continue;
    }
    for (const error of checkRefs(refs, { exists, anchorsFor })) {
      errors.push(`${name}: ${error}`);
    }
  }
  return errors;
}

async function main() {
  const privacy = await readFile(path.join(repoRoot, "PRIVACY.md"), "utf8");
  const privacyAnchorSet = markdownAnchors(privacy);
  const errors = await checkGuides({
    exists: (p) => existsSync(path.join(repoRoot, p)),
    anchorsFor: (repoPath) =>
      repoPath === "PRIVACY.md" ? privacyAnchorSet : null,
  });
  if (errors.length > 0) {
    console.error(`Claims-ledger check failed (${errors.length}):`);
    for (const error of errors) console.error(`  - ${error}`);
    process.exit(1);
  }
  console.log("Claims-ledger check passed (every cited path exists).");
}

// Only run when executed directly, so the unit tests can import the
// pure functions above.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
