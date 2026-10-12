// Unit tests for the external-link check (issue #1899 added the DOI case).
// Plain `node --test` (`npm test` from site/): the check takes an injected
// fetch, so the branches are driven without a network and without a built
// site.

import assert from "node:assert/strict";
import { test } from "node:test";

import { checkExternalLinks, doiFromUrl } from "./check-external-links.mjs";

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
      calls.push({ url, method: options.method ?? "GET" });
      return { status: 200 };
    },
  });
  assert.deepEqual(failures, []);
  // The publisher is never contacted: one GET of the Crossref record, nothing else.
  assert.deepEqual(calls, [
    { url: "https://api.crossref.org/works/10.1002/ijgo.12666", method: "GET" },
  ]);
});

test("a DOI Crossref reports 404 for fails", async () => {
  const failures = await checkExternalLinks(["https://doi.org/10.1002/gone"], {
    fetchImpl: async () => ({ status: 404 }),
  });
  assert.deepEqual(failures, ["https://doi.org/10.1002/gone: DOI not found (Crossref 404)"]);
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
