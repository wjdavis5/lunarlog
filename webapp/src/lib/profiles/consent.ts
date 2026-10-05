import { z } from '../zod';

import type { AppSupabaseClient } from '../supabase';
import { MINIMUM_AGE_POLICY_VERSION } from '../sharing';

/**
 * The minimum-age acknowledgement's read half (issue #1253) — the web
 * mirror of `SupabaseConsentService.fetchMinimumAgeAcknowledgement`
 * (lib/data/consent/supabase_consent_service.dart, issue #845). The write
 * half lives in `sharing.ts`'s `recordMinimumAgeAcknowledgement`; the
 * invite path already uses it for the parent-invite consent.
 *
 * The read never throws: no session, offline, a server error, or a
 * malformed row all read as `null` ("no usable record"), exactly like the
 * app — a caller deciding whether to re-prompt treats "could not read"
 * the same as "no record yet".
 */

/** The acknowledgement was made by the operator themselves (the 13+ statement). */
export const CONSENT_VIA_SELF_13_PLUS = 'self_13_plus';

/** One stored acknowledgement, as the client reads it. */
export interface ConsentRecord {
  consentVia: string;
  acknowledgedAt: string;
  appVersion: string;
  policyVersion: string;
}

const consentRowSchema = z.object({
  consent_via: z.string(),
  acknowledged_at: z.string(),
  app_version: z.string(),
  policy_version: z.string(),
});

/**
 * Reads the caller's own `account_consents` row (owner-only RLS,
 * 20260921100000). Best-effort by contract.
 */
export async function fetchMinimumAgeAcknowledgement(
  client: AppSupabaseClient,
): Promise<ConsentRecord | null> {
  try {
    const { data, error } = await client
      .from('account_consents')
      .select('consent_via, acknowledged_at, app_version, policy_version')
      .maybeSingle();
    if (error !== null || data === null) return null;
    const parsed = consentRowSchema.safeParse(data);
    if (!parsed.success) return null;
    return {
      consentVia: parsed.data.consent_via,
      acknowledgedAt: parsed.data.acknowledged_at,
      appVersion: parsed.data.app_version,
      policyVersion: parsed.data.policy_version,
    };
  } catch {
    return null;
  }
}

/**
 * Whether the caller must (re-)acknowledge before creating a profile: no
 * readable record, or one written under an older policy version — the
 * same re-prompt rule `_checkAgeAcknowledgment` applies on the app
 * (issue #845).
 */
export function needsMinimumAgeAcknowledgement(record: ConsentRecord | null): boolean {
  return record === null || record.policyVersion !== MINIMUM_AGE_POLICY_VERSION;
}
