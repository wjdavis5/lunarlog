// One-command local regeneration of the site's app screenshots (issue
// #1104): `npm run screenshots` from site/ runs the Flutter render tool
// (tool/screenshots/render_screens_test.dart) against the repo root and
// writes the PNGs + screenshots.json into site/public/screenshots/, where
// the Astro build picks them up. The same command runs in
// site-deploy.yml's deploy job — the PNGs are never committed.
//
// Env the tool itself reads (see its header): LUNARLOG_SCREENSHOTS_OUT,
// LUNARLOG_SCREENSHOTS_COMMIT, LUNARLOG_SCREENSHOTS_FILTER. This wrapper
// resolves the repo root and the commit so `npm run screenshots` needs no
// arguments; a LUNARLOG_SCREENSHOTS_FILTER you set yourself still narrows
// the run locally.

import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const siteDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(siteDir, "..");
const outDir = path.join(siteDir, "public", "screenshots");

function resolveCommit() {
  if (process.env.LUNARLOG_SCREENSHOTS_COMMIT) {
    return process.env.LUNARLOG_SCREENSHOTS_COMMIT;
  }
  try {
    return execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: repoRoot,
      encoding: "utf8",
    }).trim();
  } catch {
    // A render without git (tarball checkout) still works; the index
    // records 'unknown'.
    return "unknown";
  }
}

const result = spawnSync(
  "flutter",
  ["test", "tool/screenshots/render_screens_test.dart"],
  {
    cwd: repoRoot,
    stdio: "inherit",
    // On Windows flutter is a .bat shim; spawnSync only finds it through a
    // shell.
    shell: process.platform === "win32",
    env: {
      ...process.env,
      LUNARLOG_SCREENSHOTS_OUT: outDir,
      LUNARLOG_SCREENSHOTS_COMMIT: resolveCommit(),
    },
  },
);

if (result.error) {
  console.error(
    `npm run screenshots: could not launch flutter (${result.error.message}). ` +
      "Install the Flutter SDK pinned in .github/workflows/ci.yml (FLUTTER_VERSION) " +
      "and make sure it is on PATH.",
  );
  process.exit(1);
}

process.exit(result.status ?? 1);
