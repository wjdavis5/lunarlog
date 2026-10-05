// Asks the browser version's public address whether it is serving the
// browser version, and prints `true` or `false` for the deploy workflow to
// pass to the site build as LUNARLOG_WEB_APP_LIVE (see src/lib/web-app.mjs).
//
// It prints `false` only when the address ANSWERED and the answer was not
// the browser version, on every attempt. If the address could not be
// reached at all (no network on the runner, a timeout) it prints `true`:
// a build must not take the site's main button away because of a problem
// on the machine doing the building.
//
// Usage: node scripts/probe-web-app.mjs

import { pathToFileURL } from "node:url";

import { WEB_APP_URL, answerIsTheWebApp } from "../src/lib/web-app.mjs";

const ATTEMPTS = 3;
const TIMEOUT_MS = 15_000;
const PAUSE_MS = 2_000;

/**
 * One request to the address.
 *
 * @param {typeof fetch} fetchImpl
 * @returns {Promise<{ status: number, contentSecurityPolicy: string | null } | null>}
 *   the answer, or null when the address could not be reached
 */
export async function askOnce(fetchImpl = fetch) {
  try {
    const response = await fetchImpl(`${WEB_APP_URL}/`, {
      redirect: "manual",
      headers: { accept: "text/html" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    return {
      status: response.status,
      contentSecurityPolicy: response.headers.get("content-security-policy"),
    };
  } catch {
    return null;
  }
}

/**
 * Whether the browser version is live, from up to [attempts] requests.
 *
 * @param {object} [options]
 * @param {typeof fetch} [options.fetchImpl]
 * @param {number} [options.attempts]
 * @param {(ms: number) => Promise<void>} [options.pause]
 * @returns {Promise<{ live: boolean, reason: string }>}
 */
export async function probeWebApp({
  fetchImpl = fetch,
  attempts = ATTEMPTS,
  pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
} = {}) {
  let lastStatus = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const answer = await askOnce(fetchImpl);
    if (answer !== null) {
      if (answerIsTheWebApp(answer)) {
        return { live: true, reason: "the address is serving the browser version" };
      }
      lastStatus = answer.status;
    }
    if (attempt < attempts) await pause(PAUSE_MS);
  }
  if (lastStatus === null) {
    return {
      live: true,
      reason: "the address could not be reached from here, so the site is left as it is",
    };
  }
  return {
    live: false,
    reason: `the address answered HTTP ${lastStatus} without the browser version's headers`,
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const result = await probeWebApp();
  console.error(`probe-web-app: ${result.reason}`);
  console.log(result.live ? "true" : "false");
}
