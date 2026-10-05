import { createIntl } from 'react-intl';
import { describe, expect, it } from 'vitest';

import { todayLogSchema, type TodayLog } from '../src/domain/schemas';
import messages from '../src/i18n/messages.en.json';
import type { TFunction } from '../src/i18n/t';
import { emptySyncedData, type SyncedData } from '../src/lib/domain';
import {
  liveEntryOn,
  readTodayLog,
  todayLogCardView,
  todayLogFlowLine,
  todayLogLines,
  todayLogRequest,
} from '../src/lib/profiles/today-log';
import type {
  DayEntryRow,
  ObservationRow,
  ProfileRow,
  ProfileTagRegistryRow,
} from '../src/lib/schemas';
import fixtures from './domain/fixtures.json';
import { loadDomainModule } from './domain/load-module';

/**
 * What the home's "Logged today" card says, and to whom (the browser
 * version of the app's Today log card, issue #1489).
 *
 * The rules are not written here. The card's inputs are the committed
 * parity fixtures: the exact answers the compiled Dart domain gives
 * (`todayLog` in tool/web_domain/facade.dart), pinned to the Dart side by
 * test/domain/web_domain_fixtures_test.dart and to the compiled module by
 * test/domain/parity.test.ts. What is tested here is the web's own part:
 * which rows of the snapshot go into the call, who is shown a card, and
 * how an answer becomes lines. The one place the real compiled module is
 * called is the last group, which follows a note into the call and looks
 * for it in what comes back.
 */

const UID = '00000000-0000-4000-8000-0000000000u1';
const PROFILE = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const OTHER_PROFILE = '01M2FWKNG0ZMH2ANCH7R2CM2YA';
const ENTRY = '01M2FWKNG0ZMH2ANCH7R2CM2E1';
const TODAY = '2026-09-30';
const NOTE = 'zebra crossing after the dentist';

const intl = createIntl({ locale: 'en', messages });
const t: TFunction = (id, values) => intl.formatMessage({ id }, values);

interface FixtureCase {
  name: string;
  method: string;
  request: Record<string, unknown>;
  expected: { ok: boolean; data?: unknown };
}

/** The domain's own answer for one committed `todayLog` case. */
function answer(name: string): TodayLog {
  const fixture = (fixtures as FixtureCase[]).find((entry) => entry.name === name);
  if (fixture === undefined) throw new Error(`no fixture named ${name}`);
  return todayLogSchema.parse(fixture.expected.data);
}

function profileRow(overrides: Partial<ProfileRow> = {}): ProfileRow {
  return {
    id: PROFILE,
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

function entryRow(overrides: Partial<DayEntryRow> = {}): DayEntryRow {
  return {
    id: ENTRY,
    user_id: UID,
    profile_id: PROFILE,
    local_date: TODAY,
    tz: 'UTC',
    flow: 'medium',
    tags: ['cramps'],
    note: NOTE,
    note_private: false,
    pms: false,
    source: 'manual',
    created_at: '2026-09-30T08:00:00Z',
    updated_at: '2026-09-30T08:00:00Z',
    deleted_at: null,
    server_version: 3,
    ...overrides,
  };
}

function observationRow(overrides: Partial<ObservationRow> = {}): ObservationRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2B1',
    day_entry_id: ENTRY,
    profile_id: PROFILE,
    local_date: TODAY,
    tz: 'UTC',
    observed_at: null,
    category: 'bbt',
    code: null,
    value_num: 36.7,
    value_text: null,
    unit: 'celsius',
    intensity: null,
    excluded: false,
    source: 'manual',
    created_at: '2026-09-30T08:00:00Z',
    updated_at: '2026-09-30T08:00:00Z',
    deleted_at: null,
    server_version: 4,
    ...overrides,
  };
}

function tagRow(overrides: Partial<ProfileTagRegistryRow> = {}): ProfileTagRegistryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2T1',
    profile_id: PROFILE,
    code: 'back_cracking',
    display_name: 'Back cracking',
    category: 'custom',
    intensity_enabled: false,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 5,
    ...overrides,
  };
}

function synced(overrides: Partial<SyncedData> = {}): SyncedData {
  return { ...emptySyncedData(), profiles: [profileRow()], ...overrides };
}

describe('liveEntryOn', () => {
  it("finds the profile's live entry for the day", () => {
    const data = synced({ day_entries: [entryRow()] });
    expect(liveEntryOn(data, PROFILE, TODAY)?.id).toBe(ENTRY);
  });

  it('is null on a day with no entry', () => {
    const data = synced({ day_entries: [entryRow({ local_date: '2026-09-29' })] });
    expect(liveEntryOn(data, PROFILE, TODAY)).toBeNull();
  });

  it('never returns a deleted entry', () => {
    const data = synced({
      day_entries: [entryRow({ deleted_at: '2026-09-30T09:00:00Z' })],
    });
    expect(liveEntryOn(data, PROFILE, TODAY)).toBeNull();
  });

  it("never returns another profile's entry for the same day", () => {
    const data = synced({ day_entries: [entryRow({ profile_id: OTHER_PROFILE })] });
    expect(liveEntryOn(data, PROFILE, TODAY)).toBeNull();
  });
});

describe('todayLogRequest', () => {
  it('asks about no entry when the day has none', () => {
    expect(todayLogRequest(synced(), PROFILE, TODAY)).toEqual({ entry: null });
  });

  it("sends the day's entry in the shape the domain decodes", () => {
    const request = todayLogRequest(synced({ day_entries: [entryRow()] }), PROFILE, TODAY);
    expect(request.entry).toMatchObject({
      id: ENTRY,
      profileId: PROFILE,
      localDate: TODAY,
      flow: 'medium',
      tags: ['cramps'],
      pms: false,
      deletedAt: null,
    });
  });

  it("sends only the live observations attached to today's entry", () => {
    const request = todayLogRequest(
      synced({
        day_entries: [entryRow()],
        observations: [
          observationRow(),
          observationRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2B2',
            category: 'spotting',
            value_num: null,
            unit: null,
          }),
          // Deleted: not the day's.
          observationRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2B3',
            category: 'weight',
            value_num: 61,
            unit: 'kg',
            deleted_at: '2026-09-30T09:00:00Z',
          }),
          // Another day's entry: not this day's.
          observationRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2B4',
            day_entry_id: '01M2FWKNG0ZMH2ANCH7R2CM2E0',
            category: 'weight',
            value_num: 60,
            unit: 'kg',
          }),
        ],
      }),
      PROFILE,
      TODAY,
    );
    expect(request.observations).toEqual([
      {
        dayEntryId: ENTRY,
        category: 'bbt',
        valueNum: 36.7,
        unit: 'celsius',
        source: 'manual',
      },
      {
        dayEntryId: ENTRY,
        category: 'spotting',
        valueNum: null,
        unit: null,
        source: 'manual',
      },
    ]);
  });

  it("sends the profile's own tag names, and no deleted or foreign ones", () => {
    const request = todayLogRequest(
      synced({
        day_entries: [entryRow()],
        profile_tag_registry: [
          tagRow(),
          // Retired, not deleted: it still names its rows.
          tagRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2T2',
            code: 'old_habit',
            display_name: 'Old habit',
            hidden_at: '2026-09-10T00:00:00Z',
          }),
          tagRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2T3',
            code: 'gone_tag',
            display_name: 'Gone',
            deleted_at: '2026-09-11T00:00:00Z',
          }),
          tagRow({
            id: '01M2FWKNG0ZMH2ANCH7R2CM2T4',
            profile_id: OTHER_PROFILE,
            code: 'not_hers',
            display_name: 'Not hers',
          }),
        ],
      }),
      PROFILE,
      TODAY,
    );
    expect(request.customTags).toEqual([
      { code: 'back_cracking', displayName: 'Back cracking' },
      { code: 'old_habit', displayName: 'Old habit' },
    ]);
  });

  it("sends the profile's display units when it has them", () => {
    const withUnits = todayLogRequest(
      synced({
        profiles: [profileRow({ bbt_unit: 'fahrenheit', weight_unit: 'lb' })],
        day_entries: [entryRow()],
      }),
      PROFILE,
      TODAY,
    );
    expect(withUnits.bbtUnit).toBe('fahrenheit');
    expect(withUnits.weightUnit).toBe('lb');

    const without = todayLogRequest(synced({ day_entries: [entryRow()] }), PROFILE, TODAY);
    expect('bbtUnit' in without).toBe(false);
    expect('weightUnit' in without).toBe(false);
  });
});

describe('todayLogCardView: who is shown a card', () => {
  const logged = answer('todayLog.flow-medium');
  const nothing = answer('todayLog.no-entry');

  it('the subject who can log sees the summary with Edit', () => {
    expect(todayLogCardView({ log: logged, lens: 'subject', canLog: true })).toEqual({
      kind: 'logged',
      log: logged,
      canEdit: true,
    });
  });

  it('the subject who can log sees the quiet line when nothing is logged', () => {
    expect(todayLogCardView({ log: nothing, lens: 'subject', canLog: true })).toEqual({
      kind: 'empty',
    });
  });

  it('someone who cannot log sees the summary without Edit', () => {
    expect(todayLogCardView({ log: logged, lens: 'subject', canLog: false })).toEqual({
      kind: 'logged',
      log: logged,
      canEdit: false,
    });
  });

  it('someone who cannot log sees no card when nothing is logged', () => {
    expect(todayLogCardView({ log: nothing, lens: 'subject', canLog: false })).toEqual({
      kind: 'none',
    });
  });

  it('a guardian sees no card, logged or not, able to log or not', () => {
    for (const log of [logged, nothing]) {
      for (const canLog of [true, false]) {
        expect(todayLogCardView({ log, lens: 'guardian', canLog })).toEqual({ kind: 'none' });
      }
    }
  });

  it('no answer from the domain is no card', () => {
    expect(todayLogCardView({ log: null, lens: 'subject', canLog: true })).toEqual({
      kind: 'none',
    });
  });
});

describe('todayLogFlowLine', () => {
  it('a bleed level reads "{level} flow", in the calendar\'s words', () => {
    expect(todayLogFlowLine('light', t)).toBe('Light flow');
    expect(todayLogFlowLine('medium', t)).toBe('Medium flow');
    expect(todayLogFlowLine('heavy', t)).toBe('Heavy flow');
    expect(todayLogFlowLine('super_heavy', t)).toBe('Super heavy flow');
  });

  it('spotting and not-bleeding read as themselves', () => {
    expect(todayLogFlowLine('spotting', t)).toBe('Spotting');
    expect(todayLogFlowLine('not_bleeding', t)).toBe('Not bleeding');
  });
});

describe('todayLogLines: what the card says', () => {
  it('flow only', () => {
    expect(todayLogLines(answer('todayLog.flow-medium'), t)).toEqual(['Medium flow']);
    expect(todayLogLines(answer('todayLog.flow-not-bleeding'), t)).toEqual(['Not bleeding']);
  });

  it('tags only, by the labels the domain chose, in stored order', () => {
    expect(todayLogLines(answer('todayLog.tags-in-stored-order'), t)).toEqual([
      'Headache, Cramps, Pain free',
    ]);
    expect(todayLogLines(answer('todayLog.tags-contextual-labels'), t)).toEqual([
      'Vaginal discharge: Sticky, Stool: Normal, Craving: Sweet, ' +
        'Sleep duration: 0-3 hours, Took pain medication, Bloating',
    ]);
  });

  it('spotting reads "Spotting", not the "Not bleeding" its flow was raised to', () => {
    expect(todayLogLines(answer('todayLog.spotting-over-not-bleeding'), t)).toEqual([
      'Spotting',
    ]);
    expect(todayLogLines(answer('todayLog.spotting-only-from-import'), t)).toEqual([
      'Spotting',
    ]);
  });

  it('bleed wins over spotting', () => {
    expect(todayLogLines(answer('todayLog.bleed-wins-over-spotting'), t)).toEqual([
      'Heavy flow',
    ]);
  });

  it("a reading reads under the day editor's field label", () => {
    expect(todayLogLines(answer('todayLog.readings-as-stored'), t)).toEqual([
      'BBT (°C): 36.7',
      'Weight (kg): 61',
    ]);
  });

  it("a reading is in the profile's unit, to two places at most", () => {
    expect(todayLogLines(answer('todayLog.readings-in-profile-units'), t)).toEqual([
      'BBT (°F): 98.6',
      'Weight (lb): 110.23',
    ]);
  });

  it('a note is the one line "Note added"; the PMS marker is "PMS"', () => {
    expect(todayLogLines(answer('todayLog.pms-and-note'), t)).toEqual(['PMS', 'Note added']);
  });

  it('more tags than fit: six are named, the rest are "and N more"', () => {
    expect(todayLogLines(answer('todayLog.tags-more-than-fit'), t)).toEqual([
      'Cramps, Headache, Back pain, Fatigue, Acne, Migraine and 3 more',
    ]);
    expect(todayLogLines(answer('todayLog.tags-exactly-six'), t)).toEqual([
      'Cramps, Headache, Back pain, Fatigue, Acne, Migraine',
    ]);
  });

  it('tags that are counted and not named join "and N more"', () => {
    const lines = todayLogLines(answer('todayLog.tags-unnamed-are-counted'), t);
    expect(lines).toEqual(['Cramps and 3 more']);
    for (const hidden of ['sex', 'Sex', 'regnancy', 'some_new_code']) {
      expect(lines.join(' ')).not.toContain(hidden);
    }
  });

  it('"and 1 more" is singular', () => {
    expect(todayLogLines(answer('todayLog.everything'), t)[1]).toBe(
      'Cramps, Vaginal discharge: Sticky and 1 more',
    );
  });

  it('only unnamed tags: a count and nothing else', () => {
    expect(todayLogLines(answer('todayLog.tags-only-unnamed'), t)).toEqual(['2 other entries']);
    const one: TodayLog = { ...answer('todayLog.tags-only-unnamed'), moreTagCount: 1 };
    expect(todayLogLines(one, t)).toEqual(['1 other entry']);
  });

  it("everything, in the app's order: flow, tags, PMS, readings, note", () => {
    expect(todayLogLines(answer('todayLog.everything'), t)).toEqual([
      'Light flow',
      'Cramps, Vaginal discharge: Sticky and 1 more',
      'PMS',
      'BBT (°F): 97.9',
      'Weight (lb): 134.5',
      'Note added',
    ]);
  });

  it('nothing logged is no lines', () => {
    expect(todayLogLines(answer('todayLog.no-entry'), t)).toEqual([]);
    expect(todayLogLines(answer('todayLog.tombstone-says-nothing'), t)).toEqual([]);
  });
});

// The note goes into the call and no further. This is the call itself,
// against the real compiled module: a snapshot whose entry carries a note
// goes in, and what comes back, and every line built from it, is searched
// for the note's words.
describe('readTodayLog: the note stops at the call', () => {
  const module = loadDomainModule();
  const data = synced({ day_entries: [entryRow()] });

  it('sends the note in, so the domain can say one exists', () => {
    expect(todayLogRequest(data, PROFILE, TODAY).entry?.note).toBe(NOTE);
  });

  it('gets back the fact of a note and none of its text', () => {
    const log = readTodayLog(module, data, PROFILE, TODAY);
    expect(log.hasNote).toBe(true);
    expect(log.flow).toBe('medium');
    expect(log.tags).toEqual(['Cramps']);
    const everything = JSON.stringify(log) + todayLogLines(log, t).join(' ');
    for (const word of ['zebra', 'crossing', 'dentist']) {
      expect(everything).not.toContain(word);
    }
    expect(todayLogLines(log, t)).toEqual(['Medium flow', 'Cramps', 'Note added']);
  });

  it('answers nothing logged for a profile with no entry today', () => {
    const log = readTodayLog(module, data, OTHER_PROFILE, TODAY);
    expect(log).toEqual(answer('todayLog.no-entry'));
  });
});

describe('the todayLog answer at the client boundary', () => {
  it('drops anything the module answers beyond what the card may say', () => {
    const parsed = todayLogSchema.parse({
      ...answer('todayLog.pms-and-note'),
      note: NOTE,
      tagCodes: ['unprotected_sex'],
    });
    expect('note' in parsed).toBe(false);
    expect('tagCodes' in parsed).toBe(false);
    expect(JSON.stringify(parsed)).not.toContain('zebra');
  });

  it('refuses a flow value the card has no words for', () => {
    expect(() =>
      todayLogSchema.parse({ ...answer('todayLog.flow-medium'), flow: 'none' }),
    ).toThrow();
  });
});
