import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  symptomPickerCategories,
  tagsByCategory,
  taxonomy,
  type SurfacedCategory,
} from '../src/lib/day/categories';

/**
 * Two properties of the day form found by looking at it: it drew a heading
 * for every category, including the ones with no tags under them, and its
 * Save button sat at the bottom of a form several screens long.
 */

const everyCategory: SurfacedCategory[] = taxonomy.categories.map((category) => ({
  name: category.name,
  wireName: category.wireName,
  label: category.label,
}));

describe('symptomPickerCategories', () => {
  const grouped = tagsByCategory();
  const drawn = symptomPickerCategories(everyCategory);

  it('the taxonomy really does contain categories with no tags', () => {
    // If this stops being true the rule below has nothing to do, and this
    // test should say so rather than pass silently.
    const empty = everyCategory.filter((category) => !grouped.get(category.name)?.length);
    expect(empty.length).toBeGreaterThan(0);
  });

  it('draws no category that has nothing to pick', () => {
    expect(drawn.length).toBeGreaterThan(5);
    for (const entry of drawn) {
      expect(entry.tags.length, entry.category.label).toBeGreaterThan(0);
    }
    const drawnNames = new Set(drawn.map((entry) => entry.category.name));
    for (const category of everyCategory) {
      if (!grouped.get(category.name)?.length) {
        expect(drawnNames.has(category.name), category.label).toBe(false);
      }
    }
  });

  it('keeps every category that has tags, in the order it was given', () => {
    const expected = everyCategory
      .filter((category) => category.name !== 'tests')
      .filter((category) => (grouped.get(category.name)?.length ?? 0) > 0)
      .map((category) => category.name);
    expect(drawn.map((entry) => entry.category.name)).toEqual(expected);
  });

  it('leaves `tests` to its own fieldset', () => {
    expect(grouped.get('tests')?.length ?? 0).toBeGreaterThan(0);
    expect(drawn.some((entry) => entry.category.name === 'tests')).toBe(false);
  });

  it('hands back the tags it found, so the page does not look them up twice', () => {
    const pain = drawn.find((entry) => entry.category.name === 'pain');
    expect(pain?.tags).toEqual(grouped.get('pain'));
  });

  it('draws nothing for a profile with no categories surfaced', () => {
    expect(symptomPickerCategories([])).toEqual([]);
  });
});

describe('the Save row', () => {
  const css = readFileSync(
    join(import.meta.dirname, '..', 'src', 'styles', 'global.css'),
    'utf8',
  ).replaceAll('\r\n', '\n');

  const rule = /\.day-actions \{([^}]*)\}/.exec(css)?.[1] ?? '';

  it('stays pinned to the bottom of the window while the form scrolls', () => {
    expect(rule).toContain('position: sticky');
    expect(rule).toMatch(/bottom:\s*var\(--ll-space-\d\)/);
  });

  it('is opaque, so the form does not show through it', () => {
    expect(rule).toMatch(/background:\s*var\(--ll-surface-container/);
  });

  it('leaves keyboard focus room above it', () => {
    // Without scroll padding the browser can scroll a focused control to
    // rest underneath a pinned row.
    expect(css).toMatch(/html \{[^}]*scroll-padding-bottom:/);
  });
});
