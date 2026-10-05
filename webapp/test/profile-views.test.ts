import { describe, expect, it } from 'vitest';

import {
  callerRoleFor,
  canEditProfile,
  entriesToDomainJson,
  estimateDateText,
  homeEstimateView,
  irregularFramingInEffect,
  isCivilDate,
  isoDateFormatter,
  isoDaysBetween,
  profileDomainInputs,
  profileHomePath,
  profileListsFromSyncedData,
  profileModeFromDb,
  shiftIsoDate,
  showsFertileWindow,
} from '../src/lib/profiles/profile-views';
import { emptySyncedData, mergeSyncedData, type SyncedData } from '../src/lib/domain';
import type {
  CycleOverrideRow,
  DayEntryRow,
  ProfileGuardianRow,
  ProfileModeRow,
  ProfileRow,
} from '../src/lib/schemas';
import type { Prediction } from '../src/domain/schemas';

/**
 * The profile screens' pure derivations (issue #1253): list grouping,
 * role gating, the domain request inputs, the #853 framing composition,
 * and the estimate presentation — the web mirrors of
 * `care_modes.dart`/`overview_panel.dart`'s own rules.
 */

const UID = '00000000-0000-4000-8000-0000000000u1';
const OTHER = '00000000-0000-4000-8000-0000000000u2';

function profileRow(overrides: Partial<ProfileRow> = {}): ProfileRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    user_id: UID,
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
    ...overrides,
  };
}

function guardianRow(overrides: Partial<ProfileGuardianRow> = {}): ProfileGuardianRow {
  return {
    id: '00000000-0000-4000-8000-0000000000g1',
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    user_id: UID,
    role: 'primary_guardian',
    status: 'accepted',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
    ...overrides,
  };
}

function entryRow(overrides: Partial<DayEntryRow> = {}): DayEntryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
    user_id: UID,
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    local_date: '2026-09-28',
    tz: 'UTC',
    flow: 'medium',
    tags: ['cramps'],
    note: 'private note',
    note_private: true,
    pms: false,
    source: 'manual',
    created_at: '2026-09-28T08:00:00Z',
    updated_at: '2026-09-28T08:00:00Z',
    deleted_at: null,
    server_version: 3,
    ...overrides,
  };
}

function modeRow(overrides: Partial<ProfileModeRow> = {}): ProfileModeRow {
  return {
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    mode: 'tracking',
    mode_started_on: null,
    health_sync_consent: false,
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
    ...overrides,
  };
}

function overrideRow(overrides: Partial<CycleOverrideRow> = {}): CycleOverrideRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2O1',
    profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    cycle_start_date: '2026-08-15',
    excluded_from_average: true,
    manual_start: false,
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
    ...overrides,
  };
}

function synced(overrides: Partial<SyncedData> = {}): SyncedData {
  return mergeSyncedData(emptySyncedData(), {
    profiles: [profileRow()],
    day_entries: [entryRow()],
    observations: [],
    profile_modes: [modeRow()],
    cycle_overrides: [overrideRow()],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians: [guardianRow()],
    guardian_notes: [],
    ...overrides,
  });
}

describe('profileListsFromSyncedData', () => {
  it('groups mine, shared, and archived, and never shows tombstones', () => {
    const mine = profileRow();
    const shared = profileRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2SB',
      user_id: OTHER,
      sort_order: 1,
    });
    const archived = profileRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2AR',
      archived_at: '2026-09-01T00:00:00Z',
      sort_order: 2,
    });
    const deleted = profileRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2DE',
      deleted_at: '2026-09-02T00:00:00Z',
    });
    const lists = profileListsFromSyncedData(
      synced({
        profiles: [deleted, archived, shared, mine],
        profile_guardians: [],
      }),
      UID,
    );
    expect(lists.mine.map((p) => p.id)).toEqual([mine.id]);
    expect(lists.shared.map((p) => p.id)).toEqual([shared.id]);
    expect(lists.archived.map((p) => p.id)).toEqual([archived.id]);
  });

  it('sorts archived by newest archive first', () => {
    const older = profileRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2A1',
      archived_at: '2026-08-01T00:00:00Z',
      user_id: OTHER,
    });
    const newer = profileRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2A2',
      archived_at: '2026-09-01T00:00:00Z',
      user_id: OTHER,
    });
    const lists = profileListsFromSyncedData(
      synced({ profiles: [older, newer], profile_guardians: [] }),
      UID,
    );
    expect(lists.archived.map((p) => p.id)).toEqual([newer.id, older.id]);
  });
});

describe('callerRoleFor / canEditProfile', () => {
  it('reads the accepted membership and fails closed', () => {
    expect(callerRoleFor(synced(), profileRow().id, UID)).toBe('primary_guardian');
    expect(callerRoleFor(synced(), profileRow().id, OTHER)).toBeNull();
    expect(callerRoleFor(synced(), '01M2FWKNG0ZMH2ANCH7R2CM2NO', UID)).toBeNull();
    const revoked = synced({
      profile_guardians: [
        guardianRow({ status: 'revoked', revoked_at: '2026-09-01T00:00:00Z' }),
      ],
    });
    expect(callerRoleFor(revoked, profileRow().id, UID)).toBeNull();
  });

  it('gates edits to primary and co-parent only', () => {
    expect(canEditProfile('primary_guardian')).toBe(true);
    expect(canEditProfile('co_parent')).toBe(true);
    expect(canEditProfile('caregiver')).toBe(false);
    expect(canEditProfile('viewer')).toBe(false);
    expect(canEditProfile(null)).toBe(false);
  });
});

describe('entriesToDomainJson', () => {
  it('maps live rows onto the export shape the facade decodes', () => {
    const mapped = entriesToDomainJson({
      profileId: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
      entries: [entryRow()],
    });
    expect(mapped).toHaveLength(1);
    expect(mapped[0]).toMatchObject({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
      profileId: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
      localDate: '2026-09-28',
      flow: 'medium',
      tags: ['cramps'],
      note: 'private note',
      notePrivate: true,
    });
  });

  it('drops tombstones and other profiles rows', () => {
    const mapped = entriesToDomainJson({
      profileId: '01M2FWKNG0ZMH2ANCH7R2CM2XZ',
      entries: [
        entryRow({ id: '01M2FWKNG0ZMH2ANCH7R2CM2E2', deleted_at: '2026-09-29T00:00:00Z' }),
        entryRow({
          id: '01M2FWKNG0ZMH2ANCH7R2CM2E3',
          profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2OT',
        }),
      ],
    });
    expect(mapped).toEqual([]);
  });
});

describe('profileDomainInputs', () => {
  it('maps live entries, omits tombstones, and carries the omission list', () => {
    const tombstone = entryRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2E2',
      deleted_at: '2026-09-29T00:00:00Z',
    });
    const otherProfile = entryRow({
      id: '01M2FWKNG0ZMH2ANCH7R2CM2E3',
      profile_id: '01M2FWKNG0ZMH2ANCH7R2CM2OT',
    });
    const inputs = profileDomainInputs(
      synced({ day_entries: [entryRow(), tombstone, otherProfile] }),
      profileRow().id,
    );
    expect(inputs.entries.map((entry) => entry.id)).toEqual([entryRow().id]);
    expect(inputs.omittedCycleStarts).toEqual(['2026-08-15']);
    expect(inputs.predictionsEnabled).toBe(true);
    // Export-row fields the facade decodes.
    expect(inputs.entries[0]).toMatchObject({
      localDate: '2026-09-28',
      flow: 'medium',
      tags: ['cramps'],
      notePrivate: true,
      deletedAt: null,
    });
  });

  it('drops a deleted override from the omission list', () => {
    const inputs = profileDomainInputs(
      synced({
        cycle_overrides: [
          overrideRow(),
          overrideRow({ id: '01M2FWKNG0ZMH2ANCH7R2CM2O2', deleted_at: '2026-09-02T00:00:00Z' }),
          overrideRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2O3',
            cycle_start_date: '2026-07-01',
            excluded_from_average: false,
          }),
        ],
      }),
      profileRow().id,
    );
    expect(inputs.omittedCycleStarts).toEqual(['2026-08-15']);
  });

  it('carries the stored cycle facts when present', () => {
    const inputs = profileDomainInputs(
      synced({
        profiles: [
          profileRow({
            last_period_start: '2026-09-20',
            typical_cycle_length_days: 30,
            typical_period_length_days: 5,
          }),
        ],
      }),
      profileRow().id,
    );
    expect(inputs.facts).toEqual({
      lastPeriodStart: '2026-09-20',
      typicalCycleLengthDays: 30,
      typicalPeriodLengthDays: 5,
    });
  });

  it('carries birth control and non-default life-stage modes, and neither otherwise', () => {
    const withMode = profileDomainInputs(
      synced({
        profile_modes: [
          modeRow({
            mode: 'pregnancy',
            birth_control_method: 'pill',
            birth_control_started_on: '2026-09-01',
          }),
        ],
      }),
      profileRow().id,
    );
    expect(withMode.lifecycleMode).toBe('pregnancy');
    expect(withMode.birthControl).toEqual({
      method: 'pill',
      startedOn: '2026-09-01',
      stoppedOn: null,
    });

    const plain = profileDomainInputs(
      synced({ profile_modes: [modeRow({ mode: 'tracking', birth_control_method: 'none' })] }),
      profileRow().id,
    );
    expect(plain.lifecycleMode).toBeUndefined();
    expect(plain.birthControl).toBeUndefined();
  });
});

describe('irregularFramingInEffect (the #853 rule)', () => {
  it('an explicitly stored value wins in both directions', () => {
    expect(irregularFramingInEffect({ mode: 'standard', stored: true, tier: 'high' })).toBe(
      true,
    );
    expect(irregularFramingInEffect({ mode: 'teen', stored: false, tier: null })).toBe(false);
  });

  it('a teen defaults ON until the estimate reaches high confidence', () => {
    expect(irregularFramingInEffect({ mode: 'teen', stored: null, tier: null })).toBe(true);
    expect(irregularFramingInEffect({ mode: 'teen', stored: null, tier: 'learning' })).toBe(
      true,
    );
    expect(irregularFramingInEffect({ mode: 'teen', stored: null, tier: 'high' })).toBe(false);
  });

  it('every other mode defaults OFF; the legacy irregular wire mode is always ON', () => {
    expect(
      irregularFramingInEffect({ mode: 'standard', stored: null, tier: 'provisional' }),
    ).toBe(false);
    expect(profileModeFromDb('irregular')).toBe('irregular');
    expect(irregularFramingInEffect({ mode: 'irregular', stored: null, tier: 'high' })).toBe(
      true,
    );
  });
});

// Issue #1390: the port of the calendar's `_showsFertileWindow`.
describe('showsFertileWindow', () => {
  const steady = { storedIrregularFraming: null, tier: 'high', lifecycleMode: null } as const;

  it('shows the window for a standard profile and for a teen whose cycles have steadied', () => {
    expect(showsFertileWindow({ ...steady, profileMode: 'standard' })).toBe(true);
    expect(showsFertileWindow({ ...steady, profileMode: 'standard', tier: 'learning' })).toBe(
      true,
    );
    expect(showsFertileWindow({ ...steady, profileMode: 'teen' })).toBe(true);
  });

  it('hides it for the retired irregular mode, whatever framing is stored', () => {
    expect(showsFertileWindow({ ...steady, profileMode: 'irregular' })).toBe(false);
    expect(
      showsFertileWindow({
        ...steady,
        profileMode: 'irregular',
        storedIrregularFraming: false,
      }),
    ).toBe(false);
  });

  it('hides it whenever the irregular framing is in effect', () => {
    // An explicit choice on a standard profile.
    expect(
      showsFertileWindow({ ...steady, profileMode: 'standard', storedIrregularFraming: true }),
    ).toBe(false);
    // The teen default: on until the estimate reaches high.
    expect(showsFertileWindow({ ...steady, profileMode: 'teen', tier: 'learning' })).toBe(
      false,
    );
    expect(showsFertileWindow({ ...steady, profileMode: 'teen', tier: null })).toBe(false);
    // And an explicit "off" lifts it for a teen at any tier.
    expect(
      showsFertileWindow({
        ...steady,
        profileMode: 'teen',
        tier: 'learning',
        storedIrregularFraming: false,
      }),
    ).toBe(true);
  });

  it('hides it for the Perimenopause life stage and no other', () => {
    expect(
      showsFertileWindow({
        ...steady,
        profileMode: 'standard',
        lifecycleMode: 'perimenopause',
      }),
    ).toBe(false);
    expect(
      showsFertileWindow({ ...steady, profileMode: 'standard', lifecycleMode: 'conceive' }),
    ).toBe(true);
  });
});

// Issue #1389: a civil date has no zone, so it must not shift with the
// browser's. These hold only because the formatter pins UTC — the suite
// runs west of UTC (vite.config.ts) precisely so they would fail without it.
describe('isoDateFormatter', () => {
  it('writes the civil date it was given', () => {
    const medium = isoDateFormatter('en', { dateStyle: 'medium' });
    expect(medium('2026-10-20')).toBe('Oct 20, 2026');
    expect(medium('2026-01-01')).toBe('Jan 1, 2026');
    expect(medium('2026-12-31')).toBe('Dec 31, 2026');
  });

  it('keeps the weekday in step with the date', () => {
    const long = isoDateFormatter('en', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
    expect(long('2026-10-04')).toBe('Sunday, October 4, 2026');
  });

  // Issue #1473. `Intl.DateTimeFormat` throws on an invalid date, and these
  // formatters run while a page renders: a throw took the notes page down
  // when the date field's year box was given a fifth digit.
  it('never throws: a value that is not a civil date comes back as given', () => {
    const full = isoDateFormatter('en', { dateStyle: 'full' });
    for (const odd of [
      '20261-10-05',
      '10000-01-01',
      '275760-09-13',
      '2026-02-31',
      '2026-13-01',
      '2026-00-10',
      '2026-10-5',
      '26-10-05',
      '',
      'not a date',
      '2026-10-05T00:00:00Z',
    ]) {
      expect(() => full(odd), odd).not.toThrow();
      expect(full(odd), odd).toBe(odd);
    }
    expect(full('2026-10-05')).toBe('Monday, October 5, 2026');
  });
});

describe('isCivilDate', () => {
  it('accepts a real four-digit-year date', () => {
    for (const iso of ['2026-10-05', '2024-02-29', '1999-12-31', '0001-01-01', '9999-12-31']) {
      expect(isCivilDate(iso), iso).toBe(true);
    }
  });

  it('refuses a longer year, a day that does not exist, and anything else', () => {
    for (const iso of [
      '20261-10-05',
      '10000-01-01',
      '2026-02-29',
      '2026-02-31',
      '2026-04-31',
      '2026-13-01',
      '2026-00-10',
      '2026-10-00',
      '2026-10-5',
      '2026/10/05',
      ' 2026-10-05',
      '',
    ]) {
      expect(isCivilDate(iso), iso).toBe(false);
    }
  });
});

describe('profileHomePath', () => {
  it('names the profile, because the home opens the first one without it', () => {
    expect(profileHomePath('01M2FWKNG0ZMH2ANCH7R2CM2XZ')).toBe(
      '/?profile=01M2FWKNG0ZMH2ANCH7R2CM2XZ',
    );
  });

  it('is the plain home when there is no profile to name', () => {
    expect(profileHomePath('')).toBe('/');
  });

  it('encodes whatever it is given', () => {
    expect(profileHomePath('a b&c')).toBe('/?profile=a%20b%26c');
  });
});

describe('estimateDateText (the app estimate row rule)', () => {
  it('high confidence shows the exact date', () => {
    expect(
      estimateDateText({ estimatedNextStart: '2026-10-14', spreadDays: 3, tier: 'high' }),
    ).toEqual({ kind: 'date', iso: '2026-10-14' });
  });

  it('other tiers show the spread range; a degenerate spread falls back', () => {
    expect(
      estimateDateText({ estimatedNextStart: '2026-10-14', spreadDays: 3.2, tier: 'learning' }),
    ).toEqual({ kind: 'range', startIso: '2026-10-11', endIso: '2026-10-17' });
    expect(
      estimateDateText({ estimatedNextStart: '2026-10-14', spreadDays: 0.2, tier: 'learning' }),
    ).toEqual({ kind: 'date', iso: '2026-10-14' });
  });
});

describe('homeEstimateView (the care-mode composition)', () => {
  const active: Prediction = {
    kind: 'active',
    today: '2026-10-03',
    lastEpisodeStart: '2026-09-28',
    estimatedNextStart: '2026-10-14',
    originalEstimatedNextStart: '2026-10-14',
    averagedCycleLengths: [28],
    meanCycleLengthDays: 28,
    cycleDay: 6,
    duringEpisode: false,
    completedCycleCount: 6,
    validCycleCount: 6,
    meanPeriodLengthDays: 5,
    spreadDays: 1,
    validRatio: 1,
    tier: 'high',
    basis: 'statistical',
    unusuallyLongCycle: false,
    staleHistory: false,
    daysLate: null,
    daysUntilNextPeriod: 11,
    forecast: [],
    pms: null,
  };

  it('passes suppression through with its reason', () => {
    expect(
      homeEstimateView({
        prediction: { kind: 'suppressed', method: null, lifecycleMode: 'pregnancy' },
        profileMode: 'standard',
        storedIrregularFraming: null,
        todayIso: '2026-10-03',
      }),
    ).toMatchObject({ kind: 'suppressed', lifecycleModeDb: 'pregnancy', methodDb: null });
  });

  it('notEnoughHistory carries the teen flag and the 3-cycle target', () => {
    expect(
      homeEstimateView({
        prediction: {
          kind: 'notEnoughHistory',
          episodeCount: 1,
          completedCycleCount: 1,
          validCycleCount: 1,
          usableCycleCount: 1,
        },
        profileMode: 'teen',
        storedIrregularFraming: null,
        todayIso: '2026-10-03',
      }),
    ).toEqual({
      kind: 'notEnoughHistory',
      teen: true,
      completedCycles: 1,
      neededCycles: 3,
    });
  });

  it('composes the framing: stored true forces ranges even for a standard profile', () => {
    const view = homeEstimateView({
      prediction: active,
      profileMode: 'standard',
      storedIrregularFraming: true,
      todayIso: '2026-10-03',
    });
    expect(view).toMatchObject({ kind: 'active', mode: 'standard', composed: true });
  });

  it('a teen at high tier with no stored flag reads uncomposed', () => {
    const view = homeEstimateView({
      prediction: active,
      profileMode: 'teen',
      storedIrregularFraming: null,
      todayIso: '2026-10-03',
    });
    expect(view).toMatchObject({ kind: 'active', mode: 'teen', composed: false });
  });

  it('carries the overdue line only when daysLate is positive', () => {
    const late = homeEstimateView({
      prediction: { ...active, daysLate: 3 },
      profileMode: 'standard',
      storedIrregularFraming: null,
      todayIso: '2026-10-03',
    });
    expect(late).toMatchObject({ kind: 'active', overdue: { daysLate: 3 } });
    const onTime = homeEstimateView({
      prediction: { ...active, daysLate: 0 },
      profileMode: 'standard',
      storedIrregularFraming: null,
      todayIso: '2026-10-03',
    });
    expect(onTime).toMatchObject({ kind: 'active', overdue: null });
  });

  it('counts the episode day from the last episode start', () => {
    const during = homeEstimateView({
      prediction: { ...active, duringEpisode: true },
      profileMode: 'standard',
      storedIrregularFraming: null,
      todayIso: '2026-09-30',
    });
    expect(during).toMatchObject({ kind: 'active', duringEpisode: true, episodeDay: 3 });
  });
});

describe('date helpers', () => {
  it('shifts and diffs civil dates without time-zone wobble', () => {
    expect(shiftIsoDate('2026-10-14', -3)).toBe('2026-10-11');
    expect(shiftIsoDate('2026-01-01', -1)).toBe('2025-12-31');
    expect(isoDaysBetween('2026-09-28', '2026-10-03')).toBe(5);
  });
});
