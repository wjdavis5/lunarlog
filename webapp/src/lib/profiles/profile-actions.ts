import {
  editedProfilePayload,
  getSyncedDataCache,
  newProfilePayload,
  nowSyncStamp,
  pushSyncBatch,
  type StoredProfileCore,
} from '../domain';
import type { AppSupabaseClient } from '../supabase';
import type { ProfileRow } from '../schemas';
import { MINIMUM_AGE_POLICY_VERSION, recordMinimumAgeAcknowledgement } from '../sharing';
import pkg from '../../../package.json';
import { CONSENT_VIA_SELF_13_PLUS } from './consent';

/**
 * The profiles page's write actions (issue #1253), composed on the #1252
 * data layer. Every synced write goes through `pushSyncBatch` — the same
 * `sync_push` RPC the phones use, with a client-generated ULID id and
 * client-minted `updated_at` — and the server re-authorises everything
 * (a non-guardian caller's row lands in `rejected`; a viewer's edit is
 * refused server-side). Archiving is `archived_at`, deleting is the
 * `delete_profile_data` RPC (issue #264 — the app's own delete path, a
 * server-side purge of every dependent row plus the guardianships), and
 * the minimum-age acknowledgement rides `record_minimum_age_acknowledgement`
 * exactly as `lib/ui/profiles/first_run_screen.dart` records it on the
 * first profile's creation (issue #845). No new server path ships here.
 */

/** The editable profile fields the app's own profile dialog edits. */
export interface ProfileFields {
  displayName: string;
  /** Create-only: the edit path never flips the flag by itself. */
  isMinor?: boolean;
  birthYear: number | null;
  /**
   * Who the profile is for. `undefined` on an edit leaves the stored value
   * alone: the payload omits the key and the server's containment guard
   * keeps the column. That is what a caller who is not the profile's
   * primary guardian sends (issue #1503) — the server would put her value
   * back anyway (issue #1499). On a create, `undefined` is no relationship.
   */
  relationship?: string | null;
  /** The care mode (`ProfileMode`): standard or teen (choosableModes). */
  mode: string;
  /**
   * The #853 irregular-cycles tri-state: `undefined` preserves the stored
   * value (the payload omits the key and the server's containment guard
   * keeps the column — the app's "untouched control" behaviour),
   * true/false write it explicitly.
   */
  irregularFraming?: boolean;
}

/** The client-side name rule the app validates before creating (R2) —
 * the server CHECK's own bound (kMaxDisplayNameLength, lib/domain/limits.dart). */
export const MAX_DISPLAY_NAME_LENGTH = 80;

/** The app's dialog birth-year window (kMinBirthYear/kMaxBirthYear, profile_dialogs.dart). */
export const MIN_BIRTH_YEAR = 1900;
export const MAX_BIRTH_YEAR = 2200;

export type ProfileValidation =
  | { valid: true }
  | {
      valid: false;
      violation: 'nameEmpty' | 'nameTooLong' | 'birthYearInvalid' | 'birthYearOutOfRange';
    };

/** The app's dialog validates name length and birth-year plausibility. */
export function validateProfileFields(fields: {
  displayName: string;
  birthYear: number | null;
}): ProfileValidation {
  const name = fields.displayName.trim();
  if (name === '') return { valid: false, violation: 'nameEmpty' };
  if (name.length > MAX_DISPLAY_NAME_LENGTH) return { valid: false, violation: 'nameTooLong' };
  if (fields.birthYear !== null) {
    if (!Number.isInteger(fields.birthYear)) {
      return { valid: false, violation: 'birthYearInvalid' };
    }
    if (fields.birthYear < MIN_BIRTH_YEAR || fields.birthYear > MAX_BIRTH_YEAR) {
      return { valid: false, violation: 'birthYearOutOfRange' };
    }
  }
  return { valid: true };
}

export class ProfileActionError extends Error {
  constructor(
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'ProfileActionError';
  }
}

/** The next `sort_order` after a profile list's live rows. */
export function nextSortOrder(rows: Pick<ProfileRow, 'sort_order'>[]): number {
  return rows.reduce((max, row) => Math.max(max, row.sort_order), 0) + 1;
}

export interface CreateProfileArgs {
  fields: ProfileFields;
  /** The live profiles' sort orders (the new row sorts last). */
  existingSortOrders: number[];
  /**
   * When true (the account has no current-version acknowledgement), the
   * creation also records it — `consent_via = self_13_plus`, best-effort
   * exactly like `_recordMinimumAgeConsent` in first_run_screen.dart.
   */
  recordMinimumAgeAck?: boolean;
}

/**
 * Creates a profile. Returns the payload that was pushed (the id is
 * client-generated). The push is the gate — a rejected row throws and the
 * caller keeps the form; the acknowledgement write never fails the
 * creation.
 */
export async function createProfile(
  client: AppSupabaseClient,
  args: CreateProfileArgs,
): Promise<{ id: string }> {
  const payload = newProfilePayload({
    display_name: args.fields.displayName.trim(),
    is_minor: args.fields.isMinor ?? false,
    sort_order: nextSortOrder(args.existingSortOrders.map((sort_order) => ({ sort_order }))),
    birth_year: args.fields.birthYear,
    relationship: args.fields.relationship ?? null,
    mode: args.fields.mode,
    ...(args.fields.irregularFraming === undefined
      ? {}
      : { irregular_framing: args.fields.irregularFraming }),
  });
  const outcome = await pushSyncBatch(client, { profiles: [payload] });
  if (outcome.rejected.length > 0) {
    throw new ProfileActionError('profile create rejected by sync_push');
  }
  if (args.recordMinimumAgeAck === true) {
    try {
      await recordMinimumAgeAcknowledgement(client, {
        consentVia: CONSENT_VIA_SELF_13_PLUS,
        appVersion: WEBAPP_APP_VERSION,
        policyVersion: MINIMUM_AGE_POLICY_VERSION,
      });
    } catch {
      // Best-effort by contract (the app swallows it too; a later
      // creation re-prompts because the account row is what gates it).
    }
  }
  return { id: payload.id };
}

/**
 * Updates a profile's editable fields. The stored row's full-row columns
 * (sort order, archive stamp, creation date) ride along unchanged — the
 * server would otherwise reset them (issue #1388) — and an omitted
 * `irregularFraming` or `relationship` stays omitted, so the server's
 * containment guard preserves the stored value (the relationship is
 * omitted for everyone but the primary guardian, issue #1503).
 */
export async function updateProfile(
  client: AppSupabaseClient,
  profile: StoredProfileCore,
  fields: ProfileFields,
): Promise<void> {
  const payload = editedProfilePayload(profile, {
    display_name: fields.displayName.trim(),
    birth_year: fields.birthYear,
    ...(fields.relationship === undefined ? {} : { relationship: fields.relationship }),
    mode: fields.mode,
    ...(fields.irregularFraming === undefined
      ? {}
      : { irregular_framing: fields.irregularFraming }),
  });
  const outcome = await pushSyncBatch(client, { profiles: [payload] });
  if (outcome.rejected.length > 0) {
    throw new ProfileActionError('profile update rejected by sync_push');
  }
}

/**
 * Archives (or un-archives) a profile by stamping `archived_at`; the rest
 * of the stored row rides along unchanged (issue #1388). Primary guardian
 * only, in both directions: `enforce_profile_guardian_only_deletion`
 * rejects anyone else's change to the stamp.
 */
export async function setProfileArchived(
  client: AppSupabaseClient,
  profile: StoredProfileCore,
  archived: boolean,
): Promise<void> {
  const payload = editedProfilePayload(profile, {
    archived_at: archived ? nowSyncStamp() : null,
  });
  const outcome = await pushSyncBatch(client, { profiles: [payload] });
  if (outcome.rejected.length > 0) {
    throw new ProfileActionError('profile archive rejected by sync_push');
  }
}

/**
 * Deletes a profile permanently through `delete_profile_data(p_profile_id)`
 * (issue #264) — the server purges every dependent row, removes the
 * guardianships, and tombstones the profile. The caller re-pulls from zero
 * afterwards (`repullMembershipData`): the membership reshape never bumps
 * `server_version`s, so an incremental pull cannot converge (issue #1282).
 */
export async function deleteProfile(
  client: AppSupabaseClient,
  profileId: string,
): Promise<void> {
  const { error } = await client.rpc('delete_profile_data', {
    p_profile_id: profileId,
  });
  if (error !== null) {
    throw new ProfileActionError(`delete_profile_data failed: ${error.message}`);
  }
  // The purge changed far more than the profile row; drop the cached
  // snapshot so the next pull rebuilds from zero instead of merging over
  // rows the server no longer returns.
  getSyncedDataCache().reset();
}

/**
 * The `app_version` the acknowledgement writes — the web client's own
 * package version (the invite-accept path records the same value; the app
 * writes its pubspec version the same way).
 */
export const WEBAPP_APP_VERSION: string = pkg.version;
