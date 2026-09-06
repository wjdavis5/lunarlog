// index.test.ts (Issue #5, Unit U5)
//
// handlePushDispatch takes all real I/O as injected PushDispatchDeps, so
// every case here runs with fakes: no live Supabase project, no FCM
// credential, no network. The "production claim predicate" test at the
// bottom drives buildDeps' own claimBatch closure against a fake client
// that really enforces WHERE-clause filtering (feedback-notify's
// established pattern), so it fails if the `.is("claimed_at", null)` guard
// is ever removed from the real claim query.

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

function row(overrides: Partial<OutboxRow> = {}): OutboxRow {
  return {
    id: "row-1",
    profile_id: "profile-1",
    recipient_user_id: "user-1",
    kind: "logged",
    ...overrides,
  };
}

interface FakeState {
  rows: OutboxRow[];
  devices: Record<string, PushDeviceRow[]>;
  sent: string[];
  released: Array<{ id: string; errorKind: string }>;
  disabledDevices: string[];
  sendCalls: unknown[];
  sendResult: (message: unknown, call: number) => { ok: true } | { ok: false; reason: string };
}

function fakeDeps(state: Partial<FakeState> = {}): PushDispatchDeps & FakeState {
  const s: FakeState = {
    rows: state.rows ?? [],
    devices: state.devices ?? {},
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
    markSent: async (id) => {
      s.sent.push(id);
    },
    releaseClaim: async (id, errorKind) => {
      s.released.push({ id, errorKind });
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
    rows: [row()],
    devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
    sendResult: () => ({ ok: false, reason: "network_error" }),
  });

  await handlePushDispatch(deps);

  assertEquals(deps.sent.length, 0, "sent_at must stay null on a failed send");
  assertEquals(deps.released, [{ id: "row-1", errorKind: "network_error" }]);
});

Deno.test("an unregistered result disables that device row and does not retry it", async () => {
  const deps = fakeDeps({
    rows: [row()],
    devices: { "user-1": [{ id: "device-1", token: "token-1" }] },
    sendResult: () => ({ ok: false, reason: "unregistered" }),
  });

  await handlePushDispatch(deps);

  assertEquals(deps.disabledDevices, ["device-1"]);
  assertEquals(deps.released, [{ id: "row-1", errorKind: "unregistered" }]);
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

/** A minimal fake Supabase client factory whose `.from("notification_outbox")`
 * chain really enforces `.is`/`.lte`/`.lt`/`.eq` filtering against an
 * in-memory row set -- mirrors feedback-notify/index.test.ts's
 * fakeClientFactory. This is what makes the tests below real regression
 * coverage for buildDeps' own claim closure rather than a test double
 * standing in for it. */
function fakeClientFactory(rows: Array<Record<string, unknown>>): SupabaseClientFactory {
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

  const tables: Record<string, Array<Record<string, unknown>>> = { notification_outbox: rows };

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
      };
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
    { id: "row-future", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, deliver_after: future, attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  const claimed = await deps.claimBatch(10);

  assertEquals(claimed, [], "a row whose deliver_after has not arrived yet must not be claimed");
});

Deno.test("a row already claimed_at by another invocation is not claimed again", async () => {
  const past = new Date(Date.now() - 60_000).toISOString();
  const rows = [
    { id: "row-claimed", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: past, deliver_after: past, attempts: 0 },
  ];
  const deps = buildDeps(fullEnv, fakeClientFactory(rows));

  const claimed = await deps.claimBatch(10);

  assertEquals(claimed, [], "a row already claimed by another invocation must not be claimed again");
});

Deno.test("production claim predicate: buildDeps' claimBatch really requires claimed_at IS NULL", async () => {
  const past = new Date(Date.now() - 60_000).toISOString();
  const rows = [
    { id: "row-1", profile_id: "p1", recipient_user_id: "u1", kind: "logged", claimed_at: null, deliver_after: past, attempts: 0 },
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
