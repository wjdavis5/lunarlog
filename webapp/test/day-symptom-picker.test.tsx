import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { recentTagCodes, RECENT_TAGS_CAP, tagMatchesQuery } from '../src/lib/day/categories';
import { DaySymptomPicker, type PickerCategory } from '../src/pages/DaySymptomPicker';

/**
 * The day editor's symptom picker, the app's `CategoryPicker` on the web:
 * search, a "Recent" row, and sections that open and close. It replaced a
 * single open list of every category, which on a phone was some four
 * thousand pixels of chips above the rest of the form.
 */

const SEARCH = messages['daySheetTagSearchSemanticsLabel'] ?? 'missing';
const CLEAR = messages['daySheetTagSearchClearTooltip'] ?? 'missing';
const RECENT = messages['daySheetTagRecentLabel'] ?? 'missing';
const CUSTOM = messages['daySheetCustomTagsLabel'] ?? 'missing';

function category(name: string, label: string, tags: [string, string][]): PickerCategory {
  return {
    category: { name, wireName: name, label },
    tags: tags.map(([code, display]) => ({ code, display })),
  };
}

const CATEGORIES: PickerCategory[] = [
  category('pain', 'Pain', [
    ['cramps', 'Cramps'],
    ['headache', 'Headache'],
    ['back_pain', 'Back pain'],
  ]),
  category('energy', 'Energy', [
    ['tired', 'Tired'],
    ['energetic', 'Energetic'],
  ]),
  category('skin', 'Skin', [['acne', 'Acne']]),
];

/** The picker with the selection held the way the day page holds it. */
function Harness(props: {
  initial?: string[];
  recent?: string[];
  readOnly?: boolean;
  custom?: { code: string; display: string }[];
  onToggle?: (code: string, categoryName: string | null) => void;
}) {
  const [selected, setSelected] = useState<string[]>(props.initial ?? []);
  return (
    <AppIntlProvider>
      <DaySymptomPicker
        categories={CATEGORIES}
        customTags={props.custom ?? []}
        selected={selected}
        recentCodes={props.recent ?? []}
        readOnly={props.readOnly ?? false}
        onToggle={(code, categoryName) => {
          props.onToggle?.(code, categoryName);
          setSelected((current) =>
            current.includes(code) ? current.filter((c) => c !== code) : [...current, code],
          );
        }}
      />
    </AppIntlProvider>
  );
}

function section(label: string): HTMLElement {
  return screen.getByRole('button', { name: label });
}

function chip(label: string): HTMLElement | null {
  return screen.queryByRole('button', { name: label, pressed: undefined });
}

describe('DaySymptomPicker', () => {
  afterEach(cleanup);

  describe('sections', () => {
    it('start closed on a day with nothing logged, one row per category', () => {
      render(<Harness />);
      for (const label of ['Pain', 'Energy', 'Skin']) {
        expect(section(label)).toHaveAttribute('aria-expanded', 'false');
      }
      expect(chip('Cramps')).toBeNull();
      expect(chip('Acne')).toBeNull();
    });

    it('open and close on their heading', () => {
      render(<Harness />);
      fireEvent.click(section('Pain'));
      expect(section('Pain')).toHaveAttribute('aria-expanded', 'true');
      expect(chip('Cramps')).toBeInTheDocument();
      // The other sections are left alone.
      expect(section('Energy')).toHaveAttribute('aria-expanded', 'false');
      fireEvent.click(section('Pain'));
      expect(chip('Cramps')).toBeNull();
    });

    it('name the panel they control only while it exists', () => {
      render(<Harness />);
      expect(section('Pain')).not.toHaveAttribute('aria-controls');
      fireEvent.click(section('Pain'));
      const panelId = section('Pain').getAttribute('aria-controls');
      expect(panelId).not.toBeNull();
      expect(document.getElementById(panelId ?? '')).toContainElement(chip('Cramps'));
    });

    it('are open when they hold something logged for the day', () => {
      render(<Harness initial={['headache']} />);
      expect(section('Pain')).toHaveAttribute('aria-expanded', 'true');
      expect(chip('Headache')).toHaveAttribute('aria-pressed', 'true');
      expect(section('Energy')).toHaveAttribute('aria-expanded', 'false');
    });

    it('can be closed by hand even while they hold something logged', () => {
      render(<Harness initial={['headache']} />);
      fireEvent.click(section('Pain'));
      expect(section('Pain')).toHaveAttribute('aria-expanded', 'false');
      expect(chip('Headache')).toBeNull();
    });

    // Without this, clearing the only chip in a section that was open
    // because of it would shut the section under the reader's finger.
    it('stay open when their last chip is cleared', () => {
      render(<Harness initial={['headache']} />);
      fireEvent.click(chip('Headache') as HTMLElement);
      expect(chip('Headache')).toHaveAttribute('aria-pressed', 'false');
      expect(section('Pain')).toHaveAttribute('aria-expanded', 'true');
    });

    it('report a press with the category it belongs to', () => {
      const onToggle = vi.fn();
      render(<Harness onToggle={onToggle} />);
      fireEvent.click(section('Energy'));
      fireEvent.click(chip('Tired') as HTMLElement);
      expect(onToggle).toHaveBeenCalledWith('tired', 'energy');
      expect(chip('Tired')).toHaveAttribute('aria-pressed', 'true');
    });
  });

  describe('search', () => {
    it('is a labelled search field', () => {
      render(<Harness />);
      const field = screen.getByLabelText(SEARCH);
      expect(field).toHaveAttribute('type', 'search');
      expect(field).toHaveAttribute('placeholder', messages['daySheetTagSearchHint']);
    });

    it('shows the matching chips under their category and drops the rest', () => {
      render(<Harness />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: 'ache' } });
      expect(chip('Headache')).toBeInTheDocument();
      expect(chip('Cramps')).toBeNull();
      expect(screen.getByRole('heading', { name: 'Pain' })).toBeInTheDocument();
      // Nothing in these matches, so the headings go too.
      expect(screen.queryByRole('heading', { name: 'Energy' })).toBeNull();
      expect(screen.queryByRole('heading', { name: 'Skin' })).toBeNull();
      // Results are all on show: there is nothing to open or close.
      expect(screen.queryByRole('button', { name: 'Pain' })).toBeNull();
    });

    it('ignores case and surrounding spaces', () => {
      render(<Harness />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: '  ACNE ' } });
      expect(chip('Acne')).toBeInTheDocument();
    });

    it('says so when nothing matches', () => {
      render(<Harness />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: 'zzz' } });
      expect(screen.getByRole('status')).toHaveTextContent(
        messages['webDayTagSearchNoMatches'] ?? 'missing',
      );
    });

    it('clears back to the sections, with the chosen tag still on show', () => {
      render(<Harness />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: 'tired' } });
      fireEvent.click(chip('Tired') as HTMLElement);
      fireEvent.click(screen.getByRole('button', { name: CLEAR }));
      expect(screen.getByLabelText(SEARCH)).toHaveValue('');
      expect(section('Energy')).toHaveAttribute('aria-expanded', 'true');
      expect(chip('Tired')).toHaveAttribute('aria-pressed', 'true');
      expect(section('Pain')).toHaveAttribute('aria-expanded', 'false');
    });

    it('offers no clear button until something is typed', () => {
      render(<Harness />);
      expect(screen.queryByRole('button', { name: CLEAR })).toBeNull();
    });
  });

  describe('the Recent row', () => {
    function recentRow() {
      return within(screen.getByRole('group', { name: RECENT }));
    }

    it('offers the recent tags in the order given', () => {
      render(<Harness recent={['tired', 'cramps']} />);
      const labels = recentRow()
        .getAllByRole('button')
        .map((button) => button.textContent);
      expect(labels).toEqual(['Tired', 'Cramps']);
    });

    it('is not drawn when there is nothing recent', () => {
      render(<Harness />);
      expect(screen.queryByRole('group', { name: RECENT })).toBeNull();
    });

    it('leaves out a tag already on the day', () => {
      render(<Harness recent={['tired', 'cramps']} initial={['cramps']} />);
      expect(recentRow().queryByRole('button', { name: 'Cramps' })).toBeNull();
      expect(recentRow().getByRole('button', { name: 'Tired' })).toBeInTheDocument();
    });

    it('leaves out a code that has no chip in the categories on offer', () => {
      render(<Harness recent={['ovulation_positive', 'tired']} />);
      expect(recentRow().getAllByRole('button')).toHaveLength(1);
    });

    it('adds the tag and opens its section, so the choice stays in sight', () => {
      const onToggle = vi.fn();
      render(<Harness recent={['tired']} onToggle={onToggle} />);
      fireEvent.click(recentRow().getByRole('button', { name: 'Tired' }));
      expect(onToggle).toHaveBeenCalledWith('tired', 'energy');
      // It was the only recent tag, so the row is gone and the chip is in
      // its own section, selected.
      expect(screen.queryByRole('group', { name: RECENT })).toBeNull();
      expect(section('Energy')).toHaveAttribute('aria-expanded', 'true');
      expect(chip('Tired')).toHaveAttribute('aria-pressed', 'true');
    });

    it('steps aside while searching', () => {
      render(<Harness recent={['tired']} />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: 'cr' } });
      expect(screen.queryByRole('group', { name: RECENT })).toBeNull();
    });
  });

  describe("the profile's own tags", () => {
    const custom = [{ code: 'custom:01', display: 'Hot water bottle' }];

    it('have a section of their own, under their own name', () => {
      const onToggle = vi.fn();
      render(<Harness custom={custom} onToggle={onToggle} />);
      const group = within(screen.getByRole('group', { name: CUSTOM }));
      fireEvent.click(group.getByRole('button', { name: 'Hot water bottle' }));
      expect(onToggle).toHaveBeenCalledWith('custom:01', null);
    });

    it('are searched with the rest', () => {
      render(<Harness custom={custom} />);
      fireEvent.change(screen.getByLabelText(SEARCH), { target: { value: 'bottle' } });
      expect(chip('Hot water bottle')).toBeInTheDocument();
      expect(screen.queryByRole('status')).toBeNull();
    });
  });

  describe('for someone who can only read the day', () => {
    it('shows what was logged, by category, and nothing to operate', () => {
      render(
        <Harness
          readOnly
          initial={['headache', 'custom:01']}
          recent={['tired']}
          custom={[{ code: 'custom:01', display: 'Hot water bottle' }]}
        />,
      );
      expect(screen.getByRole('heading', { name: 'Pain' })).toBeInTheDocument();
      expect(chip('Headache')).toBeDisabled();
      expect(chip('Hot water bottle')).toBeDisabled();
      // Nothing that was not logged, and no controls.
      expect(chip('Cramps')).toBeNull();
      expect(screen.queryByRole('heading', { name: 'Energy' })).toBeNull();
      expect(screen.queryByLabelText(SEARCH)).toBeNull();
      expect(screen.queryByRole('group', { name: RECENT })).toBeNull();
      expect(screen.queryByRole('button', { name: 'Pain' })).toBeNull();
    });

    it('says so when nothing was logged', () => {
      render(<Harness readOnly />);
      expect(
        screen.getByText(messages['webDayNoSymptomsLogged'] ?? 'missing'),
      ).toBeInTheDocument();
    });
  });
});

describe('recentTagCodes', () => {
  const P = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
  const OTHER = '01M2FWKNG0ZMH2ANCH7R2CM2YC';

  function day(localDate: string, tags: string[], overrides: object = {}) {
    return { profile_id: P, local_date: localDate, tags, deleted_at: null, ...overrides };
  }

  it('lists the latest days first, each day in logged order, with no repeats', () => {
    expect(
      recentTagCodes(
        [
          day('2026-09-28', ['acne', 'cramps']),
          day('2026-09-30', ['headache', 'cramps']),
          day('2026-09-29', ['bloating', 'headache']),
        ],
        P,
      ),
    ).toEqual(['headache', 'cramps', 'bloating', 'acne']);
  });

  it('reads only this profile, and not a deleted day', () => {
    expect(
      recentTagCodes(
        [
          day('2026-09-30', ['cramps'], { profile_id: OTHER }),
          day('2026-09-29', ['headache'], { deleted_at: '2026-09-30T00:00:00Z' }),
          day('2026-09-28', ['acne']),
        ],
        P,
      ),
    ).toEqual(['acne']);
  });

  it('skips a code that is not in the taxonomy', () => {
    expect(recentTagCodes([day('2026-09-30', ['custom:01ABC', 'cramps'])], P)).toEqual([
      'cramps',
    ]);
  });

  it('stops at the cap the app uses', () => {
    expect(RECENT_TAGS_CAP).toBe(8);
    const codes = ['cramps', 'headache', 'acne', 'bloating', 'nausea'];
    expect(recentTagCodes([day('2026-09-30', codes)], P, 3)).toEqual([
      'cramps',
      'headache',
      'acne',
    ]);
  });

  it('is empty for a profile with no entries', () => {
    expect(recentTagCodes([], P)).toEqual([]);
  });
});

describe('tagMatchesQuery', () => {
  it('matches part of the label, whatever the case', () => {
    expect(tagMatchesQuery('Back pain', 'PAIN')).toBe(true);
    expect(tagMatchesQuery('Back pain', 'ck p')).toBe(true);
    expect(tagMatchesQuery('Back pain', 'cramp')).toBe(false);
  });

  it('treats an empty or blank search as matching everything', () => {
    expect(tagMatchesQuery('Acne', '')).toBe(true);
    expect(tagMatchesQuery('Acne', '   ')).toBe(true);
  });
});
