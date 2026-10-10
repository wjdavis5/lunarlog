import { useT } from '../i18n/t';
import type { BbtChart as BbtChartData } from '../domain/schemas';

/**
 * The BBT chart (issue #1796): the phone's chart, drawn from the drawable
 * form the domain sends - per-point x/y fractions, per-series overlay
 * opacity, and the Celsius range for the caption (see `bbtChartSchema`).
 * The SVG only maps fractions to pixels; no geometry is recomputed here.
 * The caption reads in Celsius, the canonical unit the response carries
 * (the phone converts to the profile's display unit; the web profile has no
 * BBT unit setting of its own yet).
 */

const kViewBoxWidth = 320;
const kViewBoxHeight = 200;
/** Space inside the viewBox so a point at fraction 0 or 1 stays visible. */
const kInset = 8;

function xPixels(fraction: number): number {
  return kInset + fraction * (kViewBoxWidth - 2 * kInset);
}

function yPixels(fraction: number): number {
  // SVG y grows downward; the domain's yFraction is 0 at the range's low end.
  return kInset + (1 - fraction) * (kViewBoxHeight - 2 * kInset);
}

function formatCelsius(value: number): string {
  return `${value.toFixed(1)}\u00B0C`;
}

export function BbtChart(props: { chart: BbtChartData }) {
  const t = useT();
  const { chart } = props;
  if (chart.isEmpty) {
    return (
      <section className="card" aria-labelledby="home-bbt-title">
        <h2 className="card-title" id="home-bbt-title">
          {t('bbtChartEmptyTitle')}
        </h2>
        <p className="card-body" data-testid="bbt-chart-empty">
          {t('bbtChartEmptyBody')}
        </p>
      </section>
    );
  }
  const range = `${formatCelsius(chart.minCelsius)}-${formatCelsius(chart.maxCelsius)}`;
  return (
    <section className="card" aria-labelledby="home-bbt-title">
      <h2 className="card-title" id="home-bbt-title">
        {t('analysisBbtChartTitle')}
      </h2>
      <svg
        className="home-bbt-chart"
        data-testid="bbt-chart-svg"
        viewBox={`0 0 ${kViewBoxWidth} ${kViewBoxHeight}`}
        role="img"
        aria-label={t('analysisBbtChartTitle')}
      >
        {chart.series.map((series, index) => (
          <g key={series.cycleStart}>
            <polyline
              data-testid={`bbt-series-${index}`}
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeOpacity={series.opacity}
              points={series.points
                .map((point) => `${xPixels(point.xFraction)},${yPixels(point.yFraction)}`)
                .join(' ')}
            />
            {series.points.map((point) => (
              <circle
                key={`${point.date}-${point.cycleDay}`}
                cx={xPixels(point.xFraction)}
                cy={yPixels(point.yFraction)}
                r="2.5"
                fill="currentColor"
                fillOpacity={series.opacity}
              />
            ))}
          </g>
        ))}
      </svg>
      <p className="card-body" data-testid="bbt-chart-caption">
        {t('bbtChartCaption', { count: chart.series.length, range })}
      </p>
    </section>
  );
}
