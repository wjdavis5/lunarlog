// Unit tests for the ARB string loader behind <UiLabel> (issue #1106).
// The build-fails-on-unknown-key contract is enforced when Astro renders
// a guide; these tests pin the same rules directly, plus the loader's
// resolution of the real `lib/l10n/app_en.arb` from the site working
// directory.

import assert from "node:assert/strict";
import { test } from "node:test";

import { arbString, loadArb, uiString } from "../src/lib/ui-strings.mjs";

const FIXTURE = {
  plain: "Just text.",
  withParam: "Invite {name} to log their own profile",
  icuPlural:
    "{count, plural, =1{1 day late} other{{count} days late}}",
  notAString: 42,
};

test("arbString resolves a plain key", () => {
  assert.equal(arbString(FIXTURE, "plain"), "Just text.");
});

test("arbString throws on an unknown or non-string key", () => {
  assert.throws(() => arbString(FIXTURE, "missingKey"), /unknown ARB key "missingKey"/);
  assert.throws(() => arbString(FIXTURE, "notAString"), /unknown ARB key "notAString"/);
  assert.throws(() => arbString(FIXTURE, ""), /non-empty string/);
});

test("arbString refuses ICU composite messages", () => {
  assert.throws(
    () => arbString(FIXTURE, "icuPlural"),
    /ICU composite message/,
  );
});

test("arbString fills {param} placeholders from values", () => {
  assert.equal(
    arbString(FIXTURE, "withParam", { name: "Maya" }),
    "Invite Maya to log their own profile",
  );
});

test("arbString throws when a placeholder has no supplied value", () => {
  assert.throws(
    () => arbString(FIXTURE, "withParam"),
    /needs a value for \{name\}/,
  );
  assert.throws(
    () => arbString(FIXTURE, "withParam", { name: "" }),
    /needs a value for \{name\}/,
  );
});

test("loadArb resolves the app's real ARB from the site working directory", () => {
  const arb = loadArb();
  assert.equal(typeof arb.guardianRoleLabelViewer, "string");
});

test("uiString reads a label the guides actually quote", () => {
  assert.equal(uiString("guardianRoleLabelViewer"), "Viewer");
});
