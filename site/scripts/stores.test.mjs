// What the site says about installing on a phone (src/lib/stores.mjs).
//
// The getting-started guide used to say "install lunarlog from the App
// Store or Google Play" while neither store listed it. The sentence now
// follows one switch, and these cases hold the switch and the sentence
// together so neither can change without the other.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { PHONE_INSTALL_SENTENCE, STORE_LISTINGS_LIVE } from "../src/lib/stores.mjs";

const guide = readFileSync(
  path.resolve(process.cwd(), "src/pages/guides/getting-started.astro"),
  "utf-8",
);

test("the install sentence says what is true for the switch", () => {
  if (STORE_LISTINGS_LIVE) {
    assert.match(PHONE_INSTALL_SENTENCE, /install lunarlog from the App Store or Google Play\.$/);
    assert.doesNotMatch(PHONE_INSTALL_SENTENCE, /not open|will install/);
  } else {
    // Not an instruction a reader cannot follow.
    assert.doesNotMatch(PHONE_INSTALL_SENTENCE, /\binstall lunarlog from\b/);
    assert.match(PHONE_INSTALL_SENTENCE, /Neither listing is open yet\.$/);
  }
});

test("the guide takes the sentence from the switch and does not retype it", () => {
  assert.ok(guide.includes("{PHONE_INSTALL_SENTENCE}"));
  assert.ok(!guide.includes("install lunarlog from the App Store"));
});

test("store badges and store links come with the switch, not before it", () => {
  // The site deliberately carries no store badge or store link while the
  // listings are not public (site/claims.md). Flipping the switch is the
  // moment to add them, in the same change.
  if (!STORE_LISTINGS_LIVE) {
    // Every link in the guide, by the host it goes to.
    const linkedHosts = [...guide.matchAll(/href="(https?:\/\/[^"]+)"/g)].map(
      (match) => new URL(match[1]).hostname,
    );
    for (const store of ["apps.apple.com", "itunes.apple.com", "play.google.com"]) {
      assert.equal(linkedHosts.includes(store), false, store);
    }
  }
});
