// The invite page's web-app button must not survive the down build
// (check-web-app-down.mjs fails on any link to the address), while a live
// build keeps it. Proves the transform against the shipped page itself.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("./apply-web-app-down.mjs", import.meta.url));
const page = fileURLToPath(new URL("../public/invite.html", import.meta.url));

function run(flag) {
  const dir = mkdtempSync(path.join(tmpdir(), "web-app-down-"));
  copyFileSync(page, path.join(dir, "invite.html"));
  execFileSync("node", [script, dir], {
    env: { ...process.env, LUNARLOG_WEB_APP_LIVE: flag },
  });
  return readFileSync(path.join(dir, "invite.html"), "utf-8");
}

test("a live build leaves the invite page untouched", () => {
  const after = run("true");
  assert.match(after, /id="open-in-web-app"/);
  assert.match(after, /app\.lunarlog\.app\/invite/);
});

test("a down build drops the web-app button, its line, and its script rewrite", () => {
  const after = run("false");
  assert.doesNotMatch(after, /id="open-in-web-app"/);
  assert.doesNotMatch(after, /On a computer, you can accept the invitation in the web app/);
  assert.doesNotMatch(after, /app\.lunarlog\.app/);
  assert.doesNotMatch(after, /href="https:\/\/app\.lunarlog\.app/);
  // The primary path and the install steps stay.
  assert.match(after, /id="open-in-app"/);
  assert.match(after, /lunarlog:\/\/invite\?/);
});
