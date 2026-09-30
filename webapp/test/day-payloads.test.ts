import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  buildSavePlan,
  canEditProfileMetadata,
  canWriteDayContent,
  DayPermissionError,
  DayValidationError,
  resolveCallerRole,
  resolveEffectiveFlow,
  type DayEdit,
  type LoadedDayView,
} from '../src/lib/day/payloads';
import type {
  CycleOverrideRow,
  DayEntryRow,
  ObservationRow,
  ProfileGuardianRow,
  ProfileRow,
  ProfileModeRow,
} from '../src/lib/schemas';

/**
 * The save-plan contract (issue #1254): what the web editor actually puts
 * on the wire for `sync_push`. The shapes mirror the app's row codec
 * (lib/data/sync/row_codec.dart) and the shapes pinned by
 * supabase/tests/seed_sync_push_sample_test.sql; the key sets are checked
 * against the allowlists derived from the committed schema snapshot, so a
 * payload key the server would reject ("row carries an unknown key") fails
 * here first.
 */

const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const ENTRY_ID = '01M2FWKNG0ZMH2ANCH7R2CM2Y2';
const NOW = '2026-09-30T08:00:00.000Z';
const TODAY = '2026-09-30';

let idCounter = 0;
const nextFixedId = (): string => {
  idCounter += 1;
  // Deterministic, valid ULIDs: fixed 10-char timestamp + counter-encoded
  // randomness — unique per draw, ascending within the test.
  const base = '01ARZ3NDEK';
  const tail = idCounter.toString(32).toUpperCase().padStart(16, '0');
  return base + tail.slice(-16).replace(/[IL OU]/g, '0');
};

const baseProfile: ProfileRow = {
  id: PROFILE_ID,
  user_id: '00000000-0000-0000-0000-00000000owner',
  display_name: 'Maya',
  is_minor: false,
  mode: 'standard',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  archived_at: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  deleted_at: null,
  server_version: 1,
  bbt_unit: 'celsius',
  weight_unit: 'kg',
  tracking_preferences: null,
};

const acceptedMembership = (role: string, isSubject = false): ProfileGuardianRow => ({
  id: '00000000-0000-0000-0000-00000000memb',
  profile_id: PROFILE_ID,
  user_id: '00000000-0000-0000-0000-00000000user',
  role,
  status: 'accepted',
  is_subject: isSubject ? true : false,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  server_version: 1,
});

const baseEntry: DayEntryRow = {
  id: ENTRY_ID,
  user_id: '00000000-0000-0000-0000-00000000user',
  profile_id: PROFILE_ID,
  local_date: '2026-09-29',
  tz: 'UTC',
  flow: 'none',
  tags: [],
  note: null,
  note_private: false,
  pms: false,
  source: 'manual',
  source_id: null,
  created_at: '2026-09-29T08:00:00.000Z',
  updated_at: '2026-09-29T08:00:00.000Z',
  deleted_at: null,
  server_version: 2,
};

const emptyEdit: DayEdit = {
  flow: 'none',
  flowExplicitlySet: false,
  spotting: false,
  pms: false,
  tags: [],
  note: null,
  notePrivate: false,
  bbt: null,
  weight: null,
  mode: null,
  manualCycleStart: false,
  excludeCycleFromAverage: false,
};

function viewWith(overrides: {
  entry?: DayEntryRow | null;
  observations?: ObservationRow[];
  membership?: ProfileGuardianRow | null;
  mode?: ProfileModeRow | null;
  cycleOverride?: CycleOverrideRow | null;
  profile?: Partial<ProfileRow>;
}): LoadedDayView {
  return {
    profile: { ...baseProfile, ...overrides.profile },
    entry: overrides.entry === undefined ? baseEntry : overrides.entry,
    observations: overrides.observations ?? [],
    membership:
      overrides.membership === undefined
        ? acceptedMembership('primary_guardian', true)
        : overrides.membership,
    mode: overrides.mode ?? null,
    cycleOverride: overrides.cycleOverride ?? null,
  };
}

function observation(partial: Partial<ObservationRow>): ObservationRow {
  return {
    id: partial.id ?? nextFixedId(),
    day_entry_id: partial.day_entry_id ?? ENTRY_ID,
    profile_id: PROFILE_ID,
    local_date: partial.local_date ?? '2026-09-29',
    observed_at: null,
    tz: 'UTC',
    category: partial.category ?? 'bbt',
    code: partial.code ?? null,
    value_num: partial.value_num ?? null,
    value_text: null,
    unit: partial.unit ?? null,
    intensity: null,
    excluded: false,
    source: partial.source ?? 'manual',
    source_id: null,
    created_at: '2026-09-29T08:00:00.000Z',
    updated_at: '2026-09-29T08:00:00.000Z',
    deleted_at: null,
    server_version: 3,
  };
}

const planFor = (edit: Partial<DayEdit>, view: LoadedDayView) =>
  buildSavePlan({
    profileId: PROFILE_ID,
    dateIso: '2026-09-29',
    todayIso: TODAY,
    tz: 'UTC',
    edit: { ...emptyEdit, ...edit },
    view,
    nowIso: NOW,
    newId: nextFixedId,
  });

describe('buildSavePlan: the day_entries payload', () => {
  it('updates the stored row in place (same id, LWW timestamp, provenance carried)', () => {
    const stored = { ...baseEntry, source: 'clue_import', source_id: 'clue-42' };
    const plan = planFor({ note: 'updated' }, viewWith({ entry: stored }));
    expect(plan.dayEntries).toHaveLength(1);
    const row = plan.dayEntries[0] as unknown as Record<string, unknown>;
    expect(row['id']).toBe(ENTRY_ID);
    expect(row['profile_id']).toBe(PROFILE_ID);
    expect(row['local_date']).toBe('2026-09-29');
    expect(row['tz']).toBe('UTC');
    expect(row['source']).toBe('clue_import');
    expect(row['source_id']).toBe('clue-42');
    expect(row['updated_at']).toBe(NOW);
    expect(row['note']).toBe('updated');
    // Server-stamped / never-emitted keys stay off the wire.
    for (const banned of [
      'created_at',
      'server_version',
      'user_id',
      'logged_by_user_id',
      'import_id',
      'deleted_at',
    ]) {
      expect(row).not.toHaveProperty(banned);
    }
  });

  it('creates a fresh ULID row when the day has none yet', () => {
    const plan = planFor({ note: 'first' }, viewWith({ entry: null }));
    const row = plan.dayEntries[0] as unknown as Record<string, unknown>;
    expect(row['id']).not.toBe(ENTRY_ID);
    expect(String(row['id'])).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/);
  });

  it('writes an explicit flow and the first-class pms marker', () => {
    const plan = planFor({ flow: 'heavy', flowExplicitlySet: true, pms: true }, viewWith({}));
    const row = plan.dayEntries[0] as unknown as Record<string, unknown>;
    expect(row['flow']).toBe('heavy');
    expect(row['pms']).toBe(true);
  });

  it('empty string note saves as null (the app compose rule)', () => {
    const plan = planFor({ note: '' }, viewWith({}));
    expect((plan.dayEntries[0] as unknown as Record<string, unknown>)['note']).toBeNull();
  });

  it('rejects a note past the 2000-char bound before anything is sent', () => {
    expect(() => planFor({ note: 'x'.repeat(2001) }, viewWith({}))).toThrowError(
      DayValidationError,
    );
  });
});

describe('buildSavePlan: tag and flow bounds', () => {
  it('rejects more than 32 tags (is_valid_tags_array)', () => {
    const tags = Array.from({ length: 33 }, (_, i) => `tag_${i}`);
    try {
      planFor({ tags }, viewWith({}));
      expect.fail('expected DayValidationError');
    } catch (error) {
      expect(error).toBeInstanceOf(DayValidationError);
      expect((error as DayValidationError).field).toBe('tags');
    }
  });

  it('rejects a tag longer than 64 characters', () => {
    try {
      planFor({ tags: ['x'.repeat(65)] }, viewWith({}));
      expect.fail('expected DayValidationError');
    } catch (error) {
      expect((error as DayValidationError).field).toBe('tags');
    }
  });

  it('rejects a date past the bounds (the #848 policy, client-side first)', () => {
    const args = {
      profileId: PROFILE_ID,
      dateIso: '2026-10-05',
      todayIso: TODAY,
      tz: 'UTC',
      edit: emptyEdit,
      view: viewWith({}),
      nowIso: NOW,
      newId: nextFixedId,
    };
    expect(() => buildSavePlan(args)).toThrowError(DayValidationError);
    expect(() =>
      buildSavePlan({
        ...args,
        view: viewWith({ profile: { birth_year: 1990 } }),
        dateIso: '1989-01-01',
      }),
    ).toThrowError(DayValidationError);
  });
});

describe('buildSavePlan: note privacy (#849)', () => {
  it('lets the subject choose privacy while the stored note is still empty', () => {
    const plan = planFor(
      { note: 'secret', notePrivate: true },
      viewWith({ membership: acceptedMembership('primary_guardian', true) }),
    );
    expect((plan.dayEntries[0] as unknown as Record<string, unknown>)['note_private']).toBe(
      true,
    );
  });

  it('locks private on: a private note is never cleared, even by the subject', () => {
    const stored = { ...baseEntry, note_private: true, note: 'secret' };
    const plan = planFor(
      { note: 'secret', notePrivate: false },
      viewWith({ entry: stored, membership: acceptedMembership('primary_guardian', true) }),
    );
    expect((plan.dayEntries[0] as unknown as Record<string, unknown>)['note_private']).toBe(
      true,
    );
  });

  it('locks private off: a shared note with content can never be made private', () => {
    const stored = { ...baseEntry, note_private: false, note: 'shared' };
    const plan = planFor(
      { note: 'shared', notePrivate: true },
      viewWith({ entry: stored, membership: acceptedMembership('primary_guardian', true) }),
    );
    expect((plan.dayEntries[0] as unknown as Record<string, unknown>)['note_private']).toBe(
      false,
    );
  });

  it('a non-subject echoes the stored flag, so a masked private note survives their save', () => {
    const stored = { ...baseEntry, note_private: true, note: null };
    const plan = planFor(
      { notePrivate: false },
      viewWith({ entry: stored, membership: acceptedMembership('caregiver') }),
    );
    expect((plan.dayEntries[0] as unknown as Record<string, unknown>)['note_private']).toBe(
      true,
    );
  });
});

describe('buildSavePlan: spotting (#247)', () => {
  it('creates one spotting observation when toggled on with none stored', () => {
    const plan = planFor({ spotting: true }, viewWith({}));
    const spotting = plan.observations.filter(
      (row) => (row as unknown as Record<string, unknown>)['category'] === 'spotting',
    );
    expect(spotting).toHaveLength(1);
    const row = spotting[0] as unknown as Record<string, unknown>;
    expect(row['code']).toBe('spotting');
    expect(row['day_entry_id']).toBe(ENTRY_ID);
    expect(row['source']).toBe('manual');
    expect(row).not.toHaveProperty('deleted_at');
  });

  it('tombstones every stored spotting row when toggled off', () => {
    const stored = observation({ category: 'spotting', code: 'spotting' });
    const plan = planFor({ spotting: false }, viewWith({ observations: [stored] }));
    const row = plan.observations[0] as unknown as Record<string, unknown>;
    expect(row['id']).toBe(stored.id);
    expect(row['deleted_at']).toBe(NOW);
    // Tombstones carry no payload.
    expect(row).not.toHaveProperty('category');
    expect(row).not.toHaveProperty('code');
  });

  it('leaves the stored spotting row alone when already on', () => {
    const stored = observation({ category: 'spotting', code: 'spotting' });
    const plan = planFor({ spotting: true }, viewWith({ observations: [stored] }));
    expect(plan.observations).toHaveLength(0);
  });

  it('a spotting-only day asserts not_bleeding; removing spotting reverts to none', () => {
    // resolveEffectiveFlow's #247 rule, ported.
    expect(resolveEffectiveFlow({ ...emptyEdit, spotting: true }, false)).toBe('not_bleeding');
    expect(
      resolveEffectiveFlow(
        { ...emptyEdit, spotting: false, flow: 'not_bleeding', flowExplicitlySet: false },
        true,
      ),
    ).toBe('none');
    expect(
      resolveEffectiveFlow(
        { ...emptyEdit, spotting: false, flow: 'not_bleeding', flowExplicitlySet: true },
        true,
      ),
    ).toBe('not_bleeding');
    expect(
      (
        planFor({ spotting: true }, viewWith({})).dayEntries[0] as unknown as Record<
          string,
          unknown
        >
      )['flow'],
    ).toBe('not_bleeding');
  });
});

describe('buildSavePlan: measurements (#457)', () => {
  it('creates a manual bbt row in the unit the profile stores', () => {
    const plan = planFor({ bbt: 36.6 }, viewWith({}));
    const bbt = plan.observations.find(
      (row) => (row as unknown as Record<string, unknown>)['category'] === 'bbt',
    ) as unknown as Record<string, unknown>;
    expect(bbt).toBeDefined();
    expect(bbt['value_num']).toBe(36.6);
    expect(bbt['unit']).toBe('celsius');
    expect(bbt['source']).toBe('manual');
    expect(bbt).not.toHaveProperty('observed_at');
  });

  it('updates the stored measurement row in place rather than duplicating it', () => {
    const stored = observation({ category: 'bbt', value_num: 36.4, unit: 'celsius' });
    const plan = planFor({ bbt: 36.7 }, viewWith({ observations: [stored] }));
    expect(plan.observations).toHaveLength(1);
    const row = plan.observations[0] as unknown as Record<string, unknown>;
    expect(row['id']).toBe(stored.id);
    expect(row['value_num']).toBe(36.7);
    expect(row).not.toHaveProperty('deleted_at');
  });

  it('no-op when the measurement is unchanged', () => {
    const stored = observation({ category: 'weight', value_num: 63.5, unit: 'kg' });
    const plan = planFor({ weight: 63.5 }, viewWith({ observations: [stored] }));
    expect(plan.observations).toHaveLength(0);
  });

  it('tombstones the stored measurement when the field is cleared', () => {
    const stored = observation({ category: 'weight', value_num: 63.5, unit: 'kg' });
    const plan = planFor({ weight: null }, viewWith({ observations: [stored] }));
    const row = plan.observations[0] as unknown as Record<string, unknown>;
    expect(row['id']).toBe(stored.id);
    expect(row['deleted_at']).toBe(NOW);
  });

  it('enforces the sanity range in the stored unit', () => {
    const fahrenheit = viewWith({ profile: { bbt_unit: 'fahrenheit' } });
    try {
      planFor({ bbt: 110 }, fahrenheit);
      expect.fail('expected DayValidationError');
    } catch (error) {
      expect((error as DayValidationError).field).toBe('bbt');
    }
    expect(() => planFor({ weight: 5 }, viewWith({}))).toThrowError(DayValidationError);
    expect(() => planFor({ bbt: 36.6 }, viewWith({}))).not.toThrow();
  });
});

describe('buildSavePlan: roles', () => {
  it('a viewer cannot save anything', () => {
    const view = viewWith({ membership: acceptedMembership('viewer') });
    expect(() => planFor({}, view)).toThrowError(DayPermissionError);
    expect(canWriteDayContent('viewer')).toBe(false);
    expect(canWriteDayContent('caregiver')).toBe(true);
  });

  it('a caregiver can write the day but not profile metadata', () => {
    const view = viewWith({ membership: acceptedMembership('caregiver') });
    expect(() => planFor({ note: 'from caregiver' }, view)).not.toThrow();
    expect(() => planFor({ mode: 'pregnancy' }, view)).toThrowError(DayPermissionError);
    expect(() => planFor({ manualCycleStart: true }, view)).toThrowError(DayPermissionError);
    expect(canEditProfileMetadata('caregiver')).toBe(false);
    expect(canEditProfileMetadata('co_parent')).toBe(true);
  });

  it('an absent membership resolves to viewer', () => {
    expect(resolveCallerRole(null)).toBe('viewer');
  });
});

describe('buildSavePlan: life-stage mode and cycle corrections (#188)', () => {
  it('emits a modes row only when the mode changed, keyed on the edited date', () => {
    const unchanged = planFor({ mode: null }, viewWith({}));
    expect(unchanged.profileModes).toHaveLength(0);

    const changed = planFor({ mode: 'pregnancy' }, viewWith({}));
    expect(changed.profileModes).toHaveLength(1);
    const row = changed.profileModes[0] as unknown as Record<string, unknown>;
    expect(row['profile_id']).toBe(PROFILE_ID);
    expect(row['mode']).toBe('pregnancy');
    expect(row['mode_started_on']).toBe('2026-09-29');
    expect(row['updated_at']).toBe(NOW);
    // The per-key containment guards preserve everything omitted here.
    expect(row).not.toHaveProperty('birth_control_method');
    expect(row).not.toHaveProperty('health_sync_consent');
  });

  it('creates a cycle override with a fresh ULID when flagged', () => {
    const plan = planFor(
      { manualCycleStart: true, excludeCycleFromAverage: true },
      viewWith({ cycleOverride: null }),
    );
    expect(plan.cycleOverrides).toHaveLength(1);
    const row = plan.cycleOverrides[0] as unknown as Record<string, unknown>;
    expect(String(row['id'])).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/);
    expect(row['manual_start']).toBe(true);
    expect(row['excluded_from_average']).toBe(true);
    expect(row['cycle_start_date']).toBe('2026-09-29');
  });

  it('no-op when the stored override already matches the flags', () => {
    const stored: CycleOverrideRow = {
      id: nextFixedId(),
      profile_id: PROFILE_ID,
      cycle_start_date: '2026-09-29',
      excluded_from_average: false,
      manual_start: true,
      note_id: null,
      updated_at: '2026-09-29T08:00:00.000Z',
      deleted_at: null,
      server_version: 4,
    };
    const plan = planFor(
      { manualCycleStart: true, excludeCycleFromAverage: false },
      viewWith({ cycleOverride: stored }),
    );
    expect(plan.cycleOverrides).toHaveLength(0);
  });

  it('tombstones the override when every flag is cleared', () => {
    const stored: CycleOverrideRow = {
      id: nextFixedId(),
      profile_id: PROFILE_ID,
      cycle_start_date: '2026-09-29',
      excluded_from_average: true,
      manual_start: false,
      note_id: null,
      updated_at: '2026-09-29T08:00:00.000Z',
      deleted_at: null,
      server_version: 4,
    };
    const plan = planFor(
      { manualCycleStart: false, excludeCycleFromAverage: false },
      viewWith({ cycleOverride: stored }),
    );
    const row = plan.cycleOverrides[0] as unknown as Record<string, unknown>;
    expect(row['id']).toBe(stored.id);
    expect(row['deleted_at']).toBe(NOW);
    expect(row).not.toHaveProperty('manual_start');
  });
});

describe('payload keys stay inside the derived allowlists', () => {
  // The same derivation sync_push materializes at CREATE time: every column
  // of the table minus its server-stamped columns. Read from the committed
  // schema snapshot so a drift fails this file, not a live push.
  const types = readFileSync(join(__dirname, '../../supabase/database.types.ts'), 'utf8');

  function columnsOf(table: string): string[] {
    const match = types.match(
      new RegExp(`\\n\\s*${table}: \\{\\s*Row: \\{([\\s\\S]*?)\\}\\s*Insert:`),
    );
    if (match === null) throw new Error(`no ${table} Row block in database.types.ts`);
    return [...match[1].matchAll(/^\s{10}(\w+):/gm)].map((m) => m[1]);
  }

  function allowlistOf(table: string, stamped: string[]): Set<string> {
    return new Set(columnsOf(table).filter((column) => !stamped.includes(column)));
  }

  it('day_entries', () => {
    const allowlist = allowlistOf('day_entries', ['created_at']);
    const plan = planFor(
      { flow: 'light', flowExplicitlySet: true, tags: ['cramps'], note: 'x', pms: true },
      viewWith({}),
    );
    for (const key of Object.keys(plan.dayEntries[0] as unknown as Record<string, unknown>)) {
      expect(allowlist.has(key)).toBe(true);
    }
  });

  it('observations', () => {
    const allowlist = allowlistOf('observations', ['created_at']);
    const plan = planFor({ spotting: true, bbt: 36.6, weight: 63.5 }, viewWith({}));
    for (const row of plan.observations) {
      for (const key of Object.keys(row as unknown as Record<string, unknown>)) {
        expect(allowlist.has(key)).toBe(true);
      }
    }
  });

  it('profile_modes and cycle_overrides', () => {
    const modeAllowlist = allowlistOf('profile_modes', []);
    const overrideAllowlist = allowlistOf('cycle_overrides', []);
    const plan = planFor({ mode: 'conceive', manualCycleStart: true }, viewWith({}));
    for (const key of Object.keys(plan.profileModes[0] as unknown as Record<string, unknown>)) {
      expect(modeAllowlist.has(key)).toBe(true);
    }
    for (const key of Object.keys(
      plan.cycleOverrides[0] as unknown as Record<string, unknown>,
    )) {
      expect(overrideAllowlist.has(key)).toBe(true);
    }
  });
});
