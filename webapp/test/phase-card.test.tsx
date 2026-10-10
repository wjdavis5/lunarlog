import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { PhaseInsights } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { PhaseCard } from '../src/pages/PhaseCard';

/**
 * The phase card (issue #1796). Every string is the domain's or the
 * catalogue's; these cases pin the composition, the hedge, the article link,
 * and the non-statistical branch.
 */

function insights(overrides: Partial<PhaseInsights> = {}): PhaseInsights {
  return {
    phase: {
      subphase: 'late_luteal',
      displayName: 'Late Luteal (Premenstrual)',
      hormonalSummary:
        'Progesterone and estrogen fall if no pregnancy occurs, which leads to a period.',
      whatToTrack: 'Cramps, sleep quality, irritability, backache, and spotting.',
      primaryArticleId: 'why-cramps-happen',
      primaryArticleTitle: 'Why Cramps Happen',
      cycleDay: 29,
      startCycleDay: 25,
      endCycleDay: 29,
      cycleDayRangeText: 'Cycle Days 25-29',
      startDate: '2026-09-26',
      endDate: '2026-09-30',
      isHedged: false,
      hedgedNotice: null,
      biologicalExplainer:
        'Progesterone and estrogen fall if no pregnancy occurs, which leads to a period.',
      source: 'ACOG Menstrual Cycle infographic (PFSI033); ACOG FAQ024',
      reviewDate: '2026-09-26',
    },
    basis: 'statistical',
    ...overrides,
  };
}

function renderCard(value: PhaseInsights) {
  return render(
    <AppIntlProvider>
      <PhaseCard insights={value} />
    </AppIntlProvider>,
  );
}

describe('PhaseCard (issue #1796)', () => {
  afterEach(() => {
    cleanup();
  });

  it('names the subphase and its cycle-day range', () => {
    renderCard(insights());
    expect(
      screen.getByRole('heading', { name: 'Late Luteal (Premenstrual)' }),
    ).toBeInTheDocument();
    expect(screen.getByTestId('phase-range')).toHaveTextContent('Cycle Days 25-29');
  });

  it('leads the explainer with the typical-cycle framing', () => {
    renderCard(insights());
    expect(screen.getByTestId('phase-explainer')).toHaveTextContent(
      messages['phaseInsightsTypicalCycleLead'] ?? 'missing',
    );
    expect(screen.getByTestId('phase-explainer')).toHaveTextContent(
      'Progesterone and estrogen fall if no pregnancy occurs',
    );
  });

  it('labels what to track and the source line', () => {
    renderCard(insights());
    expect(screen.getByTestId('phase-tracking')).toHaveTextContent('Cramps, sleep quality');
    expect(
      screen.getByText(messages['phaseInsightsHelpfulToTrack'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(screen.getByTestId('phase-source')).toHaveTextContent('ACOG Menstrual Cycle');
    expect(screen.getByTestId('phase-source')).toHaveTextContent('2026-09-26');
  });

  it('links the article by its title', () => {
    renderCard(insights());
    const link = screen.getByTestId('phase-article');
    expect(link).toHaveAttribute('href', 'https://lunarlog.app/learn/why-cramps-happen/');
    expect(link).toHaveTextContent(
      messages['phaseInsightsReadArticle']?.replace('{title}', 'Why Cramps Happen') ??
        'missing',
    );
  });

  it('shows the hedge only when the estimate is hedged', () => {
    renderCard(insights());
    expect(screen.queryByTestId('phase-hedged')).not.toBeInTheDocument();
    cleanup();
    renderCard(
      insights({
        phase: {
          ...insights().phase!,
          isHedged: true,
          hedgedNotice: 'This is a statistical estimate, not a certainty.',
        },
      }),
    );
    expect(screen.getByTestId('phase-hedged')).toHaveTextContent(
      'This is a statistical estimate, not a certainty.',
    );
  });

  it('renders the pack-driven copy instead of a subphase', () => {
    renderCard(insights({ phase: null, basis: 'packDriven' }));
    expect(screen.getByTestId('phase-card-regimen')).toHaveTextContent(
      messages['phaseInsightsHormonalContraceptionBody'] ?? 'missing',
    );
  });

  it('renders the no-start-date copy for the hormonal method without one', () => {
    renderCard(insights({ phase: null, basis: 'statisticalOnHormonalMethod' }));
    expect(screen.getByTestId('phase-card-regimen')).toHaveTextContent(
      messages['phaseInsightsHormonalNoStartDateBody'] ?? 'missing',
    );
  });

  it('draws nothing without an active prediction', () => {
    const { container } = renderCard(insights({ phase: null, basis: null }));
    expect(container).toBeEmptyDOMElement();
  });
});
