// index.test.ts (Issue #243/D-24, round 2 fix; #17 U2/U3)
//
// `delete-account` previously had no `deno test` file at all - it was only
// proven by local `supabase functions serve` + curl smoke tests (see
// docs/ops/supabase-go-live.md). This suite does not attempt to cover every
// branch that runbook already exercises (in particular the Apple-revoke
// paths beyond a bare failure/success check); it covers what Issue #243
// added and then hardened: the fail-closed feedback-attachments Storage
// cleanup step (now Step 4, reordered ahead of row deletion and Apple
// revocation by the round 2 fix) and its ordering relative to the other
// steps, plus the paginated/recursive listing and batched removal the round
// 2 fix added. `handleDeleteAccount` takes all real I/O as an injected
// `DeleteAccountDeps`, so every case here runs with fakes: no live Supabase
// project, no Apple credentials, no network.
//
// Run locally with `deno test supabase/functions/delete-account/`.

import { assertEquals } from "jsr:@std/assert@1";
import {
  buildDeps,
  handleDeleteAccount,
  type DeleteAccountCaller,
  type DeleteAccountDeps,
  type DeleteAccountEnv,
  type SupabaseClientFactory,
} from "./index.ts";
import type { AppleRevokeResult } from "../_shared/apple_revoke.ts";

function postRequest(body: Record<string, unknown> = {}, { withAuth = true }: { withAuth?: boolean } = {}): Request {
  return new Request("https://example.test/delete-account", {
    method: "POST",
    headers: withAuth ? { Authorization: "Bearer caller-jwt" } : {},
    body: JSON.stringify(body),
  });
}

interface FakeDepsOverrides {
  user?: DeleteAccountCaller | null;
  deleteAccountDataResult?: { data: unknown; error: unknown };
  revokeResult?: AppleRevokeResult;
  attachmentPaths?: string[] | null;
  removeResult?: boolean;
  rehomeError?: unknown;
  deleteUserError?: unknown;
}

/** A deps fake recording every call it receives (in order, with enough
 * argument detail to assert ordering and exact-path claims), so a test can
 * check both "was X called" and "was X called before/with the right
 * argument as Y". */
function fakeDeps(overrides: FakeDepsOverrides = {}): { deps: DeleteAccountDeps; calls: string[] } {
  const calls: string[] = [];
  const deps: DeleteAccountDeps = {
    getUser: async () => {
      calls.push("getUser");
      return overrides.user === undefined ? { id: "user-1", providers: [] } : overrides.user;
    },
    listAttachmentPaths: async (uid) => {
      calls.push(`listAttachmentPaths:${uid}`);
      return overrides.attachmentPaths === undefined ? [] : overrides.attachmentPaths;
    },
    removeAttachmentPaths: async (paths) => {
      calls.push(`removeAttachmentPaths:${paths.join(",")}`);
      return overrides.removeResult === undefined ? true : overrides.removeResult;
    },
    deleteAccountData: async () => {
      calls.push("deleteAccountData");
      return overrides.deleteAccountDataResult ?? { data: { profiles: 1 }, error: null };
    },
    revokeApple: async () => {
      calls.push("revokeApple");
      return overrides.revokeResult ?? { kind: "ok" };
    },
    rehomeStrayDayEntries: async () => {
      calls.push("rehomeStrayDayEntries");
      return { error: overrides.rehomeError ?? null };
    },
    deleteUser: async () => {
      calls.push("deleteUser");
      return { error: overrides.deleteUserError ?? null };
    },
  };
  return { deps, calls };
}

Deno.test("a missing Authorization header is rejected with 401 and nothing is called", async () => {
  const { deps, calls } = fakeDeps();

  const response = await handleDeleteAccount(postRequest({}, { withAuth: false }), deps);

  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.code, "unauthorized");
  assertEquals(calls, [], "no dependency call should happen without an Authorization header");
});

Deno.test("an invalid caller identity (getUser returns null) is rejected with 401", async () => {
  const { deps, calls } = fakeDeps({ user: null });

  const response = await handleDeleteAccount(postRequest(), deps);

  assertEquals(response.status, 401);
  assertEquals(calls, ["getUser"], "nothing past auth resolution runs for an unresolvable caller");
});

Deno.test("an apple identity with no authorization code fails closed with 400, before any row is touched", async () => {
  const { deps, calls } = fakeDeps({ user: { id: "user-1", providers: ["apple"] } });

  const response = await handleDeleteAccount(postRequest({}), deps);

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.code, "apple_code_required");
  assertEquals(calls, ["getUser"], "nothing - not even attachment listing - must run without a required apple code");
});

Deno.test(
  "attachment listing failure fails the whole deletion closed, before any row is touched: 409 " +
    "attachment_cleanup_failed, deleteAccountData/deleteUser never called (round 2 fix: reordered ahead of row deletion)",
  async () => {
    const { deps, calls } = fakeDeps({ attachmentPaths: null });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 409);
    const body = await response.json();
    assertEquals(body.code, "attachment_cleanup_failed");
    assertEquals(
      calls,
      ["getUser", "listAttachmentPaths:user-1"],
      "a listing failure must stop before deleteAccountData, removeAttachmentPaths, and deleteUser - nothing touched",
    );
  },
);

Deno.test(
  "attachment removal failure fails the whole deletion closed, before any row is touched: 409 " +
    "attachment_cleanup_failed, deleteAccountData/deleteUser never called",
  async () => {
    const { deps, calls } = fakeDeps({
      attachmentPaths: ["user-1/t1/a.png"],
      removeResult: false,
    });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 409);
    const body = await response.json();
    assertEquals(body.code, "attachment_cleanup_failed");
    assertEquals(
      calls,
      ["getUser", "listAttachmentPaths:user-1", "removeAttachmentPaths:user-1/t1/a.png"],
      "a removal failure must stop before deleteAccountData and deleteUser - nothing touched",
    );
    assertEquals(calls.includes("deleteUser"), false, "the user must not be deleted after a failed attachment removal");
    assertEquals(calls.includes("deleteAccountData"), false, "no row deletion after a failed attachment removal");
  },
);

Deno.test(
  "no attachments to remove (empty prefix): removeAttachmentPaths is never called, and deletion still succeeds " +
    "with deleteUser still called",
  async () => {
    const { deps, calls } = fakeDeps({ attachmentPaths: [] });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.ok, true);
    assertEquals(
      calls,
      ["getUser", "listAttachmentPaths:user-1", "deleteAccountData", "rehomeStrayDayEntries", "deleteUser"],
      "removeAttachmentPaths must not be called with an empty path list",
    );
  },
);

Deno.test(
  "attachments present: listAttachmentPaths is called with the caller's uid and removeAttachmentPaths with " +
    "exactly those paths, before any row deletion or deleteUser",
  async () => {
    const { deps, calls } = fakeDeps({
      user: { id: "uid-42", providers: [] },
      attachmentPaths: ["uid-42/t1/a.png", "uid-42/t2/b.jpg"],
    });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 200);
    assertEquals(calls, [
      "getUser",
      "listAttachmentPaths:uid-42",
      "removeAttachmentPaths:uid-42/t1/a.png,uid-42/t2/b.jpg",
      "deleteAccountData",
      "rehomeStrayDayEntries",
      "deleteUser",
    ]);
  },
);

Deno.test(
  "a delete_account_data failure returns 500 unknown, after attachment cleanup already succeeded, and stops " +
    "before Apple/deleteUser",
  async () => {
    const { deps, calls } = fakeDeps({
      deleteAccountDataResult: { data: null, error: { message: "boom" } },
    });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 500);
    const body = await response.json();
    assertEquals(body.code, "unknown");
    assertEquals(calls, ["getUser", "listAttachmentPaths:user-1", "deleteAccountData"]);
  },
);

Deno.test(
  "an apple revoke failure returns 409 apple_revoke_failed and stops before deleteUser (attachment cleanup and " +
    "row deletion already succeeded by this point)",
  async () => {
    const { deps, calls } = fakeDeps({
      user: { id: "user-1", providers: ["apple"] },
      revokeResult: { kind: "apple_rejected" },
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "code-1" }), deps);

    assertEquals(response.status, 409);
    const body = await response.json();
    assertEquals(body.code, "apple_revoke_failed");
    assertEquals(calls, ["getUser", "listAttachmentPaths:user-1", "deleteAccountData", "revokeApple"]);
    assertEquals(calls.includes("deleteUser"), false, "the user must not be deleted after a failed apple revoke");
  },
);

Deno.test("happy path (no apple identity): succeeds end to end with 200 ok:true", async () => {
  const { deps } = fakeDeps({ attachmentPaths: ["user-1/t1/a.png"] });

  const response = await handleDeleteAccount(postRequest(), deps);

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.ok, true);
});

Deno.test("a delete_user failure returns 500 delete_user_failed, after everything else already ran", async () => {
  const { deps, calls } = fakeDeps({ deleteUserError: { message: "boom" } });

  const response = await handleDeleteAccount(postRequest(), deps);

  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.code, "delete_user_failed");
  assertEquals(calls, ["getUser", "listAttachmentPaths:user-1", "deleteAccountData", "rehomeStrayDayEntries", "deleteUser"]);
});

// ---------------------------------------------------------------------------
// buildDeps: the production listAttachmentPaths/removeAttachmentPaths wiring
// against a fake Storage client that really enforces the same shape a real
// Supabase Storage bucket does (a "folder" entry has a null id; a real
// object has a non-null one, and `list()` pages via `limit`/`offset`) - so
// these are regression tests for the actual pagination/recursive-listing
// and batched-removal logic, not only for a hand-rolled fake standing in
// for it (mirroring feedback-notify/index.test.ts's "production claim
// predicate" test and its own header comment on why that distinction
// matters).
// ---------------------------------------------------------------------------

interface FakeListEntry {
  id: string | null;
  name: string;
}

/** A minimal fake Supabase client factory whose `storage.from(bucket)`
 * exposes `.list(path, { limit, offset })` (paginating a fixed fixture
 * array per path via a real slice, or returning an error) and
 * `.remove(paths)` (recording every call, optionally failing). Slicing by
 * `limit`/`offset` - rather than always returning the whole fixture array -
 * is what lets a single large fixture array double as a two-page fixture:
 * the production code's own `LIST_PAGE_SIZE` decides where the page
 * boundary falls. */
function fakeStorageClientFactory(opts: {
  listResults: Record<string, FakeListEntry[] | "error">;
  removeShouldFail?: boolean;
}): { factory: SupabaseClientFactory; removedCalls: string[][] } {
  const removedCalls: string[][] = [];
  const client = {
    storage: {
      from(bucket: string) {
        if (bucket !== "feedback-attachments") {
          throw new Error(`fakeStorageClientFactory: unexpected bucket ${bucket}`);
        }
        return {
          async list(path: string, options?: { limit?: number; offset?: number }) {
            const result = opts.listResults[path];
            if (result === undefined) return { data: [], error: null };
            if (result === "error") return { data: null, error: { message: "list failed" } };
            const limit = options?.limit ?? result.length;
            const offset = options?.offset ?? 0;
            return { data: result.slice(offset, offset + limit), error: null };
          },
          async remove(paths: string[]) {
            removedCalls.push(paths);
            if (opts.removeShouldFail) return { data: null, error: { message: "remove failed" } };
            return { data: paths.map((name) => ({ name })), error: null };
          },
        };
      },
    },
  };
  return { factory: () => client, removedCalls };
}

const fullEnv: DeleteAccountEnv = {
  supabaseUrl: "https://example.test",
  anonKey: "anon-key",
  serviceRoleKey: "service-role-key",
};

Deno.test(
  "buildDeps: listAttachmentPaths recurses one level per ticket folder and collects every file's full path",
  async () => {
    const { factory } = fakeStorageClientFactory({
      listResults: {
        "uid1": [
          { id: null, name: "ticket-a" },
          { id: null, name: "ticket-b" },
        ],
        "uid1/ticket-a": [{ id: "obj-1", name: "file1.png" }],
        "uid1/ticket-b": [
          { id: "obj-2", name: "file2.png" },
          { id: "obj-3", name: "file3.jpg" },
        ],
      },
    });
    const deps = buildDeps(fullEnv, factory);

    const paths = await deps.listAttachmentPaths("uid1");

    assertEquals(
      (paths ?? []).sort(),
      ["uid1/ticket-a/file1.png", "uid1/ticket-b/file2.png", "uid1/ticket-b/file3.jpg"].sort(),
    );
  },
);

Deno.test(
  "buildDeps: listAttachmentPaths recurses into a folder nested three levels deep (round 2 fix - not just one " +
    "level per ticket folder)",
  async () => {
    const { factory } = fakeStorageClientFactory({
      listResults: {
        "uid1": [{ id: null, name: "a" }],
        "uid1/a": [{ id: null, name: "b" }],
        "uid1/a/b": [{ id: null, name: "c" }],
        "uid1/a/b/c": [{ id: "obj-1", name: "deep.png" }],
      },
    });
    const deps = buildDeps(fullEnv, factory);

    const paths = await deps.listAttachmentPaths("uid1");

    assertEquals(paths, ["uid1/a/b/c/deep.png"]);
  },
);

Deno.test(
  "buildDeps: listAttachmentPaths pages with offset until a page returns fewer than the limit, and every page's " +
    "paths are collected (round 2 fix)",
  async () => {
    // 1003 entries at "uid1": production's LIST_PAGE_SIZE (1000) means the
    // first list() call returns exactly 1000 (a full page, forcing a
    // second call), and the second returns the remaining 3 (a partial
    // page, ending the loop).
    const allEntries: FakeListEntry[] = Array.from({ length: 1003 }, (_, i) => ({
      id: `obj-${i}`,
      name: `file${i}.png`,
    }));
    const { factory } = fakeStorageClientFactory({
      listResults: { "uid1": allEntries },
    });
    const deps = buildDeps(fullEnv, factory);

    const paths = await deps.listAttachmentPaths("uid1");

    const expected = allEntries.map((e) => `uid1/${e.name}`);
    assertEquals((paths ?? []).sort(), expected.sort());
    assertEquals(paths?.length, 1003, "both the full first page and the partial second page must be collected");
  },
);

Deno.test("buildDeps: listAttachmentPaths returns an empty array when the caller has no attachments (empty prefix)", async () => {
  const { factory } = fakeStorageClientFactory({ listResults: { "uid1": [] } });
  const deps = buildDeps(fullEnv, factory);

  const paths = await deps.listAttachmentPaths("uid1");

  assertEquals(paths, []);
});

Deno.test("buildDeps: listAttachmentPaths returns null when the top-level list call fails", async () => {
  const { factory } = fakeStorageClientFactory({ listResults: { "uid1": "error" } });
  const deps = buildDeps(fullEnv, factory);

  const paths = await deps.listAttachmentPaths("uid1");

  assertEquals(paths, null);
});

Deno.test("buildDeps: listAttachmentPaths returns null when a nested ticket-folder list call fails", async () => {
  const { factory } = fakeStorageClientFactory({
    listResults: {
      "uid1": [{ id: null, name: "ticket-a" }],
      "uid1/ticket-a": "error",
    },
  });
  const deps = buildDeps(fullEnv, factory);

  const paths = await deps.listAttachmentPaths("uid1");

  assertEquals(paths, null);
});

Deno.test("buildDeps: removeAttachmentPaths calls storage remove with exactly the given paths when under the batch size", async () => {
  const { factory, removedCalls } = fakeStorageClientFactory({ listResults: {} });
  const deps = buildDeps(fullEnv, factory);

  const ok = await deps.removeAttachmentPaths(["uid1/t1/a.png", "uid1/t2/b.png"]);

  assertEquals(ok, true);
  assertEquals(removedCalls, [["uid1/t1/a.png", "uid1/t2/b.png"]]);
});

Deno.test(
  "buildDeps: removeAttachmentPaths batches at 100 paths per storage remove() call (round 2 fix)",
  async () => {
    const { factory, removedCalls } = fakeStorageClientFactory({ listResults: {} });
    const deps = buildDeps(fullEnv, factory);
    const paths = Array.from({ length: 250 }, (_, i) => `uid1/t/${i}.png`);

    const ok = await deps.removeAttachmentPaths(paths);

    assertEquals(ok, true);
    assertEquals(removedCalls.length, 3, "250 paths at a 100-path batch size is 3 calls (100, 100, 50)");
    assertEquals(removedCalls.map((batch) => batch.length), [100, 100, 50]);
    assertEquals(removedCalls.flat(), paths, "every path must be covered, in order, across the batches");
  },
);

Deno.test("buildDeps: removeAttachmentPaths reports false on a storage removal failure", async () => {
  const { factory } = fakeStorageClientFactory({ listResults: {}, removeShouldFail: true });
  const deps = buildDeps(fullEnv, factory);

  const ok = await deps.removeAttachmentPaths(["uid1/t1/a.png"]);

  assertEquals(ok, false);
});

Deno.test(
  "buildDeps: removeAttachmentPaths stops at the first failing batch and reports false (fail-closed)",
  async () => {
    const { factory, removedCalls } = fakeStorageClientFactory({ listResults: {}, removeShouldFail: true });
    const deps = buildDeps(fullEnv, factory);
    const paths = Array.from({ length: 150 }, (_, i) => `uid1/t/${i}.png`);

    const ok = await deps.removeAttachmentPaths(paths);

    assertEquals(ok, false);
    assertEquals(removedCalls.length, 1, "the first failing batch must stop further removal calls");
  },
);
