// Unit tests for the help-card loader behind <HelpCard> (issue #1106):
// the unknown-id build-failure contract, and the committed export's
// resolution of the real cards.json from the site working directory.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  helpCard,
  loadHelpCards,
} from "../src/lib/help-cards.mjs";

const FIXTURE = [
  { id: "known-card", title: "Known", summary: "s", body: ["b"], source: "x", reviewDate: "2026-09-11", screens: [] },
];

test("helpCard returns the card for a known id", () => {
  assert.equal(helpCard(FIXTURE, "known-card").title, "Known");
});

test("helpCard throws on an unknown id", () => {
  assert.throws(
    () => helpCard(FIXTURE, "renamed-away"),
    /unknown card id "renamed-away"/,
  );
});

test("loadHelpCards loads the committed export of every bundled card", () => {
  const cards = loadHelpCards();
  assert.ok(Array.isArray(cards));
  // The #139 bundle has 24 cards; the export carries all of them.
  assert.equal(cards.length, 24);
  for (const card of cards) {
    assert.equal(typeof card.id, "string");
    assert.equal(typeof card.title, "string");
    assert.ok(Array.isArray(card.body));
    assert.ok(card.body.length > 0);
    assert.equal(typeof card.source, "string");
    assert.match(card.reviewDate, /^\d{4}-\d{2}-\d{2}$/);
  }
});

test("the export answers an id a guide quotes", () => {
  assert.equal(helpCard(loadHelpCards(), "confidence-levels").id, "confidence-levels");
});
