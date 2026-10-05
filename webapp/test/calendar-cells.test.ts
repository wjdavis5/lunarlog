import { describe, expect, it } from 'vitest';

import {
  canNavigateForward,
  dayCellSemantics,
  dayCellView,
  daysInMonth,
  defaultLayerTags,
  flowFillClass,
  flowIsBleed,
  flowMarkCount,
  forecastCellForMode,
  leadingBlanksFor,
  monthHasContent,
  monthDayIsos,
  rankTagUsage,
  shiftMonth,
  spottingIsosFor,
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

  it('fills a bleed day with its flow colour, super heavy sharing heavy', () => {
    expect(flowFillClass('light')).toBe('cal-flow-light');
    expect(flowFillClass('medium')).toBe('cal-flow-medium');
    expect(flowFillClass('heavy')).toBe('cal-flow-heavy');
    expect(flowFillClass('super_heavy')).toBe('cal-flow-heavy');
  });

  it('fills nothing that is not a bleed', () => {
    for (const flow of ['none', 'spotting', 'not_bleeding', 'unknown_level']) {
      expect(flowFillClass(flow)).toBeNull();
    }
  });

  it('fills exactly the levels the isBleed port counts as a bleed', () => {
    for (const flow of [
      'none',
      'spotting',
      'not_bleeding',
      'light',
      'medium',
      'heavy',
      'super_heavy',
    ]) {
      expect(flowFillClass(flow) !== null).toBe(flowIsBleed(flow));
    }
  });

  it('counts only the four bleed levels as a bleed (the isBleed port)', () => {
    for (const flow of ['light', 'medium', 'heavy', 'super_heavy']) {
      expect(flowIsBleed(flow)).toBe(true);
    }
    for (const flow of ['none', 'not_bleeding', 'spotting', 'unrecognised']) {
      expect(flowIsBleed(flow)).toBe(false);
    }
  });
});

// Issue #1391: the spotting ring is drawn from recorded spotting, never
// inferred from a non-bleed flow level.
describe('spottingIsosFor', () => {
  const PROFILE = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
  const observation = (
    overrides: Partial<{
      profile_id: string;
      local_date: string;
      category: string | null;
      deleted_at: string | null;
    }> = {},
  ) => ({
    profile_id: PROFILE,
    local_date: '2026-10-05',
    category: 'spotting',
    deleted_at: null,
    ...overrides,
  });

  it('collects the dates of live spotting observations for the profile', () => {
    const isos = spottingIsosFor(
      [],
      [
        observation(),
        observation({ local_date: '2026-10-06', deleted_at: '2026-10-07T00:00:00Z' }),
        observation({ local_date: '2026-10-08', category: 'bbt' }),
        observation({ local_date: '2026-10-09', profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2YA' }),
      ],
      PROFILE,
    );
    expect([...isos]).toEqual(['2026-10-05']);
  });

  it('counts a legacy spotting flow row as recorded spotting', () => {
    const isos = spottingIsosFor(
      [
        entryRow({ local_date: '2026-10-02', flow: 'spotting' }),
        entryRow({ local_date: '2026-10-03', flow: 'none' }),
        entryRow({ local_date: '2026-10-04', flow: 'not_bleeding' }),
      ],
      [],
      PROFILE,
    );
    expect([...isos]).toEqual(['2026-10-02']);
  });
});

// Issue #1390: the app strips the fertile flag once, before any rendering.
describe('forecastCellForMode (the _cellForMode port)', () => {
  it('passes every cell through while the fertile window is shown', () => {
    const cell = forecastCell({ predictedBleed: false, fertileWindow: true });
    expect(forecastCellForMode(cell, true)).toBe(cell);
    expect(forecastCellForMode(null, true)).toBeNull();
  });

  it('leaves a cell with no fertile flag untouched when the window is hidden', () => {
    const cell = forecastCell({ predictedBleed: true });
    expect(forecastCellForMode(cell, false)).toBe(cell);
  });

  it('strips the fertile flag but keeps the rest of a mixed cell', () => {
    const cell = forecastCell({ predictedBleed: false, pmsBadge: true, fertileWindow: true });
    expect(forecastCellForMode(cell, false)).toEqual({ ...cell, fertileWindow: false });
  });

  it('turns a fertile-only cell into no forecast at all', () => {
    const cell = forecastCell({ predictedBleed: false, fertileWindow: true });
    expect(forecastCellForMode(cell, false)).toBeNull();
  });

  it('keeps a hidden fertile day that carries a cycle-day numeral', () => {
    const cell = forecastCell({
      predictedBleed: false,
      cycleDayNumber: 14,
      fertileWindow: true,
    });
    expect(forecastCellForMode(cell, false)?.cycleDayNumber).toBe(14);
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
      spottingIsos: new Set(),
      showsFertileWindow: true,
      activeLayers: ['cramps'],
    });
    expect(cell.dayNumber).toBe(12);
    expect(cell.entry?.flow).toBe('heavy');
    expect(cell.flowMarkCount).toBe(4);
    expect(cell.layerHits).toEqual(['cramps']);
  });

  // Issue #1476.
  it('carries the setup mark on the named day only, and never over a logged day', () => {
    const view = (iso: string, entries: Map<string, DayEntryRow>, mark: string | null) =>
      dayCellView({
        iso,
        todayIso,
        entryByIso: entries,
        forecastByIso: new Map(),
        spottingIsos: new Set(),
        showsFertileWindow: true,
        activeLayers: [],
        setupPeriodMarkIso: mark,
      });
    expect(view('2026-10-01', new Map(), '2026-10-01').setupPeriodMark).toBe(true);
    expect(view('2026-10-02', new Map(), '2026-10-01').setupPeriodMark).toBe(false);
    expect(view('2026-10-01', new Map(), null).setupPeriodMark).toBe(false);
    expect(
      view('2026-10-01', new Map([['2026-10-01', entryRow({ flow: 'none' })]]), '2026-10-01')
        .setupPeriodMark,
    ).toBe(false);
    // Left out altogether, as by a caller that has no domain answer yet.
    expect(
      dayCellView({
        iso: '2026-10-01',
        todayIso,
        entryByIso: new Map(),
        forecastByIso: new Map(),
        spottingIsos: new Set(),
        showsFertileWindow: true,
        activeLayers: [],
      }).setupPeriodMark,
    ).toBe(false);
  });

  it('counts the setup mark as content for its month, and for no other', () => {
    const october = ['2026-10-01', '2026-10-02'];
    const september = ['2026-09-29', '2026-09-30'];
    const none = new Map<string, DayEntryRow>();
    expect(monthHasContent({ days: october, entryByIso: none, setupPeriodMarkIso: null })).toBe(
      false,
    );
    expect(
      monthHasContent({ days: october, entryByIso: none, setupPeriodMarkIso: '2026-10-01' }),
    ).toBe(true);
    expect(
      monthHasContent({ days: september, entryByIso: none, setupPeriodMarkIso: '2026-10-01' }),
    ).toBe(false);
    expect(
      monthHasContent({
        days: september,
        entryByIso: new Map([['2026-09-30', entryRow()]]),
        setupPeriodMarkIso: null,
      }),
    ).toBe(true);
  });

  it('keeps the past factual: no forecast cell before today', () => {
    const cell = dayCellView({
      iso: '2026-10-01',
      todayIso,
      entryByIso: new Map(),
      forecastByIso: new Map([['2026-10-01', forecastCell()]]),
      spottingIsos: new Set(),
      showsFertileWindow: true,
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
      spottingIsos: new Set(),
      showsFertileWindow: true,
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
      spottingIsos: new Set(),
      showsFertileWindow: true,
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

  // Issue #1391: a symptom-only day used to carry the spotting ring.
  it('draws no flow mark for a day logged as none or not bleeding', () => {
    for (const flow of ['none', 'not_bleeding']) {
      const cell = dayCellView({
        iso: '2026-10-02',
        todayIso,
        entryByIso: new Map([['2026-10-02', entryRow({ flow, tags: ['cramps'] })]]),
        forecastByIso: new Map(),
        spottingIsos: new Set(),
        showsFertileWindow: true,
        activeLayers: [],
      });
      expect(cell.spottingStyle).toBe(false);
      expect(cell.flowMarkCount).toBe(0);
    }
  });

  it('rings a non-bleed day only when spotting was recorded for it', () => {
    const cell = dayCellView({
      iso: '2026-10-02',
      todayIso,
      entryByIso: new Map([['2026-10-02', entryRow({ flow: 'not_bleeding' })]]),
      forecastByIso: new Map(),
      spottingIsos: new Set(['2026-10-02']),
      showsFertileWindow: true,
      activeLayers: [],
    });
    expect(cell.spottingStyle).toBe(true);
    expect(cell.flowMarkCount).toBe(0);
  });

  it('shows the bleed marks, never the ring, when a bleed day also has spotting', () => {
    const cell = dayCellView({
      iso: '2026-10-02',
      todayIso,
      entryByIso: new Map([['2026-10-02', entryRow({ flow: 'light' })]]),
      forecastByIso: new Map(),
      spottingIsos: new Set(['2026-10-02']),
      showsFertileWindow: true,
      activeLayers: [],
    });
    expect(cell.spottingStyle).toBe(false);
    expect(cell.flowMarkCount).toBe(2);
  });

  it('never rings a day with no logged entry', () => {
    const cell = dayCellView({
      iso: '2026-10-02',
      todayIso,
      entryByIso: new Map(),
      forecastByIso: new Map(),
      spottingIsos: new Set(['2026-10-02']),
      showsFertileWindow: true,
      activeLayers: [],
    });
    expect(cell.spottingStyle).toBe(false);
  });

  // Issue #1390: the hidden fertile window reaches neither the band nor
  // the screen-reader label.
  it('hides the fertile window from the cell and its label when the framing hides it', () => {
    const forecastByIso = new Map([
      ['2026-10-12', forecastCell({ predictedBleed: false, fertileWindow: true })],
      ['2026-10-13', forecastCell({ predictedBleed: true, fertileWindow: true })],
    ]);
    const view = (iso: string) =>
      dayCellView({
        iso,
        todayIso,
        entryByIso: new Map(),
        forecastByIso,
        spottingIsos: new Set(),
        showsFertileWindow: false,
        activeLayers: [],
      });
    expect(view('2026-10-12').forecast).toBeNull();
    expect(dayCellSemantics(view('2026-10-12')).estimated).toBe(false);
    expect(view('2026-10-13').forecast?.fertileWindow).toBe(false);
    expect(dayCellSemantics(view('2026-10-13'))).toMatchObject({
      estimated: true,
      fertile: false,
    });
  });
});
