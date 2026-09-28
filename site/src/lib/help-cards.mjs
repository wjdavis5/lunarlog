// Build-time access to the app's bundled help cards (issue #1106).
//
// The guides reuse `lib/domain/help/help_cards.dart`'s explanations of app
// mechanics (issue #139) through the #1103 export pattern: `dart run
// tool/export_help_cards.dart` writes `src/content/help-cards/cards.json`,
// the file is committed, and the Dart freshness test
// (`test/tool/export_help_cards_test.dart`) fails when it drifts. A guide
// embeds a card by id; an unknown id throws during the static build, the
// same build-fails-on-unknown-key contract as the ARB component.
//
// Deliberately plain `.mjs` with JSDoc types: unit-tested by
// `node --test scripts/` without any extra transpiler.

import { readFileSync } from "node:fs";
import path from "node:path";

// Resolved from the process working directory (see ui-strings.mjs: Astro
// bundles component code into dist/.prerender/chunks/, where the module's
// own URL no longer points at the source tree, while every npm script runs
// with `site/` as the working directory).
/** The committed #1103-style export of `HelpCards.all`. */
export const HELP_CARDS_PATH = path.resolve(
  process.cwd(),
  "src/content/help-cards/cards.json",
);

let cached;

/** Load and parse the committed export once per process. */
export function loadHelpCards() {
  cached ??= JSON.parse(readFileSync(HELP_CARDS_PATH, "utf-8"));
  return cached;
}

/**
 * Pure card lookup against a parsed export.
 *
 * Throws on an unknown id — a guide referencing a card that no longer
 * exists (renamed or removed in `help_cards.dart`) fails `npm run build`
 * instead of shipping a silently-missing section.
 *
 * @param {Array<{id: string}>} cards a parsed cards.json array
 * @param {string} id a `HelpCard.id`, e.g. `"confidence-levels"`
 * @returns {{id: string, title: string, summary: string, body: string[], source: string, reviewDate: string, screens: string[]}} the card
 */
export function helpCard(cards, id) {
  const card = cards.find((entry) => entry.id === id);
  if (!card) {
    throw new Error(
      `HelpCard: unknown card id "${id}" in site/src/content/help-cards/cards.json. ` +
        "Pick an id from lib/domain/help/help_cards.dart; if the card was " +
        "renamed, regenerate the export with " +
        "`dart run tool/export_help_cards.dart`.",
    );
  }
  return card;
}
