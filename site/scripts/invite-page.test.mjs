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

/** [html] with its comments taken out, cut on their delimiters. */
function withoutHtmlComments(html) {
  let kept = "";
  let at = 0;
  for (;;) {
    const open = html.indexOf("<!--", at);
    if (open === -1) return kept + html.slice(at);
    kept += html.slice(at, open);
    const close = html.indexOf("-->", open + 4);
    if (close === -1) return kept;
    at = close + 3;
  }
}

test("the page's script and style are ones the Worker's policy covers", () => {
  // site/worker/index.ts sends this page a Content-Security-Policy that
  // allows nothing and then admits the page's own inline script and style
  // by hash. It finds them as bare `<script>` and `<style>` blocks. A tag
  // with an attribute, a second block of either kind, or any resource the
  // page would have to fetch is one the policy would refuse on the live
  // page, so each has to be a deliberate change there too.
  const withoutComments = withoutHtmlComments(landing);
  const tags = (name) => [
    ...withoutComments.matchAll(new RegExp(`<${name}\\b[^>]*>`, "gi")),
  ].map((match) => match[0]);
  assert.deepEqual(tags("script"), ["<script>"]);
  assert.deepEqual(tags("style"), ["<style>"]);
  for (const name of ["link", "img", "iframe", "object", "embed", "form"]) {
    assert.deepEqual(tags(name), [], `the page has no <${name}>`);
  }
  // Nothing in the style reaches for a file either.
  assert.doesNotMatch(withoutComments, /url\(|@import/);

  // The Worker finds the two blocks with a pattern on the raw text,
  // comments and all. A second mention of either tag anywhere, the page's
  // long opening comment included, could make it hash the wrong span and
  // have the page's own block refused. So: one of each, on the raw text.
  // Counted without regard to case: `<SCRIPT>` is a script to a browser
  // and nothing to the Worker's pattern.
  for (const tag of ["<script", "</script", "<style", "</style"]) {
    assert.equal(landing.toLowerCase().split(tag).length - 1, 1, `exactly one ${tag}`);
  }
});

test("the Worker sends this page the same Permissions-Policy as the rest of the site", async () => {
  // `_headers` gives every other page its Permissions-Policy and does not
  // reach this one, so the Worker carries a copy. This is what keeps the
  // copy the same.
  const headers = await readFile(path.join(siteDir, "public", "_headers"), "utf8");
  const worker = await readFile(path.join(siteDir, "worker", "index.ts"), "utf8");

  const sitePolicy = /^\s*Permissions-Policy:\s*(.+?)\s*$/m.exec(headers)?.[1];
  assert.ok(sitePolicy, "_headers has a Permissions-Policy line");

  const declaration = /export const INVITE_PERMISSIONS_POLICY =([\s\S]*?);/.exec(worker)?.[1];
  assert.ok(declaration, "index.ts declares INVITE_PERMISSIONS_POLICY");
  const workerPolicy = [...declaration.matchAll(/"([^"]*)"/g)]
    .map((part) => part[1])
    .join("");

  assert.equal(workerPolicy, sitePolicy);
});
