import { describe, expect, it } from 'vitest';

import { bbtObservationRows } from '../src/lib/profiles/bbt-inputs';
import type { ObservationRow } from '../src/lib/schemas';

/**
 * The BBT chart's request mapping (issue #1796): the synced measurement rows
 * onto the `bbtChart` shape. Rows without a category are dropped; the
 * exclusion flag and the tombstone cross the boundary so the chart itself
 * decides what to plot.
 */

function row(overrides: Partial<ObservationRow> = {}): ObservationRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    day_entry_id: '01M2FWKNG0ZMH2ANCH7R2CM2XA',
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XB',
    local_date: '2026-09-01',
    tz: 'UTC',
    observed_at: null,
    category: 'bbt',
    code: null,
    value_num: 36.4,
    value_text: null,
    unit: 'celsius',
    intensity: null,
    excluded: false,
    source: 'manual',
    source_id: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
    ...overrides,
  };
}

describe('bbtObservationRows (issue #1796)', () => {
  it('maps a row onto the request shape', () => {
    expect(bbtObservationRows([row()])).toEqual([
      {
        dayEntryId: '01M2FWKNG0ZMH2ANCH7R2CM2XA',
        category: 'bbt',
        valueNum: 36.4,
        unit: 'celsius',
        source: 'manual',
        excluded: false,
        deletedAt: null,
        updatedAt: '2026-09-01T00:00:00Z',
      },
    ]);
  });

  it('drops rows without a category', () => {
    expect(bbtObservationRows([row({ category: null })])).toEqual([]);
  });

  it('carries the exclusion flag and the tombstone through', () => {
    const mapped = bbtObservationRows([
      row({ excluded: true, deleted_at: '2026-09-02T00:00:00Z' }),
    ]);
    expect(mapped[0]?.excluded).toBe(true);
    expect(mapped[0]?.deletedAt).toBe('2026-09-02T00:00:00Z');
  });

  // Issue #1821: one date can carry two live rows, and the chart breaks
  // that tie by updatedAt - so each row's own instant must cross the
  // boundary, not be borrowed from its day entry.
  it("carries each row's own update instant", () => {
    const mapped = bbtObservationRows([
      row({ updated_at: '2026-09-02T00:00:00Z' }),
      row({ updated_at: '2026-09-03T00:00:00Z' }),
    ]);
    expect(mapped.map((entry) => entry.updatedAt)).toEqual([
      '2026-09-02T00:00:00Z',
      '2026-09-03T00:00:00Z',
    ]);
  });
});
