import { z } from 'zod';

/**
 * Zod schemas at the network boundary (issue #1249): the typed
 * `Database` snapshot tells the client what the server looks like *now*;
 * these schemas validate what actually comes back before it reaches a
 * component. Objects deliberately strip unknown keys, so a migration that
 * adds a column is not a runtime failure for this client — the field is
 * picked up here when the UI needs it.
 */

/**
 * A profile/content id as the server stores it: a 26-character Crockford
 * base32 ULID (`profiles_id_ulid_check` and friends — issue #1255 found the
 * scaffold validating these as UUIDs, which every real row fails).
 */
export const ulidSchema = z.ulid();

/** One `profiles` row, as the client reads it. */
export const profileSchema = z.object({
  id: ulidSchema,
  display_name: z.string(),
  is_minor: z.boolean(),
  mode: z.string(),
  relationship: z.string().nullable(),
  birth_year: z.number().int().nullable(),
  sort_order: z.number(),
  created_at: z.string(),
  updated_at: z.string(),
});

export type ProfileRow = z.infer<typeof profileSchema>;

export const profileListSchema = z.array(profileSchema);

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
