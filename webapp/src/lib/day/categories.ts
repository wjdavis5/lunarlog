/**
 * The day editor's category surfacing (issue #1254): which taxonomy
 * categories the symptom picker shows, and in what order — a faithful port
 * of the app's `resolveTrackingCategories` read path (issue #259's synced
 * `profiles.tracking_preferences` document over the care-mode default).
 *
 * A stored preference always wins; a category the document never mentions
 * resolves to its default — enabled for everyone except the
 * minor-visibility set (`partying`, `sex_life`), which default to disabled
 * on an `is_minor` profile. Hiding is presentation only: already-logged
 * tags keep round-tripping untouched.
 */

import taxonomyJson from '../taxonomy/taxonomy.generated.json';
import type { ProfileRow } from '../schemas';

interface TaxonomyTag {
  code: string;
  category: string;
  display: string;
}

interface TaxonomyCategory {
  name: string;
  wireName: string;
  label: string;
}

interface TaxonomyFile {
  categories: TaxonomyCategory[];
  tags: TaxonomyTag[];
  positiveAssertionCodes: string[];
  singleSelectCategories: string[];
  minorDefaultHiddenCategories: string[];
}

/** The generated taxonomy (see scripts/generate-taxonomy.mjs). */
export const taxonomy = taxonomyJson as unknown as TaxonomyFile;

/** The taxonomy's tags grouped by category, in category order. */
export function tagsByCategory(): Map<string, TaxonomyTag[]> {
  const grouped = new Map<string, TaxonomyTag[]>();
  for (const category of taxonomy.categories) {
    grouped.set(
      category.name,
      taxonomy.tags.filter((tag) => tag.category === category.name),
    );
  }
  return grouped;
}

export function categoryByWireName(wireName: string): TaxonomyCategory | undefined {
  return taxonomy.categories.find((category) => category.wireName === wireName);
}

export function isSingleSelectCategory(categoryName: string): boolean {
  const category = taxonomy.categories.find((c) => c.name === categoryName);
  return category !== undefined && taxonomy.singleSelectCategories.includes(category.wireName);
}

export function isPositiveAssertion(code: string): boolean {
  return taxonomy.positiveAssertionCodes.includes(code);
}

/** One parsed `tracking_preferences` entry (#259's stored shape). */
interface StoredPreference {
  enabled: boolean;
  sort_order: number;
}

function parsePreferences(profile: ProfileRow): Record<string, StoredPreference> {
  const parsed = profile.tracking_preferences;
  if (parsed === null || parsed === undefined) return {};
  if (typeof parsed !== 'object' || Array.isArray(parsed)) return {};
  const out: Record<string, StoredPreference> = {};
  for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
    if (value === null || typeof value !== 'object') continue;
    const entry = value as Record<string, unknown>;
    if (typeof entry['enabled'] !== 'boolean') continue;
    out[key] = {
      enabled: entry['enabled'],
      sort_order: typeof entry['sort_order'] === 'number' ? (entry['sort_order'] as number) : 0,
    };
  }
  return out;
}

export interface SurfacedCategory {
  name: string;
  wireName: string;
  label: string;
}

/**
 * The enabled categories, curated-first (ascending `sort_order`, taxonomy
 * order within ties), then the never-mentioned ones in taxonomy order.
 */
export function resolveDayCategories(profile: ProfileRow): SurfacedCategory[] {
  const prefs = parsePreferences(profile);
  const minorHidden = profile.is_minor ? taxonomy.minorDefaultHiddenCategories : [];
  const customized: { category: TaxonomyCategory; sortOrder: number; index: number }[] = [];
  const defaulted: { category: TaxonomyCategory; index: number }[] = [];
  taxonomy.categories.forEach((category, index) => {
    const stored = prefs[category.wireName];
    const enabled =
      stored !== undefined ? stored.enabled : !minorHidden.includes(category.wireName);
    if (!enabled) return;
    if (stored !== undefined) {
      customized.push({ category, sortOrder: stored.sort_order, index });
    } else {
      defaulted.push({ category, index });
    }
  });
  customized.sort((a, b) => a.sortOrder - b.sortOrder || a.index - b.index);
  return [
    ...customized.map((entry) => entry.category),
    ...defaulted.map((entry) => entry.category),
  ].map((category) => ({
    name: category.name,
    wireName: category.wireName,
    label: category.label,
  }));
}

/**
 * The categories the symptom picker draws: every surfaced category that has
 * at least one tag to pick, in order. Several taxonomy categories carry no
 * tags yet (Sleep quality, Urine, Meditation and others); drawn as a bare
 * heading they read as a broken page. `tests` is excluded because it has a
 * fieldset of its own (issue #1291).
 */
export function symptomPickerCategories(
  surfaced: SurfacedCategory[],
  grouped: Map<string, TaxonomyTag[]> = tagsByCategory(),
): { category: SurfacedCategory; tags: TaxonomyTag[] }[] {
  return surfaced
    .filter((category) => category.name !== 'tests')
    .map((category) => ({ category, tags: grouped.get(category.name) ?? [] }))
    .filter((entry) => entry.tags.length > 0);
}
