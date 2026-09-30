import { z } from 'zod';

import { ULID_PATTERN } from './ulid';

/**
 * Zod schemas at the network boundary (issue #1249): the typed
 * `Database` snapshot tells the client what the server looks like *now*;
 * these schemas validate what actually comes back before it reaches a
 * component. Objects deliberately strip unknown keys, so a migration that
 * adds a column is not a runtime failure for this client — the field is
 * picked up here when the UI needs it.
 *
 * Issue #1252 extends the catalogue to every synced table the data layer
 * reads (`sync_pull`'s eleven keys plus `guardian_notes` and `settings`,
 * which ride direct RLS-scoped selects) and pins the push-payload shapes
 * the server accepts — the same shapes `sync_push`'s derived key
 * allowlists admit and `supabase/tests/seed_sync_push_sample_test.sql`
 * replays against the live RPC.
 */

/**
 * Every synced row id is a ULID, not a UUID — the server's own
 * `*_id_ulid_check` constraints and `sync_push`'s payload validation
 * (20260903014208, `c_ulid`) define the shape. The scaffold briefly used
 * `z.uuid()` here; every real server row fails that parse, so issue
 * #1252 aligns the boundary with the server's actual id format.
 */
const ulidId = z.string().regex(ULID_PATTERN, 'not a ULID');

/** An ISO-8601 timestamp as timestamptz renders over PostgREST JSON. */
const timestamp = z.string();

// ---------------------------------------------------------------------------
// Row schemas — one per synced table, in sync_pull's own key order.
// ---------------------------------------------------------------------------

/** One `profiles` row, as the client reads it. */
export const profileSchema = z.object({
  id: ulidId,
  user_id: z.string(),
export const ulidSchema = ulidId;
  display_name: z.string(),
  is_minor: z.boolean(),
  sort_order: z.number(),
  archived_at: timestamp.nullable(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
  mode: z.string(),
  irregular_framing: z.boolean().nullable().optional(),
  birth_year: z.number().int().nullable(),
  relationship: z.string().nullable(),
  last_period_start: z.string().nullable().optional(),
  typical_cycle_length_days: z.number().int().nullable().optional(),
  typical_period_length_days: z.number().int().nullable().optional(),
  bbt_unit: z.string().optional(),
  weight_unit: z.string().optional(),
  tracking_preferences: z.unknown().nullable().optional(),
});

export type ProfileRow = z.infer<typeof profileSchema>;

export const profileListSchema = z.array(profileSchema);

/** One `day_entries` row. A private note arrives masked (note = null) for
 * every non-subject guardian — masking is the server's job (sync_pull), so
 * the client schema just carries the nullable field. */
export const dayEntrySchema = z.object({
  id: ulidId,
  user_id: z.string(),
  profile_id: ulidId,
  local_date: z.string(),
  tz: z.string(),
  flow: z.string(),
  tags: z.array(z.string()),
  note: z.string().nullable(),
  note_private: z.boolean(),
  pms: z.boolean(),
  source: z.string(),
  source_id: z.string().nullable().optional(),
  import_id: z.string().nullable().optional(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type DayEntryRow = z.infer<typeof dayEntrySchema>;

export const dayEntryListSchema = z.array(dayEntrySchema);

/** One `observations` row. */
export const observationSchema = z.object({
  id: ulidId,
  day_entry_id: ulidId,
  profile_id: ulidId,
  local_date: z.string(),
  tz: z.string(),
  observed_at: timestamp.nullable(),
  category: z.string().nullable(),
  code: z.string().nullable(),
  value_num: z.number().nullable(),
  value_text: z.string().nullable(),
  unit: z.string().nullable(),
  intensity: z.number().int().nullable(),
  excluded: z.boolean(),
  source: z.string(),
  source_id: z.string().nullable().optional(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type ObservationRow = z.infer<typeof observationSchema>;

export const observationListSchema = z.array(observationSchema);

/** One `profile_modes` row — keyed by profile_id, no id of its own. */
export const profileModeSchema = z.object({
  profile_id: ulidId,
  mode: z.string(),
  mode_started_on: z.string().nullable(),
  estimated_due_date: z.string().nullable().optional(),
  postpartum_birth_date: z.string().nullable().optional(),
  birth_control_method: z.string().nullable().optional(),
  birth_control_started_on: z.string().nullable().optional(),
  birth_control_stopped_on: z.string().nullable().optional(),
  health_sync_consent: z.boolean(),
  updated_at: timestamp,
  server_version: z.number(),
});

export type ProfileModeRow = z.infer<typeof profileModeSchema>;

export const profileModeListSchema = z.array(profileModeSchema);

/** One `cycle_overrides` row. */
export const cycleOverrideSchema = z.object({
  id: ulidId,
  profile_id: ulidId,
  cycle_start_date: z.string(),
  excluded_from_average: z.boolean(),
  manual_start: z.boolean(),
  note_id: z.string().nullable().optional(),
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type CycleOverrideRow = z.infer<typeof cycleOverrideSchema>;

export const cycleOverrideListSchema = z.array(cycleOverrideSchema);

/** One `care_notes` row. */
export const careNoteSchema = z.object({
  id: ulidId,
  profile_id: ulidId,
  body: z.string(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type CareNoteRow = z.infer<typeof careNoteSchema>;

export const careNoteListSchema = z.array(careNoteSchema);

/** One `visit_prep_items` row. */
export const visitPrepItemSchema = z.object({
  id: ulidId,
  profile_id: ulidId,
  body: z.string(),
  kind: z.string(),
  is_checked: z.boolean(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type VisitPrepItemRow = z.infer<typeof visitPrepItemSchema>;

export const visitPrepItemListSchema = z.array(visitPrepItemSchema);

/** One `guardian_notes` row (dated, author-scoped; issue #801). */
export const guardianNoteSchema = z.object({
  id: ulidId,
  profile_id: ulidId,
  local_date: z.string(),
  tz: z.string(),
  body: z.string(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type GuardianNoteRow = z.infer<typeof guardianNoteSchema>;

export const guardianNoteListSchema = z.array(guardianNoteSchema);

/** One `profile_guardians` row — the one synced row whose id is a UUID
 * (gen_random_uuid, 20260904010000), not a ULID. */
export const profileGuardianSchema = z.object({
  id: z.uuid(),
  profile_id: ulidId,
  user_id: z.string(),
  role: z.string(),
  status: z.string(),
  display_name: z.string().nullable().optional(),
  invited_by: z.string().nullable().optional(),
  is_subject: z.boolean().nullable().optional(),
  revoked_at: z.string().nullable().optional(),
  created_at: timestamp,
  updated_at: timestamp,
  server_version: z.number(),
});

export type ProfileGuardianRow = z.infer<typeof profileGuardianSchema>;

export const profileGuardianListSchema = z.array(profileGuardianSchema);

/** One `profile_tag_registry` row (the per-profile custom tags, #257). */
export const profileTagRegistrySchema = z.object({
  id: ulidId,
  profile_id: ulidId,
  code: z.string(),
  display_name: z.string(),
  category: z.string(),
  intensity_enabled: z.boolean(),
  sort_order: z.number().nullable().optional(),
  hidden_at: z.string().nullable().optional(),
  created_at: timestamp,
  updated_at: timestamp,
  deleted_at: timestamp.nullable(),
  server_version: z.number(),
});

export type ProfileTagRegistryRow = z.infer<typeof profileTagRegistrySchema>;

export const profileTagRegistryListSchema = z.array(profileTagRegistrySchema);

/** One per-user `settings` row (direct RLS-scoped select; not in sync_pull). */
export const settingSchema = z.object({
  user_id: z.string(),
  key: z.string(),
  value: z.string(),
  updated_at: timestamp,
  server_version: z.number(),
});

export type SettingRow = z.infer<typeof settingSchema>;

export const settingListSchema = z.array(settingSchema);

/**
 * One wake signal from `public.sync_signals` — the only table the Realtime
 * publication carries (20260905100000). Content-free by construction:
 * which profile changed and when, nothing else (KTD2).
 */
export const syncSignalSchema = z.object({
  profile_id: z.string(),
  updated_at: timestamp,
});

export type SyncSignalRow = z.infer<typeof syncSignalSchema>;

// ---------------------------------------------------------------------------
// RPC boundary shapes.
// ---------------------------------------------------------------------------

/**
 * `sync_pull(p_cursors)`'s response: one array per covered table. Every
 * key is required in practice (the RPC always builds all of them), but a
 * server predating a key's migration would omit it — `.optional()` keeps
 * the parse a migration behind from failing the whole pull.
 */
export const syncPullResponseSchema = z.object({
  profiles: profileListSchema.optional(),
  day_entries: dayEntryListSchema.optional(),
  observations: observationListSchema.optional(),
  profile_modes: profileModeListSchema.optional(),
  cycle_overrides: cycleOverrideListSchema.optional(),
  care_notes: careNoteListSchema.optional(),
  visit_prep_items: visitPrepItemListSchema.optional(),
  day_entry_merge_events: z.array(z.record(z.string(), z.unknown())).optional(),
  profile_tag_registry: profileTagRegistryListSchema.optional(),
  day_entry_history: z.array(z.record(z.string(), z.unknown())).optional(),
  profile_guardians: profileGuardianListSchema.optional(),
});

/**
 * `sync_push`'s result: `{ resolved, rejected, server_now }` — the exact
 * keys the Dart client's transport decodes (supabase_sync_transport.dart).
 * `resolved` rows come back as the stored row plus a `table` discriminator;
 * `rejected` entries echo the payload row's `id` — the web layer maps those
 * ids back onto the offending payload row so a rejection surfaces at the
 * field/row that caused it.
 */
export const syncPushResultSchema = z.object({
  resolved: z.array(z.record(z.string(), z.unknown())),
  rejected: z.array(z.object({ id: z.string().nullable(), rejected: z.literal(true) })),
  server_now: timestamp,
});

export type SyncPushResult = z.infer<typeof syncPushResultSchema>;

/**
 * Whether the subject-invite preset ("her own profile", issue #802) may be
 * offered for `profile` — the web mirror of `Profile.subjectInviteAvailableAt`
 * (`lib/domain/models/profile.dart`): the relationship is daughter/son/child,
 * or the profile counts as a minor today. The server re-checks the pairing.
 */
export function subjectInviteAvailable(profile: ProfileRow, today: Date = new Date()): boolean {
  if (
    profile.relationship === 'daughter' ||
    profile.relationship === 'son' ||
    profile.relationship === 'child'
  ) {
    return true;
  }
  // `deriveMinorStatus`: a birth year decides, the stored flag is the
  // fallback — and "minor" means at most 18 this calendar year.
  if (profile.birth_year !== null) return today.getUTCFullYear() - profile.birth_year <= 18;
  return profile.is_minor;
}
