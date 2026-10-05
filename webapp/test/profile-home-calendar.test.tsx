import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it } from 'vitest';

import type { ForecastDayCell } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import type { DayEntryRow } from '../src/lib/schemas';
import { ProfileHomeCalendar } from '../src/pages/ProfileHomeCalendar';

/**
 * The month calendar as rendered (issues #1389, #1390, #1391): what a day
 * cell paints and announces for a fixed "today", so the three rules the
 * app's own calendar keeps — the civil date it names, the fertile window
 * the framing may hide, and the spotting ring that needs recorded spotting
 * — are pinned on the real component, not only on its pure helpers.
 */

const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const TODAY = '2026-10-03';
const FERTILE = messages['sharingPredictionCalendarLegendFertile'] ?? 'missing';

function entryRow(localDate: string, flow: string, tags: string[] = []): DayEntryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
    user_id: 'u1',
    profile_id: PROFILE_ID,
    local_date: localDate,
    tz: 'UTC',
    flow,
    tags,
    note: null,
    note_private: false,
    pms: false,
    source: 'manual',
    created_at: `${localDate}T08:00:00Z`,
    updated_at: `${localDate}T08:00:00Z`,
    deleted_at: null,
    server_version: 1,
  };
}

function forecastCell(overrides: Partial<ForecastDayCell> = {}): ForecastDayCell {
  return {
    predictedBleed: false,
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

function renderCalendar(
  options: {
    entries?: DayEntryRow[];
    forecast?: Record<string, ForecastDayCell>;
    spottingIsos?: string[];
    fertileShown?: boolean;
  } = {},
) {
  return render(
    <AppIntlProvider>
      <MemoryRouter>
        <ProfileHomeCalendar
          todayIso={TODAY}
          profileId={PROFILE_ID}
          entryByIso={new Map((options.entries ?? []).map((row) => [row.local_date, row]))}
          forecastByIso={new Map(Object.entries(options.forecast ?? {}))}
          spottingIsos={new Set(options.spottingIsos ?? [])}
          pmsBandActive={false}
          fertileShown={options.fertileShown ?? true}
        />
      </MemoryRouter>
    </AppIntlProvider>,
  );
}

/** The day cell (the gridcell and its link) for one ISO date. */
function dayCell(iso: string): { cell: HTMLElement; link: HTMLElement } {
  const link = screen
    .getAllByRole('link')
    .find((candidate) => candidate.getAttribute('href')?.endsWith(`date=${iso}`));
  if (link === undefined) throw new Error(`no day cell for ${iso}`);
  return { cell: link.closest('[role="gridcell"]') as HTMLElement, link };
}

describe('ProfileHomeCalendar', () => {
  afterEach(cleanup);

  // Issue #1389: a civil date read as UTC midnight was written in the
  // browser's zone, so the Americas heard the day before.
  it('names each cell by its own civil date, whatever the zone', () => {
    renderCalendar();
    expect(dayCell('2026-10-04').link).toHaveAccessibleName('Sunday, October 4, 2026');
    expect(dayCell('2026-10-01').link).toHaveAccessibleName('Thursday, October 1, 2026');
    expect(dayCell('2026-10-31').link).toHaveAccessibleName('Saturday, October 31, 2026');
  });

  // Issue #1390.
  it('paints and announces the fertile window when the framing shows it', () => {
    renderCalendar({
      forecast: { '2026-10-12': forecastCell({ fertileWindow: true }) },
      fertileShown: true,
    });
    const { cell, link } = dayCell('2026-10-12');
    expect(cell).toHaveClass('cal-fertile');
    expect(link).toHaveAccessibleName(`Monday, October 12, 2026, ${FERTILE}`);
    expect(screen.getByTestId('calendar-legend')).toHaveTextContent(FERTILE);
  });

  it('hides the fertile window from the cell, its label and the legend when the framing hides it', () => {
    renderCalendar({
      forecast: {
        '2026-10-12': forecastCell({ fertileWindow: true }),
        '2026-10-13': forecastCell({ fertileWindow: true, predictedBleed: true }),
      },
      fertileShown: false,
    });
    const fertileOnly = dayCell('2026-10-12');
    expect(fertileOnly.cell).not.toHaveClass('cal-fertile');
    expect(fertileOnly.link).toHaveAccessibleName('Monday, October 12, 2026');
    // The rest of a mixed cell still renders.
    const mixed = dayCell('2026-10-13');
    expect(mixed.cell).not.toHaveClass('cal-fertile');
    expect(mixed.cell).toHaveClass('cal-predicted');
    expect(mixed.link).toHaveAccessibleName(
      `Tuesday, October 13, 2026, ${messages['calendarLegendPredicted'] ?? 'missing'}`,
    );
    expect(screen.getByTestId('calendar-legend')).not.toHaveTextContent(FERTILE);
  });

  // Issue #1391.
  it('draws no flow mark on a symptom-only or not-bleeding day', () => {
    renderCalendar({
      entries: [
        entryRow('2026-10-01', 'none', ['cramps']),
        entryRow('2026-10-02', 'not_bleeding'),
      ],
    });
    for (const iso of ['2026-10-01', '2026-10-02']) {
      const { cell } = dayCell(iso);
      expect(cell).not.toHaveClass('cal-spotting');
      expect(cell.querySelectorAll('.cal-mark')).toHaveLength(0);
    }
  });

  it('rings a day with recorded spotting and marks a bleed day by level', () => {
    renderCalendar({
      entries: [entryRow('2026-10-01', 'not_bleeding'), entryRow('2026-10-02', 'medium')],
      spottingIsos: ['2026-10-01'],
    });
    expect(dayCell('2026-10-01').cell).toHaveClass('cal-spotting');
    const bleed = dayCell('2026-10-02').cell;
    expect(bleed).not.toHaveClass('cal-spotting');
    expect(bleed.querySelectorAll('.cal-mark')).toHaveLength(3);
  });

  // The app fills a logged period day with its flow colour. The web drew
  // only the marks, so a recorded period read more weakly than an estimate.
  it('fills a logged bleed day with its flow colour', () => {
    renderCalendar({
      entries: [
        entryRow('2026-09-28', 'light'),
        entryRow('2026-09-29', 'medium'),
        entryRow('2026-09-30', 'heavy'),
      ],
    });
    // The calendar opens on October; step back to the month just logged.
    fireEvent.click(screen.getByRole('button', { name: 'Previous month' }));
    expect(dayCell('2026-09-28').cell).toHaveClass('cal-flow', 'cal-flow-light');
    expect(dayCell('2026-09-29').cell).toHaveClass('cal-flow', 'cal-flow-medium');
    expect(dayCell('2026-09-30').cell).toHaveClass('cal-flow', 'cal-flow-heavy');
  });

  it('leaves a day with no bleed unfilled, logged or not', () => {
    renderCalendar({
      entries: [entryRow('2026-10-01', 'not_bleeding'), entryRow('2026-10-02', 'spotting')],
      spottingIsos: ['2026-10-02'],
      forecast: { '2026-10-20': forecastCell({ predictedBleed: true }) },
    });
    expect(dayCell('2026-10-01').cell).not.toHaveClass('cal-flow');
    expect(dayCell('2026-10-02').cell).not.toHaveClass('cal-flow');
    // An estimated period day is never drawn as a recorded one.
    const predicted = dayCell('2026-10-20').cell;
    expect(predicted).toHaveClass('cal-predicted');
    expect(predicted).not.toHaveClass('cal-flow');
    // Nor is a day nobody logged.
    expect(dayCell('2026-10-03').cell).not.toHaveClass('cal-flow');
  });
});
