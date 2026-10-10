import { cleanup, fireEvent, render, renderHook, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { CycleRecap } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { useT } from '../src/i18n/t';
import {
  cycleDayList,
  RecapCard,
  recapSymptomLabel,
  usualRangeText,
} from '../src/pages/RecapCard';

/**
 * The cycle-end recap card (issue #1796). Every fact is the domain's; these
 * cases pin the copy composition and the phone's suppression rules, not any
 * number the engine computes.
 */

function recap(overrides: Partial<CycleRecap> = {}): CycleRecap {
  return {
    cycleNumber: 5,
    cycleStart: '2026-09-03',
    previousCycleStart: '2026-08-06',
    cycleLengthDays: 28,
    previousCycleLengthDays: 27,
    lengthChangeDays: 1,
    bleedDayCountDelta: 0,
    hasEstimate: true,
    confidence: 'high',
    meanCycleLengthDays: 28.5,
    meanPeriodLengthDays: 4,
    spreadDays: 1.5,
    usableCycleCount: 6,
    statisticChange: false,
    tierChanged: false,
    previousConfidence: null,
    meanCycleShiftDays: null,
    meanPeriodShiftDays: null,
    recurringSymptoms: [{ tag: 'cramps', cycleDays: [2, 3] }],
    crampCycleDays: [2, 3],
    ...overrides,
  };
}

function renderCard(
  value: CycleRecap,
  opts: { irregularFraming?: boolean; onDismiss?: () => void } = {},
) {
  return render(
    <AppIntlProvider>
      <RecapCard
        recap={value}
        irregularFraming={opts.irregularFraming ?? false}
        onDismiss={opts.onDismiss ?? (() => {})}
      />
    </AppIntlProvider>,
  );
}

describe('RecapCard (issue #1796)', () => {
  afterEach(() => {
    cleanup();
  });

  it('titles the card with the cycle number and states the length', () => {
    renderCard(recap());
    expect(
      screen.getByText(messages['cycleRecapTitle']?.replace('{cycleNumber}', '5') ?? 'missing'),
    ).toBeInTheDocument();
    expect(screen.getByTestId('cycle-recap-length')).toHaveTextContent('28 days');
  });

  it('states the usual range and the longer-than-previous comparison', () => {
    renderCard(recap());
    expect(screen.getByTestId('cycle-recap-range')).toHaveTextContent(
      messages['cycleRecapUsualRange']?.replace('{range}', '27\u201330 days') ?? 'missing',
    );
    expect(screen.getByTestId('cycle-recap-comparison')).toHaveTextContent(
      'One day longer than the cycle before it.',
    );
  });

  it('speaks the learning state instead of any estimate', () => {
    renderCard(
      recap({
        hasEstimate: false,
        meanCycleLengthDays: null,
        spreadDays: null,
        confidence: 'learning',
      }),
    );
    expect(screen.getByTestId('cycle-recap-learning')).toHaveTextContent(
      messages['cycleRecapStillLearning'] ?? 'missing',
    );
    expect(screen.queryByTestId('cycle-recap-range')).not.toBeInTheDocument();
  });

  it('suppresses the range and comparison under irregular framing', () => {
    renderCard(recap(), { irregularFraming: true });
    expect(screen.queryByTestId('cycle-recap-range')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cycle-recap-comparison')).not.toBeInTheDocument();
  });

  it('names a tier transition as the one change', () => {
    renderCard(
      recap({
        statisticChange: true,
        tierChanged: true,
        previousConfidence: 'learning',
        confidence: 'high',
      }),
    );
    expect(screen.getByTestId('cycle-recap-statistic-change')).toHaveTextContent(
      messages['cycleRecapEstimatesMoreConfident'] ?? 'missing',
    );
  });

  it('names a displayed-mean shift when no tier moved', () => {
    renderCard(recap({ statisticChange: true, meanCycleShiftDays: 2 }));
    expect(screen.getByTestId('cycle-recap-statistic-change')).toHaveTextContent(
      'Your average cycle length moved by 2 days.',
    );
  });

  it('lists recurring symptoms with their compressed day list', () => {
    renderCard(recap());
    expect(screen.getByTestId('cycle-recap-symptom-cramps')).toHaveTextContent(
      'Cramps: most often around cycle day 2\u20133.',
    );
  });

  it('adds a cramp line only when cramps are not already a recurring symptom', () => {
    renderCard(recap({ recurringSymptoms: [], crampCycleDays: [2, 3] }));
    expect(screen.getByTestId('cycle-recap-cramps')).toHaveTextContent(
      'Cramps most often land around cycle day 2\u20133.',
    );
    cleanup();
    renderCard(recap());
    expect(screen.queryByTestId('cycle-recap-cramps')).not.toBeInTheDocument();
  });

  it('dismisses through the button', () => {
    const onDismiss = vi.fn();
    renderCard(recap(), { onDismiss });
    fireEvent.click(screen.getByRole('button', { name: messages['cycleRecapDismissLabel'] }));
    expect(onDismiss).toHaveBeenCalledTimes(1);
  });

  it('compresses day lists and labels tags the phone way', () => {
    expect(cycleDayList([2, 3])).toBe('2\u20133');
    expect(cycleDayList([1, 3])).toBe('1, 3');
    expect(cycleDayList([])).toBe('');
    expect(recapSymptomLabel('sore_breasts')).toBe('Sore breasts');
  });

  it('renders a single-day range without a span', () => {
    const { result } = renderHook(() => useT(), { wrapper: AppIntlProvider });
    expect(usualRangeText(result.current, 30, 0)).toBe('30 days');
    expect(usualRangeText(result.current, 28.5, 1.5)).toBe('27\u201330 days');
  });
});
