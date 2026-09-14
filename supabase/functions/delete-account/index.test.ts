// index.test.ts (Issue #243/D-24, round 2 fix; #17 U2/U3; #526's neighbours
// #527/#559/#560)
//
// `delete-account` previously had no `deno test` file at all - it was only
// proven by local `supabase functions serve` + curl smoke tests (see
// docs/ops/supabase-go-live.md). This suite does not attempt to cover every
// branch that runbook already exercises (in particular the real Apple-revoke
// network calls, which live in `_shared/apple_revoke.ts` and are faked here
// via `revokeApple`); it covers the fail-closed/ordering contracts of
// `handleDeleteAccount` itself: the feedback-attachments Storage cleanup
// step (Step 4, fail-closed and bounded per Issue #559), the Apple-identity
// determination and revoke-once-then-skip-on-retry behavior (Issues
// #560/#527), and their ordering relative to the other steps.
// `handleDeleteAccount` takes all real I/O as an injected `DeleteAccountDeps`,
// so every case here runs with fakes: no live Supabase project, no Apple
// credentials, no network.
//
// Run locally with `deno test supabase/functions/delete-account/`.

import { assertEquals } from "jsr:@std/assert@1";
import {
  buildDeps,
  handleDeleteAccount,
  type DeleteAccountCaller,
  type DeleteAccountDeps,
  type DeleteAccountEnv,
  type DeletionProgress,
  type ListAttachmentsResult,
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

function baseUser(overrides: Partial<DeleteAccountCaller> = {}): DeleteAccountCaller {
  return {
    id: "user-1",
    providers: [],
    appleIdentityId: null,
    identitiesKnown: true,
    ...overrides,
  };
}

interface FakeDepsOverrides {
  user?: DeleteAccountCaller | null;
  progress?: DeletionProgress;
  deleteAccountDataResult?: { data: unknown; error: unknown };
  revokeResult?: AppleRevokeResult;
  markAppleRevokedResult?: boolean;
  listResult?: ListAttachmentsResult;
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
      return overrides.user === undefined ? baseUser() : overrides.user;
    },
    getDeletionProgress: async (uid) => {
      calls.push(`getDeletionProgress:${uid}`);
      return overrides.progress ?? { appleRevokedAt: null, appleIdentityId: null };
    },
    markAppleRevoked: async (uid, appleIdentityId) => {
      calls.push(`markAppleRevoked:${uid}:${appleIdentityId}`);
      return overrides.markAppleRevokedResult === undefined ? true : overrides.markAppleRevokedResult;
    },
    listAttachmentPaths: async (uid) => {
      calls.push(`listAttachmentPaths:${uid}`);
      return overrides.listResult ?? { ok: true, paths: [] };
    },
    removeAttachmentPaths: async (paths) => {
      calls.push(`removeAttachmentPaths:${paths.join(",")}`);
      return overrides.removeResult === undefined ? true : overrides.removeResult;
    },
    deleteAccountData: async () => {
      calls.push("deleteAccountData");
      return overrides.deleteAccountDataResult ?? { data: { profiles: 1 }, error: null };
    },
    revokeApple: async (_code, expectedAppleUserId) => {
      calls.push(`revokeApple:${expectedAppleUserId}`);
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

// ---------------------------------------------------------------------------
// Issue #560: identity determination and Apple-identity binding.
// ---------------------------------------------------------------------------

Deno.test(
  "#560: a caller whose identities could not be determined (GoTrue omitted `identities`) fails closed " +
    "with 500, before anything is touched",
  async () => {
    const { deps, calls } = fakeDeps({ user: baseUser({ identitiesKnown: false }) });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 500);
    const body = await response.json();
    assertEquals(body.code, "identity_check_failed");
    assertEquals(calls, ["getUser"], "nothing must run once identity determination itself has failed");
  },
);

Deno.test(
  "#560: revokeApple is called with the caller's own appleIdentityId, never anything from the request body",
  async () => {
    const { deps, calls } = fakeDeps({
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }),
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "code-1" }), deps);

    assertEquals(response.status, 200);
    assertEquals(calls.includes("revokeApple:apple-sub-123"), true);
  },
);

Deno.test("#560: an identity_mismatch revoke result is treated the same as any other revoke failure (409)", async () => {
  const { deps, calls } = fakeDeps({
    user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }),
    revokeResult: { kind: "identity_mismatch" },
  });

  const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "victims-code" }), deps);

  assertEquals(response.status, 409);
  const body = await response.json();
  assertEquals(body.code, "apple_revoke_failed");
  assertEquals(calls.includes("deleteUser"), false, "the user must not be deleted after an identity mismatch");
  assertEquals(calls.includes("markAppleRevoked:user-1"), false, "a mismatched identity must never be marked revoked");
});

// ---------------------------------------------------------------------------
// Issue #527: the deletion-progress marker skips Steps 3/6 on retry.
// ---------------------------------------------------------------------------

Deno.test(
  "#527: a successful apple revoke marks the progress marker before deleteUser runs",
  async () => {
    const { deps, calls } = fakeDeps({
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }),
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "code-1" }), deps);

    assertEquals(response.status, 200);
    const revokeIdx = calls.indexOf("revokeApple:apple-sub-123");
    const markIdx = calls.indexOf("markAppleRevoked:user-1:apple-sub-123");
    const deleteUserIdx = calls.indexOf("deleteUser");
    assertEquals(revokeIdx >= 0 && markIdx > revokeIdx && deleteUserIdx > markIdx, true,
      "the marker must be written after a successful revoke and before deleteUser");
  },
);

// ---------------------------------------------------------------------------
// Issue #599: the marker write is fail-closed, not best-effort.
// ---------------------------------------------------------------------------

Deno.test(
  "#599: a markAppleRevoked failure after a successful revoke stops the whole call closed with a " +
    "distinct code, before deleteUser is ever attempted",
  async () => {
    const { deps, calls } = fakeDeps({
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }),
      markAppleRevokedResult: false,
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "code-1" }), deps);

    assertEquals(response.status, 409);
    const body = await response.json();
    assertEquals(body.code, "apple_revocation_marker_failed");
    assertEquals(
      calls.includes("deleteUser"),
      false,
      "deleteUser must never run once the revocation could not be durably recorded",
    );
    assertEquals(calls, [
      "getUser",
      "getDeletionProgress:user-1",
      "listAttachmentPaths:user-1",
      "deleteAccountData",
      "revokeApple:apple-sub-123",
      "markAppleRevoked:user-1:apple-sub-123",
    ]);
  },
);

Deno.test(
  "#527: once the progress marker shows apple_revoked_at set for the caller's current Apple identity, a " +
    "retry needs no Apple code at all and never calls revokeApple again",
  async () => {
    const { deps, calls } = fakeDeps({
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }),
      progress: { appleRevokedAt: "2026-09-13T00:00:00.000Z", appleIdentityId: "apple-sub-123" },
    });

    // No appleAuthorizationCode in the body at all - a retry after a
    // deleteUser failure should not need the client to fetch a fresh code.
    const response = await handleDeleteAccount(postRequest({}), deps);

    assertEquals(response.status, 200);
    assertEquals(calls.includes("revokeApple:apple-sub-123"), false, "an already-revoked grant must not be re-revoked");
    assertEquals(
      calls.includes("markAppleRevoked:user-1:apple-sub-123"),
      false,
      "the marker must not be re-written when already set",
    );
    assertEquals(calls, [
      "getUser",
      "getDeletionProgress:user-1",
      "listAttachmentPaths:user-1",
      "deleteAccountData",
      "rehomeStrayDayEntries",
      "deleteUser",
    ]);
  },
);

// ---------------------------------------------------------------------------
// Issue #605/LLA-051: the progress marker is bound to the identity it was
// stamped for, not merely to the account.
// ---------------------------------------------------------------------------

Deno.test(
  "#605/LLA-051: a progress marker stamped for a different (since-replaced) Apple identity does not skip " +
    "the code precondition - the account's current identity still needs its own revoke",
  async () => {
    const { deps, calls } = fakeDeps({
      // The account previously had identity "apple-sub-OLD" revoked and
      // recorded, but has since unlinked it and linked a different Apple
      // identity, "apple-sub-NEW".
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-NEW" }),
      progress: { appleRevokedAt: "2026-09-13T00:00:00.000Z", appleIdentityId: "apple-sub-OLD" },
    });

    // No code supplied: if the stale marker were (wrongly) honored, this
    // would skip straight to deleteUser instead of failing closed here.
    const response = await handleDeleteAccount(postRequest({}), deps);

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.code, "apple_code_required");
    assertEquals(
      calls,
      ["getUser", "getDeletionProgress:user-1"],
      "a marker for a different identity must not let the new identity's deletion skip anything",
    );
  },
);

Deno.test(
  "#605/LLA-051: given a fresh code, a progress marker for a different Apple identity still revokes the " +
    "account's current identity (not the stale one) and re-stamps the marker with it",
  async () => {
    const { deps, calls } = fakeDeps({
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-NEW" }),
      progress: { appleRevokedAt: "2026-09-13T00:00:00.000Z", appleIdentityId: "apple-sub-OLD" },
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "fresh-code" }), deps);

    assertEquals(response.status, 200);
    assertEquals(calls.includes("revokeApple:apple-sub-NEW"), true, "the current identity must be revoked");
    assertEquals(calls.includes("revokeApple:apple-sub-OLD"), false, "the stale identity must never be revoked again");
    assertEquals(
      calls.includes("markAppleRevoked:user-1:apple-sub-NEW"),
      true,
      "the marker must be re-stamped with the identity that was actually just revoked",
    );
  },
);

Deno.test(
  "#527: without a progress marker, an apple identity with no code still fails closed with " +
    "apple_code_required (unchanged from the original #17 fix)",
  async () => {
    const { deps, calls } = fakeDeps({ user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-123" }) });

    const response = await handleDeleteAccount(postRequest({}), deps);

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.code, "apple_code_required");
    assertEquals(
      calls,
      ["getUser", "getDeletionProgress:user-1"],
      "nothing - not even attachment listing - must run without a required apple code",
    );
  },
);

// ---------------------------------------------------------------------------
// Issue #559: bounded attachment listing.
// ---------------------------------------------------------------------------

Deno.test(
  "#559: a listing that exceeds the object-count bound fails closed with a distinct 422 " +
    "attachment_cleanup_unbounded code, before any row is touched",
  async () => {
    const { deps, calls } = fakeDeps({ listResult: { ok: false, reason: "too_many_objects" } });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 422);
    const body = await response.json();
    assertEquals(body.code, "attachment_cleanup_unbounded");
    assertEquals(calls, ["getUser", "listAttachmentPaths:user-1"]);
  },
);

Deno.test(
  "#559: a listing that exceeds the depth bound fails closed with the same distinct 422 code",
  async () => {
    const { deps } = fakeDeps({ listResult: { ok: false, reason: "too_deep" } });

    const response = await handleDeleteAccount(postRequest(), deps);

    assertEquals(response.status, 422);
    const body = await response.json();
    assertEquals(body.code, "attachment_cleanup_unbounded");
  },
);

Deno.test(
  "attachment listing failure (not a bound trip) fails the whole deletion closed, before any row is touched: 409 " +
    "attachment_cleanup_failed, deleteAccountData/deleteUser never called (round 2 fix: reordered ahead of row deletion)",
  async () => {
    const { deps, calls } = fakeDeps({ listResult: { ok: false, reason: "list_failed" } });

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
      listResult: { ok: true, paths: ["user-1/t1/a.png"] },
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
    const { deps, calls } = fakeDeps({ listResult: { ok: true, paths: [] } });

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
      user: baseUser({ id: "uid-42" }),
      listResult: { ok: true, paths: ["uid-42/t1/a.png", "uid-42/t2/b.jpg"] },
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
      user: baseUser({ providers: ["apple"], appleIdentityId: "apple-sub-1" }),
      revokeResult: { kind: "apple_rejected" },
    });

    const response = await handleDeleteAccount(postRequest({ appleAuthorizationCode: "code-1" }), deps);

    assertEquals(response.status, 409);
    const body = await response.json();
    assertEquals(body.code, "apple_revoke_failed");
    assertEquals(calls, [
      "getUser",
      "getDeletionProgress:user-1",
      "listAttachmentPaths:user-1",
      "deleteAccountData",
      "revokeApple:apple-sub-1",
    ]);
    assertEquals(calls.includes("deleteUser"), false, "the user must not be deleted after a failed apple revoke");
  },
);

Deno.test("happy path (no apple identity): succeeds end to end with 200 ok:true", async () => {
  const { deps } = fakeDeps({ listResult: { ok: true, paths: ["user-1/t1/a.png"] } });

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

    const result = await deps.listAttachmentPaths("uid1");

    if (!result.ok) throw new Error("expected ok");
    assertEquals(
      result.paths.sort(),
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

    const result = await deps.listAttachmentPaths("uid1");

    if (!result.ok) throw new Error("expected ok");
    assertEquals(result.paths, ["uid1/a/b/c/deep.png"]);
  },
);

Deno.test(
  "buildDeps: listAttachmentPaths pages with offset until a page returns fewer than the limit, and every page's " +
    "paths are collected (round 2 fix)",
  async () => {
    // 1003 entries at "uid1": production's LIST_PAGE_SIZE (1000) means the
    // first list() call returns exactly 1000 (a full page, forcing a
    // second call), and the second returns the remaining 3 (a partial
    // page, ending the loop). This is comfortably under Issue #559's
    // MAX_ATTACHMENT_OBJECTS bound (2000).
    const allEntries: FakeListEntry[] = Array.from({ length: 1003 }, (_, i) => ({
      id: `obj-${i}`,
      name: `file${i}.png`,
    }));
    const { factory } = fakeStorageClientFactory({
      listResults: { "uid1": allEntries },
    });
    const deps = buildDeps(fullEnv, factory);

    const result = await deps.listAttachmentPaths("uid1");

    if (!result.ok) throw new Error("expected ok");
    const expected = allEntries.map((e) => `uid1/${e.name}`);
    assertEquals(result.paths.sort(), expected.sort());
    assertEquals(result.paths.length, 1003, "both the full first page and the partial second page must be collected");
  },
);

Deno.test("buildDeps: listAttachmentPaths returns an empty array when the caller has no attachments (empty prefix)", async () => {
  const { factory } = fakeStorageClientFactory({ listResults: { "uid1": [] } });
  const deps = buildDeps(fullEnv, factory);

  const result = await deps.listAttachmentPaths("uid1");

  if (!result.ok) throw new Error("expected ok");
  assertEquals(result.paths, []);
});

Deno.test("buildDeps: listAttachmentPaths reports list_failed when the top-level list call fails", async () => {
  const { factory } = fakeStorageClientFactory({ listResults: { "uid1": "error" } });
  const deps = buildDeps(fullEnv, factory);

  const result = await deps.listAttachmentPaths("uid1");

  assertEquals(result, { ok: false, reason: "list_failed" });
});

Deno.test("buildDeps: listAttachmentPaths reports list_failed when a nested ticket-folder list call fails", async () => {
  const { factory } = fakeStorageClientFactory({
    listResults: {
      "uid1": [{ id: null, name: "ticket-a" }],
      "uid1/ticket-a": "error",
    },
  });
  const deps = buildDeps(fullEnv, factory);

  const result = await deps.listAttachmentPaths("uid1");

  assertEquals(result, { ok: false, reason: "list_failed" });
});

// ---------------------------------------------------------------------------
// Issue #559: object-count and depth bounds.
// ---------------------------------------------------------------------------

Deno.test(
  "#559: a caller with more than MAX_ATTACHMENT_OBJECTS objects reports too_many_objects rather than " +
    "listing forever",
  async () => {
    // 2001 objects: one over the production MAX_ATTACHMENT_OBJECTS (2000)
    // bound.
    const allEntries: FakeListEntry[] = Array.from({ length: 2001 }, (_, i) => ({
      id: `obj-${i}`,
      name: `file${i}.png`,
    }));
    const { factory } = fakeStorageClientFactory({ listResults: { "uid1": allEntries } });
    const deps = buildDeps(fullEnv, factory);

    const result = await deps.listAttachmentPaths("uid1");

    assertEquals(result, { ok: false, reason: "too_many_objects" });
  },
);

Deno.test(
  "#559: a caller nested deeper than MAX_ATTACHMENT_DEPTH reports too_deep rather than recursing forever",
  async () => {
    // Nine nested folder levels - one past the production MAX_ATTACHMENT_DEPTH
    // (8) bound.
    const listResults: Record<string, FakeListEntry[]> = {};
    let path = "uid1";
    for (let level = 0; level < 9; level++) {
      const name = `d${level}`;
      listResults[path] = [{ id: null, name }];
      path = `${path}/${name}`;
    }
    listResults[path] = [{ id: "obj-1", name: "deep.png" }];
    const { factory } = fakeStorageClientFactory({ listResults });
    const deps = buildDeps(fullEnv, factory);

    const result = await deps.listAttachmentPaths("uid1");

    assertEquals(result, { ok: false, reason: "too_deep" });
  },
);

Deno.test(
  "buildDeps: removeAttachmentPaths calls storage remove with exactly the given paths when under the batch size",
  async () => {
    const { factory, removedCalls } = fakeStorageClientFactory({ listResults: {} });
    const deps = buildDeps(fullEnv, factory);

    const ok = await deps.removeAttachmentPaths(["uid1/t1/a.png", "uid1/t2/b.png"]);

    assertEquals(ok, true);
    assertEquals(removedCalls, [["uid1/t1/a.png", "uid1/t2/b.png"]]);
  },
);

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

// ---------------------------------------------------------------------------
// buildDeps: getUser's Apple identity resolution (Issue #560).
// ---------------------------------------------------------------------------

function fakeAuthClientFactory(user: Record<string, unknown> | null): SupabaseClientFactory {
  const client = {
    auth: {
      async getUser() {
        return user ? { data: { user }, error: null } : { data: { user: null }, error: { message: "invalid" } };
      },
    },
  };
  return () => client;
}

Deno.test("buildDeps: getUser resolves appleIdentityId from identities[provider==apple].id", async () => {
  const deps = buildDeps(
    fullEnv,
    fakeAuthClientFactory({
      id: "user-1",
      identities: [
        { provider: "apple", id: "apple-sub-abc" },
        { provider: "email", id: "email-id" },
      ],
    }),
  );

  const user = await deps.getUser("Bearer jwt");

  assertEquals(user?.identitiesKnown, true);
  assertEquals(user?.appleIdentityId, "apple-sub-abc");
  assertEquals(user?.providers.sort(), ["apple", "email"]);
});

Deno.test("buildDeps: getUser reports identitiesKnown=false when identities is omitted entirely", async () => {
  const deps = buildDeps(fullEnv, fakeAuthClientFactory({ id: "user-1" }));

  const user = await deps.getUser("Bearer jwt");

  assertEquals(user?.identitiesKnown, false);
  assertEquals(user?.appleIdentityId, null);
});

Deno.test("buildDeps: getUser reports identitiesKnown=true with a null appleIdentityId for a non-Apple account", async () => {
  const deps = buildDeps(fullEnv, fakeAuthClientFactory({ id: "user-1", identities: [{ provider: "email", id: "e" }] }));

  const user = await deps.getUser("Bearer jwt");

  assertEquals(user?.identitiesKnown, true);
  assertEquals(user?.appleIdentityId, null);
});

// ---------------------------------------------------------------------------
// buildDeps: markAppleRevoked's production retry-once wiring (Issue #599).
// ---------------------------------------------------------------------------

/** A minimal fake Supabase client factory whose `.from("account_deletion_progress")`
 * exposes `.upsert(row)`, resolving each call from `upsertResults` in order
 * (the last entry repeats for any call past the end of the array) and
 * recording every row it was called with. */
function fakeDeletionProgressClientFactory(
  upsertResults: Array<{ error: unknown }>,
): { factory: SupabaseClientFactory; upsertCalls: Record<string, unknown>[] } {
  const upsertCalls: Record<string, unknown>[] = [];
  const client = {
    from(table: string) {
      if (table !== "account_deletion_progress") {
        throw new Error(`fakeDeletionProgressClientFactory: unexpected table ${table}`);
      }
      return {
        async upsert(row: Record<string, unknown>) {
          upsertCalls.push(row);
          const index = Math.min(upsertCalls.length - 1, upsertResults.length - 1);
          return { data: null, error: upsertResults[index].error };
        },
      };
    },
  };
  return { factory: () => client, upsertCalls };
}

Deno.test(
  "buildDeps: markAppleRevoked succeeds on the first attempt without retrying",
  async () => {
    const { factory, upsertCalls } = fakeDeletionProgressClientFactory([{ error: null }]);
    const deps = buildDeps(fullEnv, factory);

    const ok = await deps.markAppleRevoked("user-1", "apple-sub-1");

    assertEquals(ok, true);
    assertEquals(upsertCalls.length, 1);
    assertEquals(upsertCalls[0].user_id, "user-1");
    assertEquals(upsertCalls[0].apple_identity_id, "apple-sub-1");
  },
);

Deno.test(
  "buildDeps: markAppleRevoked retries once and succeeds if the second attempt succeeds (Issue #599)",
  async () => {
    const { factory, upsertCalls } = fakeDeletionProgressClientFactory([
      { error: { message: "transient failure" } },
      { error: null },
    ]);
    const deps = buildDeps(fullEnv, factory);

    const ok = await deps.markAppleRevoked("user-1", "apple-sub-1");

    assertEquals(ok, true, "a retry that succeeds must report success overall");
    assertEquals(upsertCalls.length, 2, "exactly one retry - not more, not zero");
  },
);

Deno.test(
  "buildDeps: markAppleRevoked reports false when both attempts fail (Issue #599)",
  async () => {
    const { factory, upsertCalls } = fakeDeletionProgressClientFactory([
      { error: { message: "failure one" } },
      { error: { message: "failure two" } },
    ]);
    const deps = buildDeps(fullEnv, factory);

    const ok = await deps.markAppleRevoked("user-1", "apple-sub-1");

    assertEquals(ok, false);
    assertEquals(upsertCalls.length, 2, "both the original attempt and its one retry must have run");
  },
);
