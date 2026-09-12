// index.test.ts (Issue #5, Unit U5; Issue #526 retry-robustness fixes)
//
// handlePushDispatch takes all real I/O as injected PushDispatchDeps, so
// every case here runs with fakes: no live Supabase project, no FCM
// credential, no network. The "production claim predicate" tests at the
// bottom drive buildDeps' own claimBatch/releaseClaim closures against a
// fake client that really enforces WHERE-clause filtering (feedback-notify's
// established pattern), so they fail if a guard clause is ever removed from
// the real queries.

import { assertEquals } from "jsr:@std/assert@1";
import {
  buildDeps,
  handlePushDispatch,
  type OutboxRow,
  type PushDeviceRow,
  type PushDispatchDeps,
  type PushDispatchEnv,
  type SupabaseClientFactory,
} from "./index.ts";
import type { FcmMessage } from "../_shared/notification_copy.ts";

const PAST = new Date(Date.now() - 60_000).toISOString();

function row(overrides: Partial<OutboxRow> = {}): OutboxRow {
  return {
    id: "row-1",
    profile_id: "profile-1",
    recipient_user_id: "user-1",
    kind: "logged",
    claimed_at: PAST,
    ...overrides,
  };
}

interface FakeState {
  rows: OutboxRow[];
  devices: Record<string, PushDeviceRow[]>;
  delivered: Record<string, Set<string>>;
  sent: string[];
  released: Array<{ id: string; claimedAt: string; errorKind: string }>;
  disabledDevices: string[];
  sendCalls: unknown[];
  sendResult: (message: unknown, call: number) => { ok: true } | { ok: false; reason: string };
}

function fakeDeps(state: Partial<FakeState> = {}): PushDispatchDeps & FakeState {
  const s: FakeState = {
    rows: state.rows ?? [],
    devices: state.devices ?? {},
    delivered: state.delivered ?? {},
    sent: [],
    released: [],
    disabledDevices: [],
    sendCalls: [],
    sendResult: state.sendResult ?? (() => ({ ok: true })),
  };

  return {
    configured: true,
    claimBatch: async (limit) => s.rows.splice(0, limit),
    devicesFor: async (userId) => s.devices[userId] ?? [],
    deliveredDeviceIds: async (outboxId) => new Set(s.delivered[outboxId] ?? []),
    recordDelivery: async (outboxId, deviceId) => {
      if (!s.delivered[outboxId]) s.delivered[outboxId] = new Set();
      s.delivered[outboxId].add(deviceId);
    },
    markSent: async (id) => {
      s.sent.push(id);
    },
    releaseClaim: async (id, claimedAt, errorKind) => {
      s.released.push({ id, claimedAt, errorKind });
    },
    disableDevice: async (deviceId) => {
      s.disabledDevices.push(deviceId);
    },
    sendPush: async (message) => {
      const result = s.sendResult(message, s.sendCalls.length);
      s.sendCalls.push(message);
      return result;
    },
    get rows() {
      return s.rows;
    },
    get devices() {
      return s.devices;
    },
    get delivered() {
      return s.delivered;
    },
    get sent() {
      return s.sent;
    },
    get released() {
      return s.released;
    },
    get disabledDevices() {
      return s.disabledDevices;
    },
    get sendCalls() {
      return s.sendCalls;
    },
    get sendResult() {
      return s.sendResult;
    },
  };
}

Deno.test("an empty outbox sends nothing", async () => {
  const deps = fakeDeps({ rows: [] });
  const result = await handlePushDispatch(deps);
  assertEquals(result.processed, 0);
  assertEquals(deps.sendCalls.length, 0);
});

Deno.test("one pending row with one device sends once and stamps sent_at", async () => {
  const deps = fakeDeps({
    rows: [row()],
    devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
  });

  const result = await handlePushDispatch(deps);

  assertEquals(result.processed, 1);
  assertEquals(deps.sendCalls.length, 1);
  assertEquals(deps.sent, ["row-1"]);
  assertEquals(deps.released.length, 0);
});

Deno.test("a row with two devices for the recipient sends twice", async () => {
  const deps = fakeDeps({
    rows: [row()],
    devices: {
      "user-1": [
        { id: "device-1", token: "token-1" },
        { id: "device-2", token: "token-2" },
      ],
    },
  });

  await handlePushDispatch(deps);

  assertEquals(deps.sendCalls.length, 2);
  assertEquals(deps.sent, ["row-1"]);
});

Deno.test("a failed send leaves sent_at null, clears claimed_at, and increments attempts", async () => {
  const deps = fakeDeps({
    rows: [row({ claimed_at: PAST })],
    devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
    sendResult: () => ({ ok: false, reason: "network_error" }),
  });

  await handlePushDispatch(deps);

  assertEquals(deps.sent.length, 0, "sent_at must stay null on a failed send");
  assertEquals(deps.released, [{ id: "row-1", claimedAt: PAST, errorKind: "network_error" }]);
});

Deno.test("an unregistered result disables that device row and does not retry it", async () => {
  const deps = fakeDeps({
    rows: [row()],
    devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
    sendResult: () => ({ ok: false, reason: "unregistered" }),
  });

  await handlePushDispatch(deps);

  assertEquals(deps.disabledDevices, ["device-1"]);
  assertEquals(deps.released, [{ id: "row-1", claimedAt: PAST, errorKind: "unregistered" }]);
});

Deno.test("a recipient with zero devices marks the row sent rather than looping forever", async () => {
  const deps = fakeDeps({ rows: [row()], devices: {} });

  await handlePushDispatch(deps);

  assertEquals(deps.sent, ["row-1"]);
  assertEquals(deps.sendCalls.length, 0);
});

Deno.test("missing config sends nothing", async () => {
  const deps = fakeDeps({ rows: [row()], devices: { "user-1": [{ id: "device-1", token: "t" }] } });
  deps.configured = false;

  const result = await handlePushDispatch(deps);

  assertEquals(result.processed, 0);
  assertEquals(deps.sendCalls.length, 0);
});

Deno.test("#2 (review fix): missing config logs an error rather than staying completely silent", async () => {
  const deps = fakeDeps({ rows: [row()], devices: { "user-1": [{ id: "device-1", token: "t" }] } });
  deps.configured = false;

  const originalError = console.error;
  const calls: unknown[][] = [];
  console.error = (...args: unknown[]) => {
    calls.push(args);
  };
  let result;
  try {
    result = await handlePushDispatch(deps);
  } finally {
    console.error = originalError;
  }

  assertEquals(result.processed, 0);
  assertEquals(
    calls.length,
    1,
    "a missing config must be logged -- without this, a totally misconfigured " +
      "deployment (200, { processed: 0 }) is indistinguishable from a healthy " +
      "one with nothing currently due, in both the HTTP response and the function logs",
  );
  assertEquals(String(calls[0][0]).includes("not configured"), true);
});

// ---------------------------------------------------------------------------
// Issue #526 fix (a): per-device delivery tracking.
// ---------------------------------------------------------------------------

Deno.test(
  "#526 (a): a two-device row where one device fails releases the claim, but a retry only re-sends " +
    "to the device that failed -- the already-succeeded device is never re-alerted",
  async () => {
    const deps = fakeDeps({
      rows: [row()],
      devices: {
        "user-1": [
          { id: "device-iphone", token: "token-iphone" },
          { id: "device-ipad", token: "token-ipad" },
        ],
      },
      // The iPad's very first send attempt (call index 1 -- the iPhone's
      // successful send is call index 0) fails; any later attempt (the
      // retry below) succeeds -- modelling "the dead token finally comes
      // back" without needing this fake to know which call is a retry.
      sendResult: (message, call) =>
        (message as FcmMessage).message.token === "token-ipad" && call === 1
          ? { ok: false, reason: "network_error" }
          : { ok: true },
    });

    // First attempt: iPhone succeeds and is recorded delivered; iPad fails,
    // so the row is released for retry.
    await handlePushDispatch(deps);
    assertEquals(deps.sendCalls.length, 2, "both devices are tried on the first attempt");
    assertEquals(deps.sent.length, 0, "the row must not be marked sent while a device attempt is still pending");
    assertEquals(deps.released.length, 1, "the row is released after the iPad's failure");
    assertEquals([...deps.delivered["row-1"]], ["device-iphone"], "only the iPhone is recorded delivered");

    // Simulate the retry: the row is claimed again (same id, new claimed_at
    // from the release), with the iPad's send this time succeeding.
    deps.rows.push(row({ claimed_at: new Date().toISOString() }));
    await handlePushDispatch(deps);

    assertEquals(
      deps.sendCalls.length,
      3,
      "the retry must send only to the iPad (the still-pending device) -- the already-delivered iPhone " +
        "must never be re-sent to, even though the whole row was released",
    );
    assertEquals(deps.sent, ["row-1"], "the row is marked sent once every device has a recorded delivery");
  },
);

Deno.test(
  "#526 (a): a row whose only device is disabled by a previous unregistered failure has nothing left " +
    "to send to on retry and is marked sent immediately",
  async () => {
    const deps = fakeDeps({
      rows: [row()],
      devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
      sendResult: () => ({ ok: false, reason: "unregistered" }),
    });

    await handlePushDispatch(deps);
    assertEquals(deps.disabledDevices, ["device-1"]);
    assertEquals(deps.released.length, 1);

    // Retry: devicesFor now returns nothing for this recipient (the fake
    // doesn't actually filter disabled devices out of `devices`, so model
    // that explicitly, mirroring what the real disabled_at-scoped query
    // would return).
    deps.devices["user-1"] = [];
    deps.rows.push(row({ claimed_at: new Date().toISOString() }));
    const sendCallsBefore = deps.sendCalls.length;
    await handlePushDispatch(deps);

    assertEquals(deps.sendCalls.length, sendCallsBefore, "no send is attempted once the only device is disabled");
    assertEquals(deps.sent, ["row-1"]);
  },
);

// ---------------------------------------------------------------------------
// buildDeps: the production claim/release wiring against a fake Supabase
// client that really enforces WHERE-clause filtering.
// ---------------------------------------------------------------------------

/** A minimal fake Supabase client factory whose `.from(...)` chains really
 * enforce `.is`/`.lte`/`.lt`/`.eq` filtering against in-memory row sets, and
 * whose `.rpc("release_notification_outbox_claim", ...)` really requires
 * `claimed_at` to match, mirroring the real RPC's `WHERE id = $1 AND
 * claimed_at = $2` -- so the tests below are real regression coverage for
 * buildDeps' own closures rather than a test double standing in for them. */
function fakeClientFactory(
  rows: Array<Record<string, unknown>>,
  deliveries: Array<Record<string, unknown>> = [],
): SupabaseClientFactory {
  function makeSelectBuilder(source: Array<Record<string, unknown>>) {
    const filters: Array<(row: Record<string, unknown>) => boolean> = [];
    let orderCol: string | null = null;
    let limitN: number | null = null;
    const builder = {
      is(column: string, value: unknown) {
        filters.push((r) => r[column] === value);
        return builder;
      },
      eq(column: string, value: unknown) {
        filters.push((r) => r[column] === value);
        return builder;
      },
      lte(column: string, value: string) {
        filters.push((r) => (r[column] as string) <= value);
        return builder;
      },
      lt(column: string, value: number) {
        filters.push((r) => (r[column] as number) < value);
        return builder;
      },
      order(column: string) {
        orderCol = column;
        return builder;
      },
      limit(n: number) {
        limitN = n;
        return builder;
      },
      async maybeSingle() {
        const matched = source.filter((r) => filters.every((f) => f(r)));
        return matched.length === 0 ? { data: null, error: null } : { data: { ...matched[0] }, error: null };
      },
      then(onFulfilled: (value: { data: Record<string, unknown>[]; error: null }) => unknown) {
        let matched = source.filter((r) => filters.every((f) => f(r)));
        if (orderCol) matched = [...matched].sort((a, b) => ((a[orderCol!] as string) > (b[orderCol!] as string) ? 1 : -1));
        if (limitN !== null) matched = matched.slice(0, limitN);
        return Promise.resolve({ data: matched.map((r) => ({ ...r })), error: null }).then(onFulfilled);
      },
    };
    return builder;
  }

  function makeUpdateBuilder(source: Array<Record<string, unknown>>, patch: Record<string, unknown>) {
    const filters: Array<(row: Record<string, unknown>) => boolean> = [];
    const builder = {
      eq(column: string, value: unknown) {
        filters.push((r) => r[column] === value);
        return builder;
      },
      is(column: string, value: unknown) {
        filters.push((r) => r[column] === value);
        return builder;
      },
      select(_columns: string) {
        return {
          async maybeSingle() {
            const matched = source.filter((r) => filters.every((f) => f(r)));
            if (matched.length === 0) return { data: null, error: null };
            Object.assign(matched[0], patch);
            return { data: { ...matched[0] }, error: null };
          },
        };
      },
      then(onFulfilled: (value: { error: null }) => unknown) {
        const matched = source.filter((r) => filters.every((f) => f(r)));
        matched.forEach((r) => Object.assign(r, patch));
        return Promise.resolve({ error: null }).then(onFulfilled);
      },
    };
    return builder;
  }

  const tables: Record<string, Array<Record<string, unknown>>> = {
    notification_outbox: rows,
    notification_outbox_deliveries: deliveries,
  };

  const client = {
    from(table: string) {
      const source = tables[table] ?? [];
      return {
        select(_columns: string) {
          return makeSelectBuilder(source);
        },
        update(patch: Record<string, unknown>) {
          return makeUpdateBuilder(source, patch);
        },
        upsert(record: Record<string, unknown>) {
          const existing = deliveries.find(
            (d) => d.outbox_id === record.outbox_id && d.device_id === record.device_id,
          );
          if (existing) Object.assign(existing, record);
          else deliveries.push({ ...record });
          return Promise.resolve({ error: null });
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      if (name !== "release_notification_outbox_claim") {
        throw new Error(`fakeClientFactory: unexpected rpc ${name}`);
      }
      const matched = rows.find((r) => r.id === args.p_id && r.claimed_at === args.p_claimed_at);
      if (matched) {
        matched.claimed_at = null;
        matched.attempts = ((matched.attempts as number) ?? 0) + 1;
        matched.last_error_kind = args.p_error_kind;
      }
      return Promise.resolve({ error: null });
    },
  };

  return () => client;
}

const fullEnv: PushDispatchEnv = {
  supabaseUrl: "https://example.test",
  serviceRoleKey: "service-role-key",
  webhookSecret: "secret",
  fcmProjectId: "test-project",
  fcmClientEmail: "test@test-project.iam.gserviceaccount.com",
  fcmPrivateKey: "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----",
};

Deno.test("a row whose deliver_after is in the future is not claimed", async () => {
  const future = new Date(Date.now() + 60_000).toISOString();
  const rows = [
    { id: "row-future", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, sent_at: null, deliver_after: future, attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  const claimed = await deps.claimBatch(10);

  assertEquals(claimed, [], "a row whose deliver_after has not arrived yet must not be claimed");
});

Deno.test("a row already claimed_at by another invocation is not claimed again", async () => {
  const past = new Date(Date.now() - 60_000).toISOString();
  const rows = [
    { id: "row-claimed", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: past, sent_at: null, deliver_after: past, attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  const claimed = await deps.claimBatch(10);

  assertEquals(claimed, [], "a row already claimed by another invocation must not be claimed again");
});

Deno.test("production claim predicate: buildDeps' claimBatch really requires claimed_at IS NULL", async () => {
  const past = new Date(Date.now() - 60_000).toISOString();
  const rows = [
    { id: "row-1", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, sent_at: null, deliver_after: past, attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  const first = await deps.claimBatch(10);
  const second = await deps.claimBatch(10);

  assertEquals(first.length, 1, "the first claim on an unclaimed, due row must succeed");
  assertEquals(
    second.length,
    0,
    "a second claim on the same now-claimed row must fail - if the claimed_at IS NULL guard is removed " +
      "from the real claim query, this fake (which applies only the filters the query under test actually " +
      "calls) would let it re-match and this assertion would fail",
  );
});

Deno.test(
  "#526 (d): production claim predicate requires sent_at IS NULL -- an already-sent row is never re-claimed " +
    "even if its claimed_at was somehow cleared",
  async () => {
    const past = new Date(Date.now() - 60_000).toISOString();
    const rows = [
      { id: "row-sent", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, sent_at: past, deliver_after: past, attempts: 0 },
    ];
    const deps = buildDeps(fullEnv, fakeClientFactory(rows));

    const claimed = await deps.claimBatch(10);

    assertEquals(
      claimed,
      [],
      "an already-sent row must never be claimed again - if `.is(\"sent_at\", null)` is removed from the " +
        "real claim query, this fake would let it re-match",
    );
  },
);

Deno.test(
  "#526 (b): production releaseClaim RPC really requires claimed_at to match, and increments attempts " +
    "atomically",
  async () => {
    const past = new Date(Date.now() - 60_000).toISOString();
    const rows = [
      {
        id: "row-1",
        profile_id: "p1",
        recipient_user_id: "u1",
        kind: "logged",
        claimed_at: past as string | null,
        sent_at: null,
        deliver_after: past,
        attempts: 3,
        last_error_kind: null as string | null,
      },
    ];
    const deps = buildDeps(fullEnv, fakeClientFactory(rows));

    // A stale claimed_at (not the one the row is actually claimed with)
    // must not match -- mirrors the RPC's own optimistic-lock semantics.
    await deps.releaseClaim("row-1", new Date(0).toISOString(), "network_error");
    assertEquals(rows[0].claimed_at, past, "a mismatched claimed_at token must not release the claim");
    assertEquals(rows[0].attempts, 3, "a mismatched claimed_at token must not increment attempts");

    // The real claimed_at token releases the claim and increments attempts
    // exactly once.
    await deps.releaseClaim("row-1", past, "network_error");
    assertEquals(rows[0].claimed_at, null);
    assertEquals(rows[0].attempts, 4);
    assertEquals(rows[0].last_error_kind, "network_error");
  },
);

Deno.test("#526 (a): deliveredDeviceIds/recordDelivery round-trip through the production wiring", async () => {
  const rows = [
    { id: "row-1", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, sent_at: null, deliver_after: new Date(0).toISOString(), attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  assertEquals([...(await deps.deliveredDeviceIds("row-1"))], []);

  await deps.recordDelivery("row-1", "device-1");

  assertEquals([...(await deps.deliveredDeviceIds("row-1"))], ["device-1"]);
});
