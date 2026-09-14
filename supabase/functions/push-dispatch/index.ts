// push-dispatch (Issue #5, Unit U5)
//
// Drains public.notification_outbox to FCM HTTP v1. Invoked two ways
// (KTD3): a Database Webhook on notification_outbox insert (immediacy), and
// public.trigger_push_dispatch() via pg_net from the nightly pg_cron job
// (quiet-hours releases, retries, and stuck-claim recovery via
// public.sweep_notification_outbox()). Both send the same shared secret in
// the `x-push-dispatch-webhook-secret` header (dashboard-configured for the
// webhook; a GUC setting for the cron path -- see
// 20260906230000_reminder_windows_and_cron.sql and
// docs/ops/supabase-go-live.md), the same pattern feedback-reply already
// uses for its own webhook-only invocation.
//
// This handler never reads day_entries, profiles, or notification_preferences
// -- it needs none of them, and that is the enforcement of KTD1: the outbox
// row and the FCM payload it produces (via _shared/notification_copy.ts)
// already carry everything eligible content this function is allowed to see.
//
// Thin by design, exactly like feedback-notify/index.ts: all real I/O is an
// injected PushDispatchDeps, so the claim-before-send batch loop (KTD2) is
// covered by `deno test` with fakes -- no live Supabase project or FCM
// credential required (see index.test.ts).

import { createClient } from "@supabase/supabase-js";
import { buildPushMessage } from "../_shared/notification_copy.ts";
import { createPushSender, type ServiceAccountCredentials } from "../_shared/push.ts";

const WEBHOOK_SECRET_HEADER = "x-push-dispatch-webhook-secret";

/** Bounded so one invocation can't run unboundedly long; the next webhook
 * fire or cron sweep picks up whatever this batch didn't reach. */
const BATCH_SIZE = 25;

/** Once a row has failed this many times, it stops being claimed (an
 * effectively-dead row per the plan's state diagram) -- there is no
 * separate "dead" flag, this is the claim query's own bound. */
const MAX_ATTEMPTS = 10;

export interface OutboxRow {
  id: string;
  profile_id: string;
  recipient_user_id: string;
  kind: string;
  /** The exact `claimed_at` value this invocation claimed the row with --
   * threaded back into releaseClaim as an optimistic-lock token (Issue #526
   * fix (b)) rather than releaseClaim re-reading it itself (the old
   * non-atomic select-then-update this replaces). */
  claimed_at: string;
}

export interface PushDeviceRow {
  id: string;
  token: string;
}

/** The outcome of re-validating one claimed row right before it actually
 * reaches a device (Issue #630): "send" (still eligible), "cancel" (the
 * governing guardian membership or kind/cadence preference has since made
 * this row undeliverable -- LLA-074/LLA-076), "defer" (quiet hours have
 * opened since the row became due -- LLA-075, carrying the new
 * `deliverAfter` to release the claim to), or "retry" (the recheck itself
 * could not be answered -- an RPC error, no data, or an action string this
 * client does not recognise). "retry" must never be treated as "send": a
 * database hiccup on the one check that enforces revocation/opt-out/quiet
 * hours is exactly the moment those protections matter most, so an
 * unanswerable recheck fails closed (the row is released for the next
 * drain to try again) rather than defaulting to delivery. */
export type DispatchResolution =
  | { action: "send" }
  | { action: "cancel"; reason: string }
  | { action: "defer"; deliverAfter: string }
  | { action: "retry" };

/** Every real I/O call handlePushDispatch needs, injected so tests can
 * supply fakes instead of a live Supabase project / FCM credential. */
export interface PushDispatchDeps {
  /** True only when every required secret/credential is present. Missing
   * config degrades to "nothing dispatched" rather than a visible failure --
   * both callers (webhook, cron) treat this function as best-effort. */
  configured: boolean;
  /** Atomically claims up to [limit] pending, due, not-yet-exhausted, not
   * already-sent rows. Implemented as one conditional UPDATE per candidate
   * id (KTD2, mirroring feedback-notify's single-row claim), so two
   * overlapping invocations (the webhook and a cron sweep, or two cron
   * sweeps) can never both claim the same row. */
  claimBatch(limit: number): Promise<OutboxRow[]>;
  /** The recipient's active (non-disabled) devices. */
  devicesFor(userId: string): Promise<PushDeviceRow[]>;
  /** Device ids already recorded as successfully delivered for this outbox
   * row, from this or an earlier claim of it (Issue #526 fix (a): per-device
   * delivery tracking). A device in this set is never re-sent to on a later
   * attempt at the same row -- this is what stops one failing device on a
   * multi-device recipient from causing every already-succeeded device to
   * be re-alerted on every retry. */
  deliveredDeviceIds(outboxId: string): Promise<Set<string>>;
  /** Records a successful delivery to one device for one outbox row.
   * Idempotent (an upsert) -- recording the same (outboxId, deviceId) pair
   * twice, e.g. across two overlapping invocations, is harmless. */
  recordDelivery(outboxId: string, deviceId: string): Promise<void>;
  /** Stamps sent_at, the terminal success state for a row. */
  markSent(id: string): Promise<void>;
  /** Atomically releases a claim this same invocation just won, after at
   * least one device attempt for it failed: clears claimed_at (so a later
   * claim can retry it), increments attempts, and records last_error_kind --
   * one `UPDATE ... WHERE id = $1 AND claimed_at = $2` (Issue #526 fix (b)),
   * replacing a prior non-atomic read-modify-write on `attempts` that could
   * silently drop an increment or reset the counter to 1 on a failed read. */
  releaseClaim(id: string, claimedAt: string, errorKind: string): Promise<void>;
  /** Re-validates a just-claimed row against the current state of the
   * world (Issue #630, LLA-074/LLA-075/LLA-076) -- deliberately called
   * fresh per row rather than trusting claimBatch's snapshot, since the
   * whole point is to catch a change (revocation, an opt-out, quiet hours
   * opening) that happened after the claim. */
  resolveDispatch(outboxId: string): Promise<DispatchResolution>;
  /** Permanently removes a row resolveDispatch found no longer eligible --
   * revoked, or its governing kind/cadence preference was turned off since
   * enqueue (LLA-074/LLA-076). Deleting rather than marking sent matches
   * revoke_guardian's own precedent (Issue #5): a cancelled row was never
   * delivered, so sent_at would be a false audit signal. `claimedAt` pins
   * the delete to the row exactly as this invocation claimed it (the same
   * optimistic-lock shape as releaseClaim/deferClaim), so a cancel can
   * never delete a row a different drain has since re-claimed (e.g. after
   * a sweep released it). */
  cancelRow(outboxId: string, claimedAt: string): Promise<void>;
  /** Releases a claim without counting it as a failed attempt (LLA-075):
   * quiet hours re-opened between when the row became due and this
   * dispatch, so it is deferred to `deliverAfter` rather than sent, and
   * this is not the kind of failure `releaseClaim`'s attempts/
   * last_error_kind bookkeeping exists for. */
  deferClaim(id: string, claimedAt: string, deliverAfter: string): Promise<void>;
  /** Releases a claim with no attempts increment and no deliver_after
   * change (Issue #630 review): resolveDispatch itself could not be
   * answered (an RPC error, no data, or an unrecognised action), which is
   * a transient infra problem, not a delivery failure charged against
   * this row's MAX_ATTEMPTS budget the way a real send failure is via
   * releaseClaim. The row stays exactly as due as it already was, so the
   * next drain (the webhook's next fire, or the cron sweep) claims it
   * again and re-runs the recheck. */
  releaseForRetry(id: string, claimedAt: string): Promise<void>;
  /** Marks a device row disabled after FCM reports its token unregistered --
   * that device stops being returned by devicesFor from then on. */
  disableDevice(deviceId: string): Promise<void>;
  /** Sends one FCM HTTP v1 message; resolves rather than throws on failure. */
  sendPush(message: unknown): Promise<{ ok: true } | { ok: false; reason: string }>;
}

export interface DispatchResult {
  processed: number;
}

/** The full drain logic (Issue #5, U5). Claims a bounded batch, then for
 * each row sends to every one of the recipient's devices: a recipient with
 * zero devices is marked sent immediately (nothing to loop on forever); any
 * device failure releases the claim for a later retry; an unregistered
 * device is disabled so it stops being tried. */
export async function handlePushDispatch(deps: PushDispatchDeps): Promise<DispatchResult> {
  if (!deps.configured) {
    // #2 (review fix): a missing secret must never be silent. Without this
    // log, a totally misconfigured deployment (e.g. FCM_PRIVATE_KEY never
    // set) is indistinguishable from a healthy one with nothing currently
    // due -- both return 200 with { processed: 0 } -- and stays that way
    // until someone happens to notice the outbox table filling up. Both
    // callers (webhook, cron) still treat this function as best-effort, so
    // the response itself is unchanged; this only makes the outage visible
    // in the function's own logs.
    console.error(
      "push-dispatch: not configured -- missing one or more of SUPABASE_URL, " +
        "SUPABASE_SERVICE_ROLE_KEY, FCM_PROJECT_ID, FCM_CLIENT_EMAIL, " +
        "FCM_PRIVATE_KEY. Every alert is silently dropped until this function " +
        "secret is set (see docs/ops/supabase-go-live.md).",
    );
    return { processed: 0 };
  }

  const rows = await deps.claimBatch(BATCH_SIZE);
  let processed = 0;

  for (const row of rows) {
    await dispatchOneRow(deps, row);
    processed++;
  }

  return { processed };
}

/** Everything this invocation does for one already-claimed row (Issue
 * #630): re-validate before touching any device, then cancel, defer, or
 * actually send. Split out of handlePushDispatch's loop to keep each
 * decision -- revalidate, then send -- its own small function. */
async function dispatchOneRow(deps: PushDispatchDeps, row: OutboxRow): Promise<void> {
  const resolution = await deps.resolveDispatch(row.id);
  if (resolution.action === "cancel") {
    // LLA-074/LLA-076: the row was claimed, but a revocation or a
    // preference/cadence turned off since then means the underlying
    // profile activity signal must never reach this recipient. The
    // in-flight window between claim and this check is unavoidable (a
    // send already handed to FCM cannot be recalled either); this closes
    // it to the smallest possible gap rather than the unbounded one the
    // pre-fix code left open.
    await deps.cancelRow(row.id, row.claimed_at);
    return;
  }
  if (resolution.action === "defer") {
    // LLA-075: quiet hours re-opened between when the row became due and
    // now (a delayed dispatch, a retry, or a promoted digest). Deferred,
    // not sent and not counted as a failed attempt.
    await deps.deferClaim(row.id, row.claimed_at, resolution.deliverAfter);
    return;
  }
  if (resolution.action === "retry") {
    // Review fix: the recheck itself could not be answered (an RPC error,
    // no data, or an action this client build does not recognise) --
    // fails closed rather than defaulting to send, since this is exactly
    // the check that enforces revocation/opt-out/quiet hours. Released
    // with no attempts increment: a transient DB hiccup on the recheck is
    // not a delivery failure against this row.
    await deps.releaseForRetry(row.id, row.claimed_at);
    return;
  }
  if (resolution.action !== "send") {
    // Defense in depth: buildDeps' own resolveDispatch already maps any
    // action string it doesn't recognise to "retry" before it ever
    // reaches here, but this function's only other caller is a test
    // double -- never assume every PushDispatchDeps implementation
    // upholds that mapping. Anything that isn't an explicit "send" is
    // treated exactly like "retry": never send blind on an ambiguous
    // resolution to the one check that enforces revocation/opt-out/quiet
    // hours.
    await deps.releaseForRetry(row.id, row.claimed_at);
    return;
  }
  await sendToDevices(deps, row);
}

/** The original per-row send loop (Issue #526): every one of the
 * recipient's devices not already recorded delivered. A recipient with
 * zero pending devices is marked sent immediately (nothing to loop on
 * forever); any device failure releases the claim for a later retry; an
 * unregistered device is disabled so it stops being tried. */
async function sendToDevices(deps: PushDispatchDeps, row: OutboxRow): Promise<void> {
  const devices = await deps.devicesFor(row.recipient_user_id);
  // Issue #526 fix (a): per-device delivery tracking. A device already
  // recorded as delivered (from this row's current claim or an earlier
  // one) is never sent to again -- without this, one failing device on a
  // multi-device recipient (releaseClaim below) re-triggered a resend to
  // *every* device on the next retry, including ones that had already
  // succeeded.
  const delivered = await deps.deliveredDeviceIds(row.id);
  const pending = devices.filter((device) => !delivered.has(device.id));

  if (pending.length === 0) {
    // Nothing left to send to -- either the recipient has zero devices at
    // all, or every device has already been successfully delivered to on
    // a prior attempt at this row. Mark sent rather than retrying
    // forever, or re-sending to devices that already succeeded.
    await deps.markSent(row.id);
    return;
  }

  let anyFailure = false;
  let lastErrorKind = "";

  for (const device of pending) {
    const message = buildPushMessage(row.profile_id, device.token);
    const result = await deps.sendPush(message);
    if (result.ok) {
      await deps.recordDelivery(row.id, device.id);
    } else {
      anyFailure = true;
      lastErrorKind = result.reason;
      if (result.reason === "unregistered") {
        await deps.disableDevice(device.id);
      }
    }
  }

  if (anyFailure) {
    await deps.releaseClaim(row.id, row.claimed_at, lastErrorKind);
  } else {
    await deps.markSent(row.id);
  }
}

export interface PushDispatchEnv {
  supabaseUrl: string | undefined;
  serviceRoleKey: string | undefined;
  webhookSecret: string | undefined;
  fcmProjectId: string | undefined;
  fcmClientEmail: string | undefined;
  fcmPrivateKey: string | undefined;
}

// deno-lint-ignore no-explicit-any
export type SupabaseClientFactory = (url: string, key: string) => any;

/** Builds the production PushDispatchDeps as a plain function of its
 * environment and a client factory, mirroring feedback-notify's buildDeps --
 * this is what lets `deno test` exercise the real claim predicate instead of
 * only ever running a hand-rolled fake for it (see index.test.ts's
 * "production claim predicate" coverage). */
export function buildDeps(env: PushDispatchEnv, clientFactory: SupabaseClientFactory): PushDispatchDeps {
  const configured = !!(
    env.supabaseUrl &&
    env.serviceRoleKey &&
    env.fcmProjectId &&
    env.fcmClientEmail &&
    env.fcmPrivateKey
  );
  const client = configured ? clientFactory(env.supabaseUrl!, env.serviceRoleKey!) : null;
  const creds: ServiceAccountCredentials | null = configured
    ? { projectId: env.fcmProjectId!, clientEmail: env.fcmClientEmail!, privateKey: env.fcmPrivateKey! }
    : null;
  // #6 (round-2 review; round-1 #13): one push sender -- and so one minted
  // OAuth access token, reused across every send -- per buildDeps call, not
  // one per (row, device). buildDeps is called once per function
  // invocation (see the bottom of this file), so this closure's lifetime is
  // exactly one invocation's batch.
  const pushSender = configured ? createPushSender(creds!) : null;

  return {
    configured,
    claimBatch: async (limit) => {
      // Issue #526 fix (d): `.is("sent_at", null)` -- without it, a row a
      // slow/duplicated invocation had already sent (but whose claimed_at
      // release raced ahead of, or was never reached because of, a
      // markSent that then also succeeded) could be re-claimed and
      // re-sent. deliver_after/attempts bound *when* and *how many times*
      // a row is retried; sent_at is the separate terminal-state guard that
      // stops an already-delivered row from ever being claimed again.
      const { data: candidates, error } = await client!
        .from("notification_outbox")
        .select("id, profile_id, recipient_user_id, kind, claimed_at")
        .is("claimed_at", null)
        .is("sent_at", null)
        .lte("deliver_after", new Date().toISOString())
        .lt("attempts", MAX_ATTEMPTS)
        .order("created_at", { ascending: true })
        .limit(limit);
      if (error || !candidates) return [];

      const claimed: OutboxRow[] = [];
      for (const candidate of candidates) {
        const { data, error: claimError } = await client!
          .from("notification_outbox")
          .update({ claimed_at: new Date().toISOString() })
          .eq("id", candidate.id)
          .is("claimed_at", null)
          .select("id, profile_id, recipient_user_id, kind, claimed_at")
          .maybeSingle();
        if (!claimError && data) claimed.push(data as OutboxRow);
      }
      return claimed;
    },
    devicesFor: async (userId) => {
      const { data, error } = await client!
        .from("push_devices")
        .select("id, token")
        .eq("user_id", userId)
        .is("disabled_at", null);
      return error || !data ? [] : (data as PushDeviceRow[]);
    },
    deliveredDeviceIds: async (outboxId) => {
      const { data, error } = await client!
        .from("notification_outbox_deliveries")
        .select("device_id")
        .eq("outbox_id", outboxId);
      if (error || !data) return new Set<string>();
      return new Set((data as Array<{ device_id: string }>).map((row) => row.device_id));
    },
    recordDelivery: async (outboxId, deviceId) => {
      const { error } = await client!
        .from("notification_outbox_deliveries")
        .upsert({ outbox_id: outboxId, device_id: deviceId, sent_at: new Date().toISOString() });
      if (error) {
        console.error(
          `push-dispatch: failed to record delivery for outbox row ${outboxId} device ${deviceId}: ` +
            `a retry of this row could re-send to this device (${error.message ?? "unknown error"})`,
        );
      }
    },
    markSent: async (id) => {
      await client!.from("notification_outbox").update({ sent_at: new Date().toISOString() }).eq("id", id);
    },
    releaseClaim: async (id, claimedAt, errorKind) => {
      // Issue #526 fix (b): one atomic RPC (`UPDATE ... WHERE id = $1 AND
      // claimed_at = $2`) replaces the old non-atomic
      // select-then-update -- see the migration for the full rationale.
      const { error } = await client!.rpc("release_notification_outbox_claim", {
        p_id: id,
        p_claimed_at: claimedAt,
        p_error_kind: errorKind,
      });
      if (error) {
        console.error(`push-dispatch: release_notification_outbox_claim failed for row ${id}: ${error.message ?? "unknown error"}`);
      }
    },
    resolveDispatch: async (outboxId) => {
      // Issue #630: one round trip that re-joins profile_guardians +
      // notification_preferences server-side (the SQL function's own
      // pgTAP coverage proves the eligibility/quiet-hours logic itself;
      // this closure is just the plumbing to it) rather than duplicating
      // that join and resolve_deliver_after's zone math here in TS.
      const { data, error } = await client!.rpc("resolve_notification_outbox_dispatch", {
        p_id: outboxId,
      });
      if (error || !data) {
        // Review fix: an infra hiccup on the recheck itself must fail
        // closed, not open -- this is exactly the check that enforces
        // revocation/opt-out/quiet hours, so defaulting to "send" here
        // would defeat LLA-074/075/076 precisely when the database is
        // unhealthy. "retry" releases the claim (no attempts increment;
        // see releaseForRetry) so the next drain re-runs this same check
        // rather than either sending blind or burning the row's
        // MAX_ATTEMPTS budget on a transient DB error.
        console.error(
          `push-dispatch: resolve_notification_outbox_dispatch failed for row ${outboxId}, retrying rather ` +
            `than sending without a recheck: ${error?.message ?? "no data returned"}`,
        );
        return { action: "retry" };
      }
      const result = data as { action: string; reason?: string; deliver_after?: string };
      if (result.action === "cancel") return { action: "cancel", reason: result.reason ?? "unknown" };
      if (result.action === "defer" && result.deliver_after) {
        return { action: "defer", deliverAfter: result.deliver_after };
      }
      if (result.action === "send") return { action: "send" };
      // An action string this client build does not recognise (e.g. a
      // newer SQL function deployed ahead of this function revision) gets
      // the same fail-closed treatment as an outright error -- never
      // silently treated as "send".
      console.error(
        `push-dispatch: resolve_notification_outbox_dispatch returned an unrecognised action ` +
          `"${result.action}" for row ${outboxId}, retrying rather than sending without a recheck`,
      );
      return { action: "retry" };
    },
    cancelRow: async (outboxId, claimedAt) => {
      // Review fix: pinned to claimed_at (the same optimistic-lock shape
      // as releaseClaim/deferClaim) so a cancel can never delete a row a
      // different drain has since re-claimed (e.g. after a sweep released
      // it), and the delete's own error is logged rather than swallowed.
      const { error } = await client!
        .from("notification_outbox")
        .delete()
        .eq("id", outboxId)
        .eq("claimed_at", claimedAt);
      if (error) {
        console.error(`push-dispatch: cancelRow failed for row ${outboxId}: ${error.message ?? "unknown error"}`);
      }
    },
    deferClaim: async (id, claimedAt, deliverAfter) => {
      // Same optimistic-lock shape as releaseClaim (WHERE id = $1 AND
      // claimed_at = $2), but never touches attempts/last_error_kind --
      // quiet hours re-opening is not a failure.
      const { error } = await client!
        .from("notification_outbox")
        .update({ claimed_at: null, deliver_after: deliverAfter })
        .eq("id", id)
        .eq("claimed_at", claimedAt);
      if (error) {
        console.error(`push-dispatch: deferClaim failed for row ${id}: ${error.message ?? "unknown error"}`);
      }
    },
    releaseForRetry: async (id, claimedAt) => {
      // Review fix: clears claimed_at only -- no attempts increment (a
      // failed recheck is a transient infra problem, not a delivery
      // failure charged against MAX_ATTEMPTS the way releaseClaim's
      // failures are) and no deliver_after change (the row is exactly as
      // due as it already was).
      const { error } = await client!
        .from("notification_outbox")
        .update({ claimed_at: null })
        .eq("id", id)
        .eq("claimed_at", claimedAt);
      if (error) {
        console.error(`push-dispatch: releaseForRetry failed for row ${id}: ${error.message ?? "unknown error"}`);
      }
    },
    disableDevice: async (deviceId) => {
      await client!.from("push_devices").update({ disabled_at: new Date().toISOString() }).eq("id", deviceId);
    },
    sendPush: (message) => pushSender!(message),
  };
}

// Guarded so index.test.ts can import handlePushDispatch/buildDeps without
// this module trying to bind a real network listener under `deno test`
// (which runs with no --allow-net) -- import.meta.main is true only when
// Deno runs this file directly, how the Supabase Edge Runtime invokes it.
if (import.meta.main) {
  Deno.serve(async (req) => {
    const expectedSecret = Deno.env.get("PUSH_DISPATCH_WEBHOOK_SECRET");
    const providedSecret = req.headers.get(WEBHOOK_SECRET_HEADER);
    if (!expectedSecret || providedSecret !== expectedSecret) {
      // #10 (round-2 review): the sibling not-configured branch above logs a
      // missing secret; this branch must too. The Database Webhook config
      // and the app.settings.push_dispatch_webhook_secret GUC (the cron
      // path) are two independently-set copies of the same shared secret
      // (docs/ops/supabase-go-live.md) -- drift between them silently kills
      // every dispatch invocation with a bare 401 and no other signal
      // anywhere, the same failure class #2 covers for the unconfigured
      // branch.
      console.error(
        !expectedSecret
          ? "push-dispatch: PUSH_DISPATCH_WEBHOOK_SECRET is not set -- every " +
              "call is rejected with 401 until this function secret is set " +
              "(see docs/ops/supabase-go-live.md)."
          : "push-dispatch: rejected a call with a missing or mismatched " +
              `${WEBHOOK_SECRET_HEADER} header -- check the Database Webhook ` +
              "config and the app.settings.push_dispatch_webhook_secret GUC " +
              "have not drifted (see docs/ops/supabase-go-live.md).",
      );
      return new Response(null, { status: 401 });
    }

    const deps = buildDeps(
      {
        supabaseUrl: Deno.env.get("SUPABASE_URL"),
        serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        webhookSecret: expectedSecret,
        fcmProjectId: Deno.env.get("FCM_PROJECT_ID"),
        fcmClientEmail: Deno.env.get("FCM_CLIENT_EMAIL"),
        fcmPrivateKey: Deno.env.get("FCM_PRIVATE_KEY"),
      },
      createClient,
    );

    try {
      const result = await handlePushDispatch(deps);
      return new Response(JSON.stringify(result), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (error) {
      console.error(`push-dispatch: unhandled error: ${error instanceof Error ? error.message : String(error)}`);
      return new Response(null, { status: 500 });
    }
  });
}
