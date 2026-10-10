import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import type { BbtChart as BbtChartData } from '../src/domain/schemas';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import type { BbtUnit } from '../src/lib/day/measurements';
import { BbtChart } from '../src/pages/BbtChart';

/**
 * The BBT chart (issue #1796). The component maps the domain's fractions to
 * pixels and formats the caption; these cases pin that mapping and the copy,
 * not any geometry the domain computes.
 */

function chart(overrides: Partial<BbtChartData> = {}): BbtChartData {
  return {
    series: [
      {
        cycleStart: '2026-09-01',
        opacity: 1,
        points: [
          {
            cycleDay: 1,
            celsius: 36.4,
            date: '2026-09-01',
            xFraction: 0,
            yFraction: 0,
          },
          {
            cycleDay: 2,
            celsius: 36.6,
            date: '2026-09-02',
            xFraction: 1,
            yFraction: 1,
          },
        ],
      },
    ],
    maxCycleDay: 2,
    minCelsius: 36.1,
    maxCelsius: 36.9,
    isEmpty: false,
    ...overrides,
  };
}

function renderChart(value: BbtChartData, unit: BbtUnit = 'celsius') {
  return render(
    <AppIntlProvider>
      <BbtChart chart={value} unit={unit} />
    </AppIntlProvider>,
  );
}

describe('BbtChart (issue #1796)', () => {
  afterEach(() => {
    cleanup();
  });

  it('maps the domain fractions to SVG coordinates', () => {
    renderChart(chart());
    // Fraction (0, 0) -> (8, 192) and (1, 1) -> (312, 8): the viewBox inset,
    // with y inverted because SVG y grows downward.
    expect(screen.getByTestId('bbt-series-0')).toHaveAttribute('points', '8,192 312,8');
  });

  it('carries each series opacity onto its line', () => {
    renderChart(chart({ series: [{ ...chart().series[0], opacity: 0.35 }] }));
    expect(screen.getByTestId('bbt-series-0')).toHaveAttribute('stroke-opacity', '0.35');
  });

  it('captions the cycle count and the Celsius range', () => {
    renderChart(chart());
    const caption = screen.getByTestId('bbt-chart-caption');
    expect(caption).toHaveTextContent('1 cycle shown');
    expect(caption).toHaveTextContent('36.1\u00B0C-36.9\u00B0C');
  });

  // Issue #1820: the caption converts the response's canonical Celsius
  // range to the profile's own bbt_unit, as the phone's _captionFor does.
  it("captions the range in the profile's own unit", () => {
    renderChart(chart(), 'fahrenheit');
    expect(screen.getByTestId('bbt-chart-caption')).toHaveTextContent(
      '97.0\u00B0F-98.4\u00B0F',
    );
  });

  it('pluralizes the caption for several cycles', () => {
    renderChart(
      chart({
        series: [chart().series[0], { ...chart().series[0], cycleStart: '2026-08-01' }],
      }),
    );
    expect(screen.getByTestId('bbt-chart-caption')).toHaveTextContent('2 cycles shown');
  });

  it('shows the empty state when the chart carries nothing', () => {
    renderChart(chart({ series: [], isEmpty: true }));
    expect(screen.getByText(messages['bbtChartEmptyTitle'] ?? 'missing')).toBeInTheDocument();
    expect(screen.queryByTestId('bbt-chart-svg')).not.toBeInTheDocument();
  });
});
