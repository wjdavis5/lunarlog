// Pins the invite landing page's buttons (issue #1279).
//
// Until #1258 moves the React client onto app.lunarlog.app, that origin is
// still the Flutter web build (web-deploy.yml) — and it rejects https invite
// links because web-deploy.yml sets no LUNARLOG_LINK_DOMAIN
// (lib/domain/sharing/invite_links.dart's _isUniversalInvite returns false
// for an empty link domain). An "Open in the web app" button pointing there
// therefore silently drops the invite code. The page must offer only the
// custom-scheme button; re-adding the web-app button is a deliberate #1258
// cutover act that removes these pins in the same change (the Worker-side
// twin lives in site/worker/index.test.ts, the Dart-side one in
// test/domain/sharing/link_artifacts_test.dart).

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const siteDir = path.resolve(fileURLToPath(new URL(".", import.meta.url)), "..");

const landing = await readFile(
  path.join(siteDir, "public", "invite.html"),
  "utf8",
);
const canonical = await readFile(
  path.join(siteDir, "..", "docs", "links", "invite.html"),
  "utf8",
);

test("the deployed invite page matches the canonical docs/links copy", () => {
  // site/public/invite.html must stay byte-identical to
  // docs/links/invite.html (the same invariant site.yml's `cmp` step and
  // test/domain/sharing/link_artifacts_test.dart pin, proven here without
  // needing the Dart suite).
  assert.equal(landing, canonical);
});

test("the invite page keeps the custom-scheme open-in-app button", () => {
  assert.match(landing, /id="open-in-app"/);
  assert.match(landing, /lunarlog:\/\/invite/);
  assert.match(landing, /rel="noreferrer noopener"/);
});

test("no web-app button until #1258 serves /invite on app.lunarlog.app", () => {
  // The button's anchor id, its app.lunarlog.app target (in an href or the
  // href-rewriting script), and any copy advertising web-app acceptance must
  // all stay out until the #1258 cutover. If one of these fails, the button
  // came back without the React client serving /invite behind it — see the
  // HTML comment in docs/links/invite.html for the full cutover checklist.
  assert.doesNotMatch(landing, /open-in-web-app/);
  assert.doesNotMatch(landing, /app\.lunarlog\.app/);
  assert.doesNotMatch(landing, /web app/);
});
