// Type surface of scripts/generate-taxonomy.mjs for the freshness test (the
// runtime file stays plain ESM — it runs under plain `node`).
export function buildTaxonomy(
  tagsSource?: string,
  trackingPreferencesSource?: string,
  careModesSource?: string,
): {
  categories: { name: string; wireName: string; label: string }[];
  tags: { code: string; category: string; display: string }[];
  positiveAssertionCodes: string[];
  singleSelectCategories: string[];
  minorDefaultHiddenCategories: string[];
};
export function serializeTaxonomy(taxonomy: unknown): string;
export const webappRoot: string;
export const repoRoot: string;
export const tagsDartPath: string;
export const taxonomyJsonOutPath: string;
