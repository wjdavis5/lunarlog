// Unit tests for the external-link check (issue #1899 added the DOI case;
// issue #1934 added the Crossref 429 retry, rate-limit message, and
// polite-pool User-Agent).
// Plain `node --test` (`npm test` from site/): the check takes an injected
// fetch and an injected sleep, so the branches are driven without a network,
// without delays, and without a built site.

import assert from "node:assert/strict";
import { test } from "node:test";

import { checkExternalLinks, doiFromUrl } from "./check-external-links.mjs";

// A sleep stub that records the requested backoff instead of waiting.
const instantSleep = (sleeps) => async (ms) => {
  sleeps.push(ms);
};

test("doiFromUrl reads the DOI out of a doi.org link", () => {
  assert.equal(doiFromUrl("https://doi.org/10.1002/ijgo.12666"), "10.1002/ijgo.12666");
  assert.equal(
    doiFromUrl("https://dx.doi.org/10.1056/NEJM199512073332301"),
    "10.1056/NEJM199512073332301",
  );
});

test("doiFromUrl ignores anything that is not a DOI link", () => {
  assert.equal(doiFromUrl("https://example.com/10.1002/ijgo.12666"), null);
  assert.equal(doiFromUrl("https://doi.org/not-a-doi"), null);
  assert.equal(doiFromUrl("https://doi.org/"), null);
});

test("a doi.org link is checked at Crossref and passes when registered", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://doi.org/10.1002/ijgo.12666"], {
    fetchImpl: async (url, options) => {
      calls.push({
        url,
        method: options.method ?? "GET",
        userAgent: options.headers["User-Agent"],
      });
      return { status: 200 };
    },
  });
  assert.deepEqual(failures, []);
  // The publisher is never contacted: one GET of the Crossref record, nothing
  // else, carrying Crossref's polite-pool User-Agent (issue #1934).
  assert.deepEqual(calls, [
    {
      url: "https://api.crossref.org/works/10.1002/ijgo.12666",
      method: "GET",
      userAgent: "lunarlog-site-link-check (https://github.com/wjdavis5/lunarlog)",
    },
  ]);
});

test("a DOI Crossref reports 404 for fails", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://doi.org/10.1002/gone"], {
    fetchImpl: async () => {
      calls.push(1);
      return { status: 404 };
    },
    sleepImpl: async () => {
      throw new Error("must not back off before a 404");
    },
  });
  assert.deepEqual(failures, ["https://doi.org/10.1002/gone: DOI not found (Crossref 404)"]);
  // A 404 is a verdict, not transient trouble: answered on the first attempt.
  assert.equal(calls.length, 1);
});

test("a DOI Crossref throttles with 429 passes after backing off and retrying", async () => {
  const statuses = [429, 429, 200];
  const calls = [];
  const sleeps = [];
  const failures = await checkExternalLinks(["https://doi.org/10.1056/NEJM199512073332301"], {
    fetchImpl: async (url) => {
      calls.push(url);
      return { status: statuses[calls.length - 1] };
    },
    sleepImpl: instantSleep(sleeps),
  });
  assert.deepEqual(failures, []);
  // The first attempt plus two retries, each after a doubling backoff.
  assert.deepEqual(calls, [
    "https://api.crossref.org/works/10.1056/NEJM199512073332301",
    "https://api.crossref.org/works/10.1056/NEJM199512073332301",
    "https://api.crossref.org/works/10.1056/NEJM199512073332301",
  ]);
  assert.deepEqual(sleeps, [1_000, 2_000]);
});

test("a DOI Crossref 503s passes after a retry too", async () => {
  const statuses = [503, 200];
  const calls = [];
  const sleeps = [];
  const failures = await checkExternalLinks(["https://doi.org/10.1002/ijgo.12666"], {
    fetchImpl: async () => {
      calls.push(1);
      return { status: statuses[calls.length - 1] };
    },
    sleepImpl: instantSleep(sleeps),
  });
  assert.deepEqual(failures, []);
  assert.equal(calls.length, 2);
  assert.deepEqual(sleeps, [1_000]);
});

test("a DOI Crossref never stops throttling fails as rate-limited, not broken", async () => {
  const calls = [];
  const sleeps = [];
  const failures = await checkExternalLinks(["https://doi.org/10.1056/NEJM199512073332301"], {
    fetchImpl: async () => {
      calls.push(1);
      return { status: 429 };
    },
    sleepImpl: instantSleep(sleeps),
  });
  assert.deepEqual(failures, [
    "https://doi.org/10.1056/NEJM199512073332301: Crossref rate-limited (HTTP 429) after 4 attempts",
  ]);
  // The first attempt plus all three retries, each after a doubling backoff.
  assert.equal(calls.length, 4);
  assert.deepEqual(sleeps, [1_000, 2_000, 4_000]);
});

test("a DOI check that cannot reach Crossref fails with the error", async () => {
  const failures = await checkExternalLinks(["https://doi.org/10.1002/x"], {
    fetchImpl: async () => {
      throw new Error("fetch failed");
    },
  });
  assert.deepEqual(failures, ["https://doi.org/10.1002/x: fetch failed"]);
});

test("an ordinary link passes on its first answer", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://example.com/a"], {
    fetchImpl: async (url, options) => {
      calls.push(options.method);
      return { status: 200 };
    },
  });
  assert.deepEqual(failures, []);
  assert.deepEqual(calls, ["HEAD"]);
});

test("an ordinary link that rejects HEAD with 405 passes on the HEAD alone", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://example.com/b"], {
    fetchImpl: async (url, options) => {
      calls.push(options.method);
      return { status: options.method === "HEAD" ? 405 : 200 };
    },
  });
  assert.deepEqual(failures, []);
  assert.deepEqual(calls, ["HEAD"]);
});

test("an ordinary link whose HEAD is inconclusive passes on the GET retry", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://example.com/retry"], {
    fetchImpl: async (url, options) => {
      calls.push(options.method);
      return { status: options.method === "HEAD" ? 500 : 200 };
    },
  });
  assert.deepEqual(failures, []);
  assert.deepEqual(calls, ["HEAD", "GET"]);
});

test("an ordinary link that is gone fails with its status", async () => {
  const calls = [];
  const failures = await checkExternalLinks(["https://example.com/c"], {
    fetchImpl: async (url, options) => {
      calls.push(options.method);
      return { status: 404 };
    },
  });
  assert.deepEqual(failures, ["https://example.com/c: HTTP 404"]);
  assert.deepEqual(calls, ["HEAD", "GET"]);
});
