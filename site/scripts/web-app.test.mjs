// Whether the site links to the browser version (src/lib/web-app.mjs) and
// how the deploy finds out (scripts/probe-web-app.mjs).
//
// The home page's main button leads to app.lunarlog.app. When that address
// stopped serving the browser version, the site went on linking to it. The
// deploy now asks the address before it builds, and these cases pin both
// halves of that: what counts as "the browser version answered", and that a
// build never takes the button away for a reason on the builder's side.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  WEB_APP_HOST,
  WEB_APP_LIVE_ENV,
  WEB_APP_URL,
  answerIsTheWebApp,
  webAppIsLive,
} from "../src/lib/web-app.mjs";
import { probeWebApp } from "./probe-web-app.mjs";

const APP_CSP =
  "default-src 'self'; script-src 'self'; require-trusted-types-for 'script'";

/** A fetch that answers each call with the next canned outcome. */
function fetchAnswering(...outcomes) {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(String(url));
    const outcome = outcomes[Math.min(calls.length - 1, outcomes.length - 1)];
    if (outcome === "unreachable") throw new TypeError("fetch failed");
    return new Response("", { status: outcome.status, headers: outcome.headers ?? {} });
  };
  return { fetchImpl, calls };
}

const appAnswer = { status: 200, headers: { "content-security-policy": APP_CSP } };
const errorPage = { status: 403, headers: { "content-type": "text/plain" } };
const noPause = async () => {};

test("the address is the one the privacy policy names", () => {
  assert.equal(WEB_APP_URL, "https://app.lunarlog.app");
  assert.equal(WEB_APP_HOST, "app.lunarlog.app");
});

test("the site links to the browser version unless it is told not to", () => {
  assert.equal(webAppIsLive({}), true, "a local or pull-request build");
  assert.equal(webAppIsLive({ [WEB_APP_LIVE_ENV]: "true" }), true);
  assert.equal(webAppIsLive({ [WEB_APP_LIVE_ENV]: "" }), true);
  // Only the exact word turns it off: a typo must not hide the button.
  for (const odd of ["FALSE", "0", "no", "down", " false"]) {
    assert.equal(webAppIsLive({ [WEB_APP_LIVE_ENV]: odd }), true, odd);
  }
  assert.equal(webAppIsLive({ [WEB_APP_LIVE_ENV]: "false" }), false);
});

test("only a 200 carrying the browser version's own policy counts as live", () => {
  assert.equal(answerIsTheWebApp({ status: 200, contentSecurityPolicy: APP_CSP }), true);
  // The October 2026 outage: Cloudflare's "error code: 1014".
  assert.equal(answerIsTheWebApp({ status: 403, contentSecurityPolicy: null }), false);
  // A 200 from something else on the address.
  assert.equal(answerIsTheWebApp({ status: 200, contentSecurityPolicy: null }), false);
  assert.equal(
    answerIsTheWebApp({ status: 200, contentSecurityPolicy: "default-src 'self'" }),
    false,
  );
  assert.equal(answerIsTheWebApp({ status: 302, contentSecurityPolicy: APP_CSP }), false);
  assert.equal(answerIsTheWebApp({ status: 503, contentSecurityPolicy: APP_CSP }), false);
});

test("the probe says live when the browser version answers", async () => {
  const { fetchImpl, calls } = fetchAnswering(appAnswer);
  const result = await probeWebApp({ fetchImpl, pause: noPause });
  assert.equal(result.live, true);
  assert.deepEqual(calls, ["https://app.lunarlog.app/"]);
});

test("the probe says down when the address keeps answering with something else", async () => {
  const { fetchImpl, calls } = fetchAnswering(errorPage);
  const result = await probeWebApp({ fetchImpl, pause: noPause });
  assert.equal(result.live, false);
  assert.match(result.reason, /HTTP 403/);
  assert.equal(calls.length, 3, "it asks more than once before saying so");
});

test("one bad answer is not enough: a later good one wins", async () => {
  const { fetchImpl } = fetchAnswering(errorPage, "unreachable", appAnswer);
  const result = await probeWebApp({ fetchImpl, pause: noPause });
  assert.equal(result.live, true);
});

test("an address that cannot be reached leaves the site as it is", async () => {
  // No network on the machine doing the build is not news about the
  // address, so the button stays.
  const { fetchImpl, calls } = fetchAnswering("unreachable");
  const result = await probeWebApp({ fetchImpl, pause: noPause });
  assert.equal(result.live, true);
  assert.equal(calls.length, 3);
});

test("unreachable now and then, an error page otherwise: down", async () => {
  const { fetchImpl } = fetchAnswering("unreachable", errorPage, "unreachable");
  const result = await probeWebApp({ fetchImpl, pause: noPause });
  assert.equal(result.live, false);
});
