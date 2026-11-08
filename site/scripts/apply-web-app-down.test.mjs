// The invite page's web-app button must not survive the down build
// (check-web-app-down.mjs fails on any link to the address), while a live
// build keeps it. Proves the transform against the shipped page itself.
// The --check tests (issue #1930) prove the mode site.yml's verbatim-copy
// step calls on a down build instead of the byte-identity cmp.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
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

/** Runs `--check` over [contents] and reports whether it passed, with output. */
function check(contents) {
  const dir = mkdtempSync(path.join(tmpdir(), "web-app-down-check-"));
  writeFileSync(path.join(dir, "invite.html"), contents);
  try {
    const stdout = execFileSync("node", [script, "--check", dir], {
      env: { ...process.env, LUNARLOG_WEB_APP_LIVE: "false" },
    });
    return { ok: true, output: stdout.toString() };
  } catch (error) {
    return { ok: false, output: (error.stderr ?? "").toString() };
  }
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

test("--check passes on a page the down transform already rewrote (#1930)", () => {
  const result = check(run("false"));
  assert.ok(
    result.ok,
    `the check should pass on a down-built page, but it said: ${result.output}`,
  );
  assert.match(result.output, /--check passed/);
});

test("--check fails on the untransformed page a live build ships (#1930)", () => {
  const result = check(readFileSync(page, "utf-8"));
  assert.ok(!result.ok, "the check must not pass on a live (untransformed) page");
  assert.match(result.output, /the down transform still matches/);
  assert.match(result.output, /still mentions app\.lunarlog\.app/);
});

test("--check fails when a down page lost its custom-scheme button (#1930)", () => {
  // The down state alone is not enough: the check also pins the primary
  // path the transform must never touch.
  const withoutButton = run("false").replace(
    /<p><a id="open-in-app".*<\/a><\/p>/,
    "",
  );
  const result = check(withoutButton);
  assert.ok(!result.ok, "the check must not pass without the custom-scheme button");
  assert.match(result.output, /custom-scheme button/);
  assert.match(result.output, /custom-scheme href/);
});
