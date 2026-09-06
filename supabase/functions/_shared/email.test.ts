// _shared/email.test.ts (Issue #6, U9; PR #105 review round 7)
//
// Covers `sendEmail`'s `AbortSignal.timeout(...)` wiring and its
// `timeout`/`network_error` failure classification - both previously
// uncovered by the suite. Before this file existed, deleting the timeout
// entirely, inflating its duration to something absurd (e.g. 999 seconds),
// or swapping the two failure-reason strings all left every existing test
// green (see email.ts's header comment for the production risk that made
// this a blocking gap - a hung Resend call parking the whole invocation
// past the claim it already committed).
//
// `apiKey`/`from` are plain parameters rather than something `sendEmail`
// reads from `Deno.env` itself (round 7 hoisted them out for exactly this
// reason - see email.ts's header comment and index.ts's own env-as-plain-
// object pattern), so this file needs no `--allow-env` permission: `deno
// test` runs it with the same defaults as every other test in this suite.
//
// Run locally with `deno test supabase/functions/_shared/`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { sendEmail } from "./email.ts";
import type { EmailEnvelope } from "./format.ts";

const envelope: EmailEnvelope = {
  to: "user@example.test",
  subject: "Subject",
  html: "<p>Hi</p>",
  text: "Hi",
};

/** Swaps `globalThis.fetch` and/or `AbortSignal.timeout` for the duration of
 * `run`, restoring the originals afterward even if `run` throws - so a
 * failing assertion in one test can never leak a stub into the next. */
async function withStubs<T>(
  stubs: { fetch?: typeof fetch; timeout?: typeof AbortSignal.timeout },
  run: () => Promise<T>,
): Promise<T> {
  const originalFetch = globalThis.fetch;
  const originalTimeout = AbortSignal.timeout;
  if (stubs.fetch) globalThis.fetch = stubs.fetch;
  if (stubs.timeout) AbortSignal.timeout = stubs.timeout;
  try {
    return await run();
  } finally {
    globalThis.fetch = originalFetch;
    AbortSignal.timeout = originalTimeout;
  }
}

Deno.test(
  "sendEmail applies AbortSignal.timeout(...) - bounded well under a minute - to the fetch call",
  async () => {
    const timeoutCalls: number[] = [];
    const fakeSignal = new AbortController().signal;
    let capturedSignal: AbortSignal | undefined;

    await withStubs(
      {
        timeout: ((ms: number) => {
          timeoutCalls.push(ms);
          return fakeSignal;
        }) as typeof AbortSignal.timeout,
        fetch: (async (_input: RequestInfo | URL, init?: RequestInit) => {
          capturedSignal = init?.signal ?? undefined;
          return new Response(null, { status: 200 });
        }) as typeof fetch,
      },
      () => sendEmail(envelope, "key", "from@example.test"),
    );

    assertEquals(
      timeoutCalls.length,
      1,
      "sendEmail must call AbortSignal.timeout exactly once per send - deleting the timeout leaves this at 0",
    );
    const [ms] = timeoutCalls;
    assert(ms > 0, "the timeout duration must be positive");
    assert(
      ms <= 30_000,
      `the timeout duration (${ms}ms) must stay comfortably under any platform-level function timeout - ` +
        "not something absurd like 999 seconds",
    );
    assertEquals(
      capturedSignal,
      fakeSignal,
      "the signal returned by AbortSignal.timeout must actually reach fetch's own options",
    );
  },
);

Deno.test("sendEmail classifies an aborted (timed-out) fetch as reason 'timeout'", async () => {
  await withStubs(
    {
      fetch: (async () => {
        // What a real `fetch` throws when the `AbortSignal.timeout(...)`
        // passed to it fires before the request completes.
        throw new DOMException("The signal has been aborted", "TimeoutError");
      }) as typeof fetch,
    },
    async () => {
      const result = await sendEmail(envelope, "key", "from@example.test");
      assertEquals(result, { ok: false, reason: "timeout" });
    },
  );
});

Deno.test(
  "sendEmail classifies a non-timeout fetch failure as reason 'network_error', not 'timeout'",
  async () => {
    await withStubs(
      {
        fetch: (async () => {
          throw new TypeError("network down");
        }) as typeof fetch,
      },
      async () => {
        const result = await sendEmail(envelope, "key", "from@example.test");
        assertEquals(result, { ok: false, reason: "network_error" });
      },
    );
  },
);

// PR #105 review round 8: `!response.ok` was mutation-dead - deleting that
// branch entirely (so a Resend 4xx/5xx response fell through to `{ ok: true
// }`) left every test in this file green. That is the failure mode the
// header comment above describes as the worst case: `releaseClaim` never
// runs and the ticket's admin alert is silently and permanently lost. This
// test pins the branch by asserting the *shape* of the result (`ok: false`
// with a status-carrying reason), not merely that a value was returned.
Deno.test(
  "sendEmail reports failure, not success, when Resend responds with a " +
    "non-2xx status (a bad API key, a malformed payload, or a Resend outage)",
  async () => {
    await withStubs(
      {
        fetch: (async () =>
          new Response(JSON.stringify({ message: "Invalid API key" }), {
            status: 401,
          })) as typeof fetch,
      },
      async () => {
        const result = await sendEmail(envelope, "bad-key", "from@example.test");
        assertEquals(
          result,
          { ok: false, reason: "resend_status_401" },
          "a 4xx/5xx Resend response must never read as { ok: true } - the " +
            "caller's claim-before-send guard depends on this to release " +
            "the claim and retry the alert",
        );
      },
    );
  },
);

Deno.test(
  "sendEmail reports failure with reason 'missing_email_config' when the " +
    "Resend API key or the from address is missing, and never calls fetch",
  async () => {
    let fetchCalled = false;
    const stubbedFetch = (async () => {
      fetchCalled = true;
      return new Response(null, { status: 200 });
    }) as typeof fetch;

    await withStubs({ fetch: stubbedFetch }, async () => {
      const result = await sendEmail(envelope, undefined, "from@example.test");
      assertEquals(result, { ok: false, reason: "missing_email_config" });
    });
    assert(!fetchCalled, "a missing apiKey must short-circuit before fetch");

    await withStubs({ fetch: stubbedFetch }, async () => {
      const result = await sendEmail(envelope, "key", undefined);
      assertEquals(result, { ok: false, reason: "missing_email_config" });
    });
    assert(!fetchCalled, "a missing from address must short-circuit before fetch");
  },
);
