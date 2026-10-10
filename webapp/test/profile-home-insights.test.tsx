import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { InsightsReport } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { ProfileHomeInsights, symptomTagLabel } from '../src/pages/ProfileHomeInsights';

/**
 * The home's symptom trends (issue #1796). The report shape is the one the
 * compiled domain module answers with (the `insights` parity fixtures); the
 * display strings inside it are the phone's own, so the section renders them
 * rather than recomputing anything.
 */

function report(overrides: Partial<InsightsReport> = {}): InsightsReport {
  return {
    symptomPatterns: [
      {
        tag: 'cramps',
        totalOccurrences: 6,
        cycleCount: 4,
        frequencyByCycleDay: { '2': 4, '3': 2 },
        peakCycleDays: [2, 3],
        trend: 'stable',
        trendDisplayName: 'Consistent',
        timingSummary: 'Most common on Cycle Days 2, 3',
        meetsThreshold: true,
      },
    ],
    flowPattern: {
      flowByCycleDay: { '1': { medium: 4 } },
      typicalPeakFlow: 'medium',
      typicalPeakDay: 1,
    },
    crampPrediction: {
      predictedCycleDays: [2, 3],
      predictedDates: ['2026-10-01', '2026-10-02'],
      observedCycleCount: 4,
      totalCyclesAnalyzed: 4,
      summaryText: 'Likely on Cycle Days 2, 3',
      disclaimer:
        'Cramp estimates are based on your past logged tags, not medical diagnosis. ' +
        'Individual cycle timing and physical sensations may naturally vary.',
    },
    analyzedCycleCount: 4,
    hasEnoughData: true,
    ...overrides,
  };
}

function renderInsights(value: InsightsReport) {
  return render(
    <AppIntlProvider>
      <ProfileHomeInsights report={value} />
    </AppIntlProvider>,
  );
}

describe('ProfileHomeInsights (issue #1796)', () => {
  afterEach(() => {
    cleanup();
  });

  it('renders the cramp window from the domain strings', () => {
    renderInsights(report());
    expect(screen.getByTestId('cramp-summary')).toHaveTextContent('Likely on Cycle Days 2, 3');
    expect(screen.getByTestId('cramp-dates')).toHaveTextContent(
      messages['crampPredictionDates']?.replace('{dates}', 'Oct 1, Oct 2') ?? 'missing',
    );
    expect(screen.getByTestId('cramp-observed')).toHaveTextContent(
      messages['crampPredictionObserved']?.replace('{observed}', '4').replace('{total}', '4') ??
        'missing',
    );
    expect(screen.getByTestId('cramp-disclaimer')).toHaveTextContent(
      'Cramp estimates are based on your past logged tags',
    );
  });

  it('renders each pattern with its trend, timing, and counts', () => {
    renderInsights(report());
    const list = screen.getByTestId('symptom-patterns-list');
    expect(list).toHaveTextContent('Cramps');
    expect(list).toHaveTextContent('Consistent');
    expect(list).toHaveTextContent('Most common on Cycle Days 2, 3');
    expect(list).toHaveTextContent(
      messages['symptomTrendsLogged']?.replace('{occurrences}', '6').replace('{cycles}', '4') ??
        'missing',
    );
  });

  it('shows the empty state without enough data', () => {
    renderInsights(report({ symptomPatterns: [], hasEnoughData: false }));
    expect(screen.getByTestId('symptom-patterns-empty')).toHaveTextContent(
      messages['symptomTrendsEmpty'] ?? 'missing',
    );
    expect(screen.queryByTestId('symptom-patterns-list')).not.toBeInTheDocument();
  });

  it('draws no cramp or flow block when the report carries neither', () => {
    renderInsights(report({ crampPrediction: null, flowPattern: null }));
    expect(screen.queryByTestId('cramp-prediction')).not.toBeInTheDocument();
    expect(screen.queryByTestId('flow-pattern')).not.toBeInTheDocument();
  });

  it('renders the flow rhythm from the domain values', () => {
    renderInsights(report());
    expect(screen.getByTestId('flow-pattern')).toHaveTextContent(
      messages['symptomTrendsFlowSubtitle']
        ?.replace('{day}', '1')
        .replace('{flow}', 'Medium') ?? 'missing',
    );
  });

  // Issue #1822: the level arrives as its wire code and is labeled from the
  // flow catalogue, never printed raw ("superHeavy").
  it('labels the peak flow level instead of printing its wire code', () => {
    renderInsights(
      report({
        flowPattern: {
          flowByCycleDay: { '2': { super_heavy: 3 } },
          typicalPeakFlow: 'super_heavy',
          typicalPeakDay: 2,
        },
      }),
    );
    expect(screen.getByTestId('flow-pattern')).toHaveTextContent(
      messages['symptomTrendsFlowSubtitle']
        ?.replace('{day}', '2')
        .replace('{flow}', 'Super heavy') ?? 'missing',
    );
    expect(screen.getByTestId('flow-pattern')).not.toHaveTextContent('super_heavy');
  });

  it('turns a tag code into the phone label treatment', () => {
    expect(symptomTagLabel('cramps')).toBe('Cramps');
    expect(symptomTagLabel('sore_breasts')).toBe('Sore breasts');
    expect(symptomTagLabel('')).toBe('');
  });
});
