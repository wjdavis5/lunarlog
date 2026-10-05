// Inline-spacing check for the built site (`site/dist`).
//
// Prose in the page sources wraps, and a link often starts its own source
// line:
//
//     …each role, exactly — sees what
//     <a href="/family-sharing">their role</a> allows, and no more.
//
// The line break is the space between "what" and the link. Astro 7's
// default JSX whitespace rules dropped it, so 38 links and bold labels on the live site
// rendered glued to the word beside them ("sees whattheir role allows",
// "Questions:Support"). `astro.config.mjs` now sets `compressHTML: true`
// (lossless); this check is what keeps the bug from coming back by any
// other route (the option reverting, a minifier, a component that trims
// its slot).
//
//   node scripts/check-inline-spacing.mjs
//
// Exits non-zero when a word or sentence punctuation directly touches an
// inline text element (`a`, `strong`, `em`, `code`) in any built page.

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dist = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "../dist",
);

/** The inline elements whose edges must not touch a word. */
const INLINE_TAGS = "a|strong|em|code";

// A letter, a digit, or the punctuation that ends a clause, immediately
// before an opening inline tag. An opening bracket or quote before a link
// ("(<a…", "“<a…") is ordinary typography and is not matched.
const GLUED_BEFORE = new RegExp(
  `[\\p{L}\\p{N}:;,.!?)]<(?:${INLINE_TAGS})(?=[\\s>])`,
  "gu",
);

// A letter or digit immediately after a closing inline tag. Punctuation
// after a link ("</a>.", "</a>,") is ordinary and is not matched.
const GLUED_AFTER = new RegExp(`</(?:${INLINE_TAGS})>[\\p{L}\\p{N}]`, "gu");

/**
 * Remove the parts of a page that are not prose: comments, and the bodies
 * of `<script>` / `<style>` / `<pre>` (a code sample may legitimately hold
 * `x<a` as text).
 * @param {string} html
 * @returns {string}
 */
export function stripNonProse(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<(script|style|pre)\b[\s\S]*?<\/\1>/gi, "");
}

/**
 * Find every place a word touches an inline element, with enough context
 * around each to locate it in the source.
 * @param {string} html a built page
 * @returns {string[]} one context snippet per finding, in document order
 */
export function findGluedInlineElements(html) {
  const prose = stripNonProse(html);
  const findings = [];
  for (const pattern of [GLUED_BEFORE, GLUED_AFTER]) {
    for (const match of prose.matchAll(pattern)) {
      const start = Math.max(0, match.index - 30);
      const end = Math.min(prose.length, match.index + match[0].length + 40);
      findings.push({
        index: match.index,
        snippet: prose.slice(start, end).replace(/\s+/g, " ").trim(),
      });
    }
  }
  return findings.sort((a, b) => a.index - b.index).map((f) => f.snippet);
}

/**
 * Every `.html` file under a directory, recursively.
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
async function htmlFiles(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await htmlFiles(full)));
    else if (entry.name.endsWith(".html")) out.push(full);
  }
  return out;
}

async function main() {
  const errors = [];
  const files = await htmlFiles(dist);
  for (const file of files) {
    const rel = path.relative(dist, file).replaceAll("\\", "/");
    for (const snippet of findGluedInlineElements(await readFile(file, "utf8"))) {
      errors.push(`${rel}: …${snippet}…`);
    }
  }
  if (errors.length > 0) {
    console.error(
      `Inline-spacing check failed (${errors.length}): a word touches a link or other inline element with no space between them.`,
    );
    for (const error of errors) console.error(`  - ${error}`);
    process.exit(1);
  }
  console.log(
    `Inline-spacing check passed (${files.length} pages, no word touches an inline element).`,
  );
}

// Only run when executed directly, so the unit tests can import the pure
// functions above.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
