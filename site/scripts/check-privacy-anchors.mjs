// Section-anchor stability check for the built privacy page (`site/dist`).
//
// The in-app privacy dialog and the store listings point people at
// `https://lunarlog.app/privacy` (issue #1101), and the page's section
// anchors are the contract in-app deep links target. Astro derives heading
// ids from the heading text with GitHub's slug style, so the ids are stable
// for as long as the text is — and this check makes a *silent* heading
// rename impossible: renaming a section fails the site build until the pin
// below is updated in the same commit, which is the moment to grep the app
// for links to the old anchor.
//
//   node scripts/check-privacy-anchors.mjs
//
// Exits non-zero when a pinned anchor is missing or the page's `<h2>` set
// drifts from the pinned sections.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dist = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "../dist",
);

// The page's `<h2>` sections, exactly. `PRIVACY.md`'s eleven numbered
// sections are the stable public contract; adding, removing, or renaming one
// is a deliberate act that updates this list alongside any deep links.
const SECTION_H2_IDS = [
  "1-core-principles",
  "2-information-we-collect-and-process",
  "3-how-we-use-your-information",
  "4-third-party-service-providers",
  "5-minors-privacy--family-profiles",
  "6-security-protections",
  "7-data-export--retention--deletion-rights",
  "8-your-legal-rights-gdpr-ccpa-and-worldwide",
  "9-apple-app-store--google-play-declarations",
  "10-changes-to-this-privacy-policy",
  "11-contact-information",
];

// Sub-section anchors deep links may also target (Section 2's A–E and the
// Change History). Presence-only: new subsections are allowed to appear.
const PINNED_H3_IDS = [
  "a-health--cycle-information-local--optional-cloud-sync",
  "b-account--authentication-information-optional",
  "c-support-ticket-information-optional",
  "d-technical--crash-information-diagnostics",
  "e-home-screen-widget-data-on-device-only",
  "change-history",
];

const html = await readFile(path.join(dist, "privacy.html"), "utf8");

const headingIds = [...html.matchAll(/<h[123][^>]*\bid="([^"]+)"/g)].map(
  (match) => match[1],
);

const errors = [];

for (const id of [...SECTION_H2_IDS, ...PINNED_H3_IDS]) {
  if (!headingIds.includes(id)) {
    errors.push(`missing pinned section anchor: #${id}`);
  }
}

const h2Ids = [
  ...html.matchAll(/<h2[^>]*\bid="([^"]+)"/g),
].map((match) => match[1]);

for (const id of h2Ids) {
  if (!SECTION_H2_IDS.includes(id)) {
    errors.push(
      `unexpected <h2> anchor #${id} — update SECTION_H2_IDS in this script ` +
        `(and any deep links) in the same change`,
    );
  }
}

if (errors.length > 0) {
  console.error(`Privacy anchor check failed (${errors.length}):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(
  `Privacy anchor check passed (${SECTION_H2_IDS.length} sections, ` +
    `${PINNED_H3_IDS.length} subsections pinned).`,
);
