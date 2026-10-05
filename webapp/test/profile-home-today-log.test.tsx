import { cleanup, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it } from 'vitest';

import { todayLogSchema, type TodayLog } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import type { TodayLogCardView } from '../src/lib/profiles/today-log';
import { ProfileHomeTodayLog } from '../src/pages/ProfileHomeTodayLog';
import fixtures from './domain/fixtures.json';

/**
 * The home's "Logged today" card as it is drawn (the browser version of
 * the app's Today log card, issue #1489): the title, the lines in the
 * app's order, the Edit link to today's day page, the quiet line when
 * nothing is logged, and what it must never show.
 *
 * Each logged state is one of the committed parity fixtures: the answer
 * the compiled Dart domain gives for that day.
 */

const PROFILE = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';

interface FixtureCase {
  name: string;
  expected: { data?: unknown };
}

function answer(name: string): TodayLog {
  const fixture = (fixtures as FixtureCase[]).find((entry) => entry.name === name);
  if (fixture === undefined) throw new Error(`no fixture named ${name}`);
  return todayLogSchema.parse(fixture.expected.data);
}

function renderCard(view: TodayLogCardView) {
  return render(
    <AppIntlProvider>
      <MemoryRouter>
        <ProfileHomeTodayLog view={view} profileId={PROFILE} />
      </MemoryRouter>
    </AppIntlProvider>,
  );
}

function logged(name: string, canEdit = true): TodayLogCardView {
  return { kind: 'logged', log: answer(name), canEdit };
}

/** The card's lines, top to bottom. */
function lines(): string[] {
  return within(screen.getByTestId('today-log-card'))
    .getAllByRole('listitem')
    .map((item) => item.textContent ?? '');
}

afterEach(cleanup);

describe('ProfileHomeTodayLog: something logged', () => {
  it('is a region titled "Logged today"', () => {
    renderCard(logged('todayLog.flow-medium'));
    const card = screen.getByRole('region', { name: messages['todayLogTitle'] });
    expect(card).toBe(screen.getByTestId('today-log-card'));
    expect(
      within(card).getByRole('heading', { level: 2, name: messages['todayLogTitle'] }),
    ).toBeInTheDocument();
  });

  it('flow only', () => {
    renderCard(logged('todayLog.flow-medium'));
    expect(lines()).toEqual(['Medium flow']);
  });

  it('tags only', () => {
    renderCard(logged('todayLog.tags-in-stored-order'));
    expect(lines()).toEqual(['Headache, Cramps, Pain free']);
  });

  it('spotting', () => {
    renderCard(logged('todayLog.spotting-over-not-bleeding'));
    expect(lines()).toEqual(['Spotting']);
  });

  it('a reading', () => {
    renderCard(logged('todayLog.readings-in-profile-units'));
    expect(lines()).toEqual(['BBT (°F): 98.6', 'Weight (lb): 110.23']);
  });

  it('a note is "Note added", and its text is nowhere in what is drawn', () => {
    const { container } = renderCard(logged('todayLog.pms-and-note'));
    expect(lines()).toEqual(['PMS', 'Note added']);
    // Text, attributes, everything: the fixture's note is "zebra crossing
    // after the dentist".
    for (const word of ['zebra', 'crossing', 'dentist']) {
      expect(container.innerHTML).not.toContain(word);
    }
  });

  it('more tags than fit', () => {
    renderCard(logged('todayLog.tags-more-than-fit'));
    expect(lines()).toEqual([
      'Cramps, Headache, Back pain, Fatigue, Acne, Migraine and 3 more',
    ]);
  });

  it('only unnamed tags: a count, and no name of any of them', () => {
    const { container } = renderCard(logged('todayLog.tags-only-unnamed'));
    expect(lines()).toEqual(['2 other entries']);
    for (const hidden of ['sex', 'Sex', 'vulation', 'protected']) {
      expect(container.innerHTML).not.toContain(hidden);
    }
  });

  it('everything, in order: flow, tags, PMS, readings, note', () => {
    renderCard(logged('todayLog.everything'));
    expect(lines()).toEqual([
      'Light flow',
      'Cramps, Vaginal discharge: Sticky and 1 more',
      'PMS',
      'BBT (°F): 97.9',
      'Weight (lb): 134.5',
      'Note added',
    ]);
  });

  it("offers Edit, a link to today's day page", () => {
    renderCard(logged('todayLog.flow-medium'));
    const edit = screen.getByRole('link', { name: messages['todayLogEdit'] });
    expect(edit).toHaveAttribute('href', `/day/${PROFILE}`);
    // "Edit" is described by the card's title for someone moving from
    // link to link.
    expect(edit).toHaveAccessibleDescription(messages['todayLogTitle']);
  });
});

describe('ProfileHomeTodayLog: read-only', () => {
  it('shows the summary without Edit to someone who cannot log', () => {
    renderCard(logged('todayLog.everything', false));
    expect(lines()).toHaveLength(6);
    expect(screen.queryByRole('link')).toBeNull();
    expect(screen.queryByTestId('today-log-edit')).toBeNull();
  });
});

describe('ProfileHomeTodayLog: nothing logged', () => {
  it('is one quiet line, with no title, no lines and no Edit', () => {
    renderCard({ kind: 'empty' });
    const card = screen.getByTestId('today-log-card');
    expect(card).toHaveTextContent(messages['todayLogEmpty']);
    expect(card.textContent).toBe(messages['todayLogEmpty']);
    expect(screen.getByTestId('today-log-empty')).toHaveClass('card-body');
    expect(screen.queryByText(messages['todayLogTitle'])).toBeNull();
    expect(screen.queryByRole('listitem')).toBeNull();
    expect(screen.queryByRole('link')).toBeNull();
  });
});

describe('ProfileHomeTodayLog: not shown', () => {
  it('draws nothing at all', () => {
    const { container } = renderCard({ kind: 'none' });
    expect(container).toBeEmptyDOMElement();
  });
});
