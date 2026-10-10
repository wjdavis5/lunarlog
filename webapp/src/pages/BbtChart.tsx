import { useT } from '../i18n/t';
import type { BbtChart as BbtChartData } from '../domain/schemas';
import { bbtUnitSymbol, convertTemperature, type BbtUnit } from '../lib/day/measurements';

/**
 * The BBT chart (issue #1796): the phone's chart, drawn from the drawable
 * form the domain sends - per-point x/y fractions, per-series overlay
 * opacity, and the Celsius range for the caption (see `bbtChartSchema`).
 * The SVG only maps fractions to pixels; no geometry is recomputed here.
 * The caption converts that canonical Celsius range to the profile's own
 * `bbt_unit` at render time (issue #1820), the same read-time-only rule
 * the phone's `_captionFor` applies.
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

/** One caption bound, converted from the response's Celsius to [unit]. */
function formatTemperature(valueCelsius: number, unit: BbtUnit): string {
  return `${convertTemperature(valueCelsius, 'celsius', unit).toFixed(1)}${bbtUnitSymbol(unit)}`;
}

export function BbtChart(props: { chart: BbtChartData; unit: BbtUnit }) {
  const t = useT();
  const { chart, unit } = props;
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
  const range = `${formatTemperature(chart.minCelsius, unit)}-${formatTemperature(chart.maxCelsius, unit)}`;
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
