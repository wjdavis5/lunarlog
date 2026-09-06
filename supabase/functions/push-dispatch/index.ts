// push-dispatch (Issue #5, Unit U5)
//
// Drains public.notification_outbox to FCM HTTP v1. Invoked two ways
// (KTD3): a Database Webhook on notification_outbox insert (immediacy), and
// public.trigger_push_dispatch() via pg_net from the nightly pg_cron job
// (quiet-hours releases, retries, and stuck-claim recovery via
// public.sweep_notification_outbox()). Both send the same shared secret in
// the `x-push-dispatch-webhook-secret` header (dashboard-configured for the
// webhook; a GUC setting for the cron path -- see
// 20260906180000_reminder_windows_and_cron.sql and
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
}

export interface PushDeviceRow {
  id: string;
  token: string;
}

/** Every real I/O call handlePushDispatch needs, injected so tests can
 * supply fakes instead of a live Supabase project / FCM credential. */
export interface PushDispatchDeps {
  /** True only when every required secret/credential is present. Missing
   * config degrades to "nothing dispatched" rather than a visible failure --
   * both callers (webhook, cron) treat this function as best-effort. */
  configured: boolean;
  /** Atomically claims up to [limit] pending, due, not-yet-exhausted rows.
   * Implemented as one conditional UPDATE per candidate id (KTD2, mirroring
   * feedback-notify's single-row claim), so two overlapping invocations
   * (the webhook and a cron sweep, or two cron sweeps) can never both claim
   * the same row. */
  claimBatch(limit: number): Promise<OutboxRow[]>;
  /** The recipient's active (non-disabled) devices. */
  devicesFor(userId: string): Promise<PushDeviceRow[]>;
  /** Stamps sent_at, the terminal success state for a row. */
  markSent(id: string): Promise<void>;
  /** Releases a claim this same invocation just won, after every device
   * attempt for it failed: clears claimed_at (so a later claim can retry
   * it), increments attempts, and records last_error_kind. */
  releaseClaim(id: string, errorKind: string): Promise<void>;
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
    const devices = await deps.devicesFor(row.recipient_user_id);

    if (devices.length === 0) {
      // Nothing to send to -- mark sent rather than retrying forever
      // against a recipient with no registered device.
      await deps.markSent(row.id);
      processed++;
      continue;
    }

    let anyFailure = false;
    let lastErrorKind = "";

    for (const device of devices) {
      const message = buildPushMessage(row.profile_id, device.token);
      const result = await deps.sendPush(message);
      if (!result.ok) {
        anyFailure = true;
        lastErrorKind = result.reason;
        if (result.reason === "unregistered") {
          await deps.disableDevice(device.id);
        }
      }
    }

    if (anyFailure) {
      await deps.releaseClaim(row.id, lastErrorKind);
    } else {
      await deps.markSent(row.id);
    }
    processed++;
  }

  return { processed };
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
      const { data: candidates, error } = await client!
        .from("notification_outbox")
        .select("id, profile_id, recipient_user_id, kind")
        .is("claimed_at", null)
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
          .select("id, profile_id, recipient_user_id, kind")
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
    markSent: async (id) => {
      await client!.from("notification_outbox").update({ sent_at: new Date().toISOString() }).eq("id", id);
    },
    releaseClaim: async (id, errorKind) => {
      const { data } = await client!
        .from("notification_outbox")
        .select("attempts")
        .eq("id", id)
        .maybeSingle();
      const attempts = (data?.attempts as number | undefined) ?? 0;
      await client!
        .from("notification_outbox")
        .update({ claimed_at: null, attempts: attempts + 1, last_error_kind: errorKind })
        .eq("id", id);
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
