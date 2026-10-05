import { cleanup, render, renderHook, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { CycleHistoryView } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { useT } from '../src/i18n/t';
import {
  compareRow,
  formatDays,
  ProfileHomeComparison,
  ProfileHomeHistory,
} from '../src/pages/ProfileHomeHistory';

/**
 * The home's cycle comparison compares the two newest completed cycles on
 * its own. With fewer than two there is nothing to compare, and the page
 * shows no card: the app's empty state for this tells the reader to select
 * two cycles, which this page has no way to do.
 */

type Item = CycleHistoryView['items'][number];

function cycle(start: string, lengthDays: number | null, open = false): Item {
  return {
    start,
    lengthDays,
    omitted: false,
    open,
    outlier: false,
    countedInAverages: !open,
    bleedDays: 4,
  };
}

function view(items: Item[]): CycleHistoryView {
  const closed = items.filter((item) => !item.open).length;
  return {
    items,
    episodeCount: items.length,
    completedCycleCount: closed,
    validCycleCount: closed,
    averagedCycleCount: closed,
    meanCycleLengthDays: null,
    meanPeriodLengthDays: null,
    variationDays: null,
    confidence: null,
  };
}

function renderComparison(history: CycleHistoryView) {
  return render(
    <AppIntlProvider>
      <ProfileHomeComparison history={history} />
    </AppIntlProvider>,
  );
}

describe('ProfileHomeComparison', () => {
  afterEach(cleanup);

  it('renders nothing for a profile with only an open cycle', () => {
    const { container } = renderComparison(view([cycle('2026-09-28', null, true)]));
    expect(container).toBeEmptyDOMElement();
  });

  it('renders nothing with one completed cycle', () => {
    const { container } = renderComparison(
      view([cycle('2026-09-28', null, true), cycle('2026-08-31', 28)]),
    );
    expect(container).toBeEmptyDOMElement();
    // In particular, not the app's "select two cycles" empty state.
    expect(screen.queryByText(messages['cycleComparisonNotEnoughTitle'])).toBeNull();
    expect(screen.queryByText(messages['cycleComparisonNotEnoughBody'])).toBeNull();
  });

  it('compares the two newest completed cycles once there are two', () => {
    renderComparison(
      view([cycle('2026-09-28', null, true), cycle('2026-08-31', 28), cycle('2026-08-01', 30)]),
    );
    expect(
      screen.getByRole('heading', { name: messages['cycleComparisonScreenTitle'] }),
    ).toBeInTheDocument();
    expect(screen.getByTestId('compare-length-diff')).toHaveTextContent(/^2 days$/);
    // Both cycles in this fixture have four bleed days.
    expect(screen.getByTestId('compare-bleed-diff')).toHaveTextContent(/^0 days$/);
    expect(screen.getByText('Length: 28 days · Bleed days: 4 days')).toBeInTheDocument();
    expect(screen.getByText('Length: 30 days · Bleed days: 4 days')).toBeInTheDocument();
  });

  it('says a difference of one is one day', () => {
    renderComparison(
      view([cycle('2026-09-28', null, true), cycle('2026-08-31', 28), cycle('2026-08-02', 29)]),
    );
    expect(screen.getByTestId('compare-length-diff')).toHaveTextContent(/^1 day$/);
  });
});

/**
 * A number of days says "days". The page printed the bare number, so
 * "Variation 0" did not say what it counted, and it rounded an average
 * that the app shows to one decimal.
 */
describe('day counts on the home carry their unit', () => {
  afterEach(cleanup);

  function t() {
    return renderHook(() => useT(), { wrapper: AppIntlProvider }).result.current;
  }

  it('formatDays writes a whole number bare and anything else to one decimal', () => {
    expect(formatDays(t(), 28)).toBe('28 days');
    expect(formatDays(t(), 1)).toBe('1 day');
    expect(formatDays(t(), 0)).toBe('0 days');
    expect(formatDays(t(), 28.5)).toBe('28.5 days');
    expect(formatDays(t(), 4.75)).toBe('4.8 days');
  });

  it('compareRow names an ongoing cycle and an unknown bleed count without a unit', () => {
    expect(compareRow(t(), null, null)).toBe(
      `Length: ${messages['cycleComparisonOngoingLabel']} · Bleed days: —`,
    );
    expect(compareRow(t(), 31, 1)).toBe('Length: 31 days · Bleed days: 1 day');
  });

  it('the history statistics show days, as the app does', () => {
    render(
      <AppIntlProvider>
        <ProfileHomeHistory
          history={{
            ...view([cycle('2026-09-28', null, true), cycle('2026-08-31', 28)]),
            meanCycleLengthDays: 28.5,
            meanPeriodLengthDays: 5,
            variationDays: 1,
          }}
        />
      </AppIntlProvider>,
    );
    expect(screen.getByTestId('stat-avg-cycle')).toHaveTextContent(/^28\.5 days$/);
    expect(screen.getByTestId('stat-avg-period')).toHaveTextContent(/^5 days$/);
    expect(screen.getByTestId('stat-variation')).toHaveTextContent(/^1 day$/);
  });

  it('a statistic that is not known yet stays a dash, with no unit', () => {
    render(
      <AppIntlProvider>
        <ProfileHomeHistory
          history={{
            ...view([cycle('2026-09-28', null, true), cycle('2026-08-31', 28)]),
            meanCycleLengthDays: 28,
            meanPeriodLengthDays: null,
            variationDays: null,
          }}
        />
      </AppIntlProvider>,
    );
    expect(screen.getByTestId('stat-avg-cycle')).toHaveTextContent(/^28 days$/);
    expect(screen.getByTestId('stat-avg-period')).toHaveTextContent(/^—$/);
    expect(screen.getByTestId('stat-variation')).toHaveTextContent(/^—$/);
  });
});
