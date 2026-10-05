import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { CycleHistoryView } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { ProfileHomeComparison } from '../src/pages/ProfileHomeHistory';

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
    expect(screen.getByTestId('compare-length-diff')).toHaveTextContent('2');
  });
});
