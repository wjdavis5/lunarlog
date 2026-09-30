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
  id: z.uuid(),
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
