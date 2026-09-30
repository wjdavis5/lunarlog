import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  buildTaxonomy,
  serializeTaxonomy,
  tagsDartPath,
  taxonomyJsonOutPath,
} from '../scripts/generate-taxonomy.mjs';

/**
 * The generated taxonomy artifact (issue #1254) — the web day editor's
 * symptom-tag vocabulary, extracted from the app's own lib/domain/tags.dart.
 * The freshness discipline is the message catalogue's (test/messages.test.ts):
 * the builder re-runs here and a stale committed artifact fails this file.
 */
interface Taxonomy {
  categories: { name: string; wireName: string; label: string }[];
  tags: { code: string; category: string; display: string }[];
  positiveAssertionCodes: string[];
  singleSelectCategories: string[];
  minorDefaultHiddenCategories: string[];
}

const committed = JSON.parse(readFileSync(taxonomyJsonOutPath, 'utf8')) as Taxonomy;
const tagsDart = readFileSync(tagsDartPath, 'utf8');

/** Exact TagCode(...) count inside the kTagTaxonomy list literal. */
function dartTaxonomySize(source: string): number {
  const block = source.match(/const List<TagCode> kTagTaxonomy = \[([\s\S]*?)\n\];/);
  if (block === null) throw new Error('no kTagTaxonomy list found in tags.dart');
  return [...block[1].matchAll(/TagCode\(/g)].length;
}

describe('the generated tag taxonomy (issue #1254)', () => {
  it('is fresh against lib/domain/tags.dart', () => {
    expect(serializeTaxonomy(buildTaxonomy())).toBe(readFileSync(taxonomyJsonOutPath, 'utf8'));
  });

  it('carries every taxonomy code, verbatim', () => {
    expect(committed.tags.length).toBe(dartTaxonomySize(tagsDart));
    expect(committed.categories.length).toBe(31);
    const codes = committed.tags.map((t) => t.code);
    expect(new Set(codes).size).toBe(codes.length);
    for (const tag of committed.tags) {
      expect(tag.code).toMatch(/^[a-z0-9_]+$/);
      expect(tag.display.length).toBeGreaterThan(0);
    }
  });

  it('keeps the stable codes stable', () => {
    // The code-stability rule (tags.dart header): existing codes are never
    // renamed. These are the oldest strings — a rename breaks history.
    const codes = committed.tags.map((t) => t.code);
    for (const code of [
      'cramps',
      'headache',
      'back_pain',
      'breast_tenderness',
      'bloating',
      'nausea',
      'acne',
      'energetic',
      'fatigue',
      'cravings',
      'sleep_trouble',
      'irritable',
      'sad',
      'anxious',
      'calm',
      'sensitive',
    ]) {
      expect(codes).toContain(code);
    }
  });

  it('knows the positive assertions, single-select and minor-hidden rules', () => {
    expect(committed.positiveAssertionCodes).toEqual(['pain_free', 'no_sex_today', 'none']);
    expect(committed.singleSelectCategories).toEqual(['discharge']);
    expect(committed.minorDefaultHiddenCategories).toEqual(['partying', 'sex_life']);
  });

  it('maps every category to a wire name and a standard-mode label', () => {
    const byName = new Map(committed.categories.map((c) => [c.name, c]));
    expect(byName.get('sleepQuality')).toEqual({
      name: 'sleepQuality',
      wireName: 'sleep_quality',
      label: 'Sleep quality',
    });
    expect(byName.get('tests')?.label).toBe('Tests');
    for (const tag of committed.tags) {
      expect(byName.has(tag.category)).toBe(true);
    }
  });
});
