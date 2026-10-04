import { describe, expect, it } from 'vitest';

import {
  canNavigateForward,
  dayCellSemantics,
  dayCellView,
  daysInMonth,
  defaultLayerTags,
  flowIsSpottingStyle,
  flowMarkCount,
  leadingBlanksFor,
  monthDayIsos,
  rankTagUsage,
  shiftMonth,
  toggledLayers,
  weekdayInitials,
} from '../src/lib/profiles/calendar-cells';
import type { DayEntryRow } from '../src/lib/schemas';
import type { ForecastDayCell } from '../src/domain/schemas';

/**
 * The web month calendar's pure cell math (issue #1253) — the ports of the
 * app's own grid rules (`leadingBlanksFor`, the Sunday-first week start,
 * `_flowLevelMarkCount`, `rankTagUsage`/`defaultLayerTags`, and the
 * `kMaxSymptomLayers` cap), plus the merge rule that keeps a logged day
 * factual over any forecast decoration.
 */

function entryRow(overrides: Partial<DayEntryRow> = {}): DayEntryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
    user_id: 'u1',
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    local_date: '2026-10-12',
    tz: 'UTC',
    flow: 'medium',
    tags: [],
    note: null,
    note_private: false,
    pms: false,
    source: 'manual',
    created_at: '2026-10-12T08:00:00Z',
    updated_at: '2026-10-12T08:00:00Z',
    deleted_at: null,
    server_version: 1,
    ...overrides,
  };
}

function forecastCell(overrides: Partial<ForecastDayCell> = {}): ForecastDayCell {
  return {
    predictedBleed: true,
    cycleDayNumber: null,
    pmsBadge: false,
    crampsBadge: false,
    fertileWindow: false,
    tier: 'high',
    cycleIndex: 0,
    fertileTier: null,
    fertileCycleIndex: null,
    ...overrides,
  };
}

describe('grid layout', () => {
  it('computes Sunday-first leading blanks (Dart weekday seam port)', () => {
    // 2026-10-01 is a Thursday → 4 blanks before day 1.
    expect(leadingBlanksFor(2026, 10)).toBe(4);
    // 2026-11-01 is a Sunday → no blanks.
    expect(leadingBlanksFor(2026, 11)).toBe(0);
    // 2026-08-01 is a Saturday → 6 blanks.
    expect(leadingBlanksFor(2026, 8)).toBe(6);
  });

  it('counts days and emits ISO cells day 1 first', () => {
    expect(daysInMonth(2026, 10)).toBe(31);
    expect(daysInMonth(2024, 2)).toBe(29);
    const isos = monthDayIsos(2026, 10);
    expect(isos[0]).toBe('2026-10-01');
    expect(isos[30]).toBe('2026-10-31');
  });

  it('emits Sunday-first narrow weekday initials with long names', () => {
    expect(weekdayInitials('en')).toEqual(['S', 'M', 'T', 'W', 'T', 'F', 'S']);
  });

  it('bounds forward navigation to 12 months past today, backward freely', () => {
    const today = new Date(2026, 9, 3); // October 2026
    expect(canNavigateForward(2027, 10, today)).toBe(true); // +12 allowed
    expect(canNavigateForward(2027, 11, today)).toBe(false); // +13 refused
    expect(canNavigateForward(2000, 1, today)).toBe(true); // backward free
  });

  it('shifts months across the year boundary both ways', () => {
    expect(shiftMonth(2026, 1, -1)).toEqual({ year: 2025, month: 12 });
    expect(shiftMonth(2026, 12, 1)).toEqual({ year: 2027, month: 1 });
    expect(shiftMonth(2026, 10, -14)).toEqual({ year: 2025, month: 8 });
  });
});

describe('flow marks (the app mark-count port)', () => {
  it('climbs 1 to 5 by level', () => {
    expect(flowMarkCount('none')).toBe(1);
    expect(flowMarkCount('spotting')).toBe(1);
    expect(flowMarkCount('not_bleeding')).toBe(1);
    expect(flowMarkCount('light')).toBe(2);
    expect(flowMarkCount('medium')).toBe(3);
    expect(flowMarkCount('heavy')).toBe(4);
    expect(flowMarkCount('super_heavy')).toBe(5);
  });

  it('renders spotting-style levels as the single ring', () => {
    expect(flowIsSpottingStyle('none')).toBe(true);
    expect(flowIsSpottingStyle('spotting')).toBe(true);
    expect(flowIsSpottingStyle('not_bleeding')).toBe(true);
    expect(flowIsSpottingStyle('heavy')).toBe(false);
  });
});

describe('symptom layers (the symptom_layers.dart port)', () => {
  it('ranks most-used first with taxonomy-order tie-breaks', () => {
    const ranked = rankTagUsage([
      entryRow({ tags: ['cramps'] }),
      entryRow({ tags: ['headache'] }),
      entryRow({ tags: ['cramps'] }),
      entryRow({ tags: ['headache'] }),
      entryRow({ tags: ['cramps', 'headache', 'acne'] }),
    ]);
    expect(ranked.slice(0, 2).map((usage) => usage.code)).toEqual(['cramps', 'headache']);
  });

  it('skips tombstones and positive-assertion codes', () => {
    const ranked = rankTagUsage([
      entryRow({ tags: ['pain_free'] }),
      entryRow({ deleted_at: '2026-10-13T00:00:00Z', tags: ['cramps'] }),
    ]);
    expect(ranked).toEqual([]);
  });

  it('caps the default selection at three layers', () => {
    const entries = [entryRow({ local_date: '2026-10-01', tags: ['a', 'b', 'c', 'd'] })];
    const tags = defaultLayerTags(entries);
    expect(tags.length).toBeLessThanOrEqual(3);
  });

  it('refuses a fourth layer with the cap and allows removals', () => {
    expect(toggledLayers(['a', 'b', 'c'], 'd')).toBeNull();
    expect(toggledLayers(['a', 'b'], 'c')).toEqual(['a', 'b', 'c']);
    expect(toggledLayers(['a', 'b', 'c'], 'b')).toEqual(['a', 'c']);
  });
});

describe('dayCellView', () => {
  const todayIso = '2026-10-03';

  it('merges the logged entry and the forecast decoration', () => {
    const cell = dayCellView({
      iso: '2026-10-12',
      todayIso,
      entryByIso: new Map([['2026-10-12', entryRow({ flow: 'heavy', tags: ['cramps'] })]]),
      forecastByIso: new Map([['2026-10-12', forecastCell({ predictedBleed: true })]]),
      activeLayers: ['cramps'],
    });
    expect(cell.dayNumber).toBe(12);
    expect(cell.entry?.flow).toBe('heavy');
    expect(cell.flowMarkCount).toBe(4);
    expect(cell.layerHits).toEqual(['cramps']);
  });

  it('keeps the past factual: no forecast cell before today', () => {
    const cell = dayCellView({
      iso: '2026-10-01',
      todayIso,
      entryByIso: new Map(),
      forecastByIso: new Map([['2026-10-01', forecastCell()]]),
      activeLayers: [],
    });
    expect(cell.forecast).toBeNull();
  });

  it('a logged day suppresses its own forecast decoration', () => {
    const cell = dayCellView({
      iso: '2026-10-12',
      todayIso,
      entryByIso: new Map([['2026-10-12', entryRow()]]),
      forecastByIso: new Map([['2026-10-12', forecastCell()]]),
      activeLayers: [],
    });
    expect(cell.forecast).toBeNull();
  });

  it('labels the estimate fragments for the screen reader', () => {
    const cell = dayCellView({
      iso: '2026-10-12',
      todayIso,
      entryByIso: new Map(),
      forecastByIso: new Map([
        [
          '2026-10-12',
          forecastCell({ cycleDayNumber: 10, pmsBadge: true, fertileWindow: true }),
        ],
      ]),
      activeLayers: [],
    });
    expect(dayCellSemantics(cell)).toEqual({
      estimated: true,
      cycleDayNumber: 10,
      pms: true,
      cramps: false,
      fertile: true,
    });
  });
});
