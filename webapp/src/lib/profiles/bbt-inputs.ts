import type { BbtObservationJson } from '../../domain/client';
import type { ObservationRow } from '../schemas';

/**
 * The BBT chart's observation rows (issue #1796): the profile's synced
 * measurement rows mapped onto the `bbtChart` request shape. Rows without a
 * category are dropped here (the facade skips them too); everything else -
 * deleted rows, excluded rows, other categories, each row's own update
 * instant (issue #1821) - crosses the boundary and is skipped (or resolved)
 * by the chart itself, so the two sides never disagree about what is
 * plotted.
 */
export function bbtObservationRows(rows: ObservationRow[]): BbtObservationJson[] {
  const mapped: BbtObservationJson[] = [];
  for (const row of rows) {
    if (row.category === null) continue;
    mapped.push({
      dayEntryId: row.day_entry_id,
      category: row.category,
      valueNum: row.value_num,
      unit: row.unit,
      source: row.source,
      excluded: row.excluded,
      deletedAt: row.deleted_at,
      updatedAt: row.updated_at,
    });
  }
  return mapped;
}
