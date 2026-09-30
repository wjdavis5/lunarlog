import { z } from 'zod';

/**
 * Zod schemas at the network boundary (issue #1249): the typed
 * `Database` snapshot tells the client what the server looks like *now*;
 * these schemas validate what actually comes back before it reaches a
 * component. Objects deliberately strip unknown keys, so a migration that
 * adds a column is not a runtime failure for this client — the field is
 * picked up here when the UI needs it.
 */

/** One `profiles` row, as the client reads it. */
export const profileSchema = z.object({
  // The client-generated id is a ULID (26 Crockford base32 chars), not a
  // UUID — the scaffold's z.uuid() predated the day editor, the first code
  // path to parse a real row (issue #1254).
  id: z.string().regex(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/),
  display_name: z.string(),
  is_minor: z.boolean(),
  mode: z.string(),
  relationship: z.string().nullable(),
  birth_year: z.number().int().nullable(),
  sort_order: z.number(),
  // Issue #1254: the day editor's measurement inputs denominate in the
  // profile's own units, the same defaults the day sheet reads.
  bbt_unit: z.string(),
  weight_unit: z.string(),
  // Issue #259's synced tracking-preferences document — the day editor's
  // category visibility reads it. A jsonb column: an object, or null when
  // never customized.
  tracking_preferences: z.record(z.string(), z.unknown()).nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});

export type ProfileRow = z.infer<typeof profileSchema>;

export const profileListSchema = z.array(profileSchema);

// ---------------------------------------------------------------------------
// Day editor rows (issue #1254). The same boundary rule as `profileSchema`:
// what the server actually returns is validated before a component touches
// it, unknown keys stripped. Column sets mirror `supabase/database.types.ts`
// as of the current migration tip.
// ---------------------------------------------------------------------------

/** One live-or-tombstoned `day_entries` row, as the day editor reads it. */
export const dayEntrySchema = z.object({
  id: z.string(),
  profile_id: z.string(),
  local_date: z.string(),
  tz: z.string(),
  flow: z.string(),
  tags: z.array(z.string()),
  note: z.string().nullable(),
  note_private: z.boolean(),
  pms: z.boolean(),
  source: z.string(),
  source_id: z.string().nullable(),
  updated_at: z.string(),
  deleted_at: z.string().nullable(),
});

export type DayEntryRow = z.infer<typeof dayEntrySchema>;

/** One `observations` row — the day editor reads BBT/weight/spotting rows. */
export const observationSchema = z.object({
  id: z.string(),
  day_entry_id: z.string(),
  profile_id: z.string(),
  local_date: z.string(),
  observed_at: z.string().nullable(),
  tz: z.string(),
  category: z.string(),
  code: z.string().nullable(),
  value_num: z.number().nullable(),
  value_text: z.string().nullable(),
  unit: z.string().nullable(),
  intensity: z.number().nullable(),
  excluded: z.boolean(),
  source: z.string(),
  source_id: z.string().nullable(),
  updated_at: z.string(),
  deleted_at: z.string().nullable(),
});

export type ObservationRow = z.infer<typeof observationSchema>;

/** One `profile_modes` row (one per profile; created lazily on first write). */
export const profileModeSchema = z.object({
  profile_id: z.string(),
  mode: z.string(),
  mode_started_on: z.string().nullable(),
  estimated_due_date: z.string().nullable(),
  postpartum_birth_date: z.string().nullable(),
  birth_control_method: z.string().nullable(),
  birth_control_started_on: z.string().nullable(),
  birth_control_stopped_on: z.string().nullable(),
  health_sync_consent: z.boolean(),
  updated_at: z.string(),
});

export type ProfileModeRow = z.infer<typeof profileModeSchema>;

/** One `cycle_overrides` row — a manual cycle-boundary correction. */
export const cycleOverrideSchema = z.object({
  id: z.string(),
  profile_id: z.string(),
  cycle_start_date: z.string(),
  excluded_from_average: z.boolean(),
  manual_start: z.boolean(),
  note_id: z.string().nullable(),
  updated_at: z.string(),
  deleted_at: z.string().nullable(),
});

export type CycleOverrideRow = z.infer<typeof cycleOverrideSchema>;

/**
 * The caller's own `profile_guardians` membership for a profile — the role
 * the read-only / writable split keys on (a `viewer` or a non-accepted row
 * gets a read-only day).
 */
export const guardianMembershipSchema = z.object({
  profile_id: z.string(),
  role: z.string(),
  status: z.string(),
  is_subject: z.boolean().nullable(),
});

export type GuardianMembershipRow = z.infer<typeof guardianMembershipSchema>;

/** One live `profile_tag_registry` row — the profile's custom-tag vocabulary. */
export const customTagSchema = z.object({
  id: z.string(),
  profile_id: z.string(),
  code: z.string(),
  display_name: z.string(),
  category: z.string(),
  intensity_enabled: z.boolean(),
  hidden_at: z.string().nullable(),
});

export type CustomTagRow = z.infer<typeof customTagSchema>;
