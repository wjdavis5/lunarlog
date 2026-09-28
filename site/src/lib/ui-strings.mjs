// Build-time access to the app's own UI strings (issue #1106).
//
// The how-to guides quote screen names and button labels straight from
// `lib/l10n/app_en.arb` — never retyped — so renaming a button in the app
// and regenerating localizations cannot leave a stale guide behind. The
// site lives in this repo, which is what makes the file readable at Astro
// build time; `uiString` throws on an unknown key, and the throw happens
// while the static build renders the guide, failing `npm run build`.
//
// Deliberately plain `.mjs` with JSDoc types: the same module is unit-tested
// by `node --test scripts/` (see `scripts/ui-strings.test.mjs`) without any
// extra transpiler.

import { readFileSync } from "node:fs";
import path from "node:path";

// Resolved from the process working directory, not `import.meta.url`:
// Astro bundles component code into `dist/.prerender/chunks/`, where the
// module's own URL no longer points at the source tree. Every npm script
// (`astro dev`, `npm run build`, `astro check`) runs with `site/` as the
// working directory, so one level up is always the repository root.
/** Repository-relative ARB file this module resolves keys against. */
export const ARB_REPOSITORY_PATH = "lib/l10n/app_en.arb";
export const ARB_PATH = path.resolve(process.cwd(), "..", ARB_REPOSITORY_PATH);

let cached;

/** Load and parse the ARB once per process. */
export function loadArb() {
  cached ??= JSON.parse(readFileSync(ARB_PATH, "utf-8"));
  return cached;
}

/**
 * Pure key resolution against a parsed ARB.
 *
 * Throws when:
 * - `key` is not a non-empty string;
 * - the ARB has no string value under `key` (unknown or renamed key — the
 *   build-fails-on-unknown-key contract);
 * - the value uses ICU composite syntax (`{count, plural, ...}` /
 *   `{x, select, ...}`), which this site's plain renderer deliberately does
 *   not implement — quote a simpler string instead;
 * - the value carries `{param}` placeholders and `values` does not supply
 *   every one of them.
 *
 * @param {Record<string, unknown>} arb a parsed ARB object
 * @param {string} key the ARB key, e.g. `"guardianRoleLabelViewer"`
 * @param {Record<string, string>} [values] fills for `{param}`
 * @returns {string} the rendered string
 */
export function arbString(arb, key, values) {
  if (typeof key !== "string" || key.length === 0) {
    throw new Error(
      `UiLabel: the key must be a non-empty string, got ${JSON.stringify(key)}.`,
    );
  }
  const value = arb[key];
  if (typeof value !== "string") {
    throw new Error(
      `UiLabel: unknown ARB key "${key}" in lib/l10n/app_en.arb. ` +
        "Find the current key in the ARB (or add the string there first) — " +
        "a guide must never retype a screen name or button label.",
    );
  }
  if (/\{\s*\w+\s*,/.test(value)) {
    throw new Error(
      `UiLabel: ARB key "${key}" is an ICU composite message (plural/select) ` +
        "that this simple renderer does not implement. Quote a plainer " +
        "string from the ARB instead.",
    );
  }
  return String(value).replace(/\{(\w+)\}/g, (_placeholder, name) => {
    const filled = values?.[name];
    if (typeof filled !== "string" || filled.length === 0) {
      throw new Error(
        `UiLabel: ARB key "${key}" needs a value for {${name}}. ` +
          "Pass values={{ name: ... }} (fabricated example names only).",
      );
    }
    return filled;
  });
}

/** Resolve `key` against the app's ARB on disk (see [arbString]). */
export function uiString(key, values) {
  return arbString(loadArb(), key, values);
}
