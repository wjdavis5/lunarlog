import { useT, type TFunction } from '../i18n/t';
import type { CycleRecap } from '../domain/schemas';
import { formatDays } from './ProfileHomeHistory';

/**
 * The cycle-end recap card (issue #1796): the phone's `CycleRecapCard`
 * (lib/ui/insights/cycle_recap_card.dart) minus its compare action, whose
 * web equivalent is the comparison already shown on this page. Every fact is
 * the domain's own; the copy is composed from the catalogue exactly as the
 * phone composes it, and the irregular-framing rule suppresses the range and
 * comparison lines the same way. The web keeps no seen-cycle record, so the
 * dismiss is session-scoped (see `lib/recap-dismiss.ts`).
 */

/** The phone's day-list compression: "1-2" for a consecutive run, else "1, 3". */
export function cycleDayList(days: number[]): string {
  if (days.length === 0) return '';
  const sorted = [...days].sort((a, b) => a - b);
  let consecutive = true;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i] !== sorted[i - 1] + 1) {
      consecutive = false;
      break;
    }
  }
  if (sorted.length > 1 && consecutive) {
    return `${sorted[0]}\u2013${sorted[sorted.length - 1]}`;
  }
  return sorted.join(', ');
}

/** The phone's tag treatment (the symptom-trends section uses the same one). */
export function recapSymptomLabel(tag: string): string {
  const words = tag.replaceAll('_', ' ').trim();
  return words.length === 0 ? words : words[0].toUpperCase() + words.slice(1);
}

/** "27-31 days", or a single "30 days" when the spread rounds to zero. */
export function usualRangeText(t: TFunction, mean: number, spread: number): string {
  const low = Math.round(mean - spread);
  const high = Math.round(mean + spread);
  if (low >= high) return formatDays(t, mean);
  return t('daysValue', { count: high, value: `${low}\u2013${high}` });
}

function comparisonText(t: TFunction, recap: CycleRecap): string | null {
  const delta = recap.lengthChangeDays;
  if (delta === null) return null;
  if (delta > 0) return t('cycleRecapLongerThanPrevious', { days: delta });
  if (delta < 0) return t('cycleRecapShorterThanPrevious', { days: -delta });
  return t('cycleRecapSameAsPrevious');
}

/**
 * A tier transition first (the plainest "the record got smarter" fact),
 * otherwise a displayed-mean shift the change thresholds already judged
 * meaningful. Never both, so the card states one change at most.
 */
function statisticChangeText(t: TFunction, recap: CycleRecap): string | null {
  if (!recap.statisticChange) return null;
  if (recap.tierChanged) {
    const order = ['high', 'learning', 'irregular', 'provisional'] as const;
    const previous = recap.previousConfidence;
    const moreConfident =
      previous !== null && order.indexOf(recap.confidence) < order.indexOf(previous);
    return moreConfident
      ? t('cycleRecapEstimatesMoreConfident')
      : t('cycleRecapEstimatesLessConfident');
  }
  const shift = recap.meanCycleShiftDays;
  if (shift === null || shift === 0) return null;
  return t('cycleRecapAverageMoved', { days: formatDays(t, Math.abs(shift)) });
}

export function RecapCard(props: {
  recap: CycleRecap;
  irregularFraming: boolean;
  onDismiss: () => void;
}) {
  const t = useT();
  const { recap } = props;
  const suppressComparison = props.irregularFraming || recap.lengthChangeDays === null;
  const range =
    recap.meanCycleLengthDays !== null && recap.spreadDays !== null
      ? usualRangeText(t, recap.meanCycleLengthDays, recap.spreadDays)
      : null;
  const comparison = suppressComparison ? null : comparisonText(t, recap);
  const change = statisticChangeText(t, recap);
  const hasCrampLine =
    recap.crampCycleDays !== null &&
    !recap.recurringSymptoms.some((symptom) => symptom.tag === 'cramps');
  return (
    <section className="card" aria-labelledby="home-recap-title" data-testid="cycle-recap-card">
      <h2 className="card-title" id="home-recap-title">
        {t('cycleRecapTitle', { cycleNumber: recap.cycleNumber })}
      </h2>
      <p className="card-body" data-testid="cycle-recap-length">
        {t('cycleRecapLength', { days: formatDays(t, recap.cycleLengthDays) })}
      </p>
      {!recap.hasEstimate ? (
        <p className="card-body" data-testid="cycle-recap-learning">
          {t('cycleRecapStillLearning')}
        </p>
      ) : null}
      {range !== null && !suppressComparison ? (
        <p className="card-body" data-testid="cycle-recap-range">
          {t('cycleRecapUsualRange', { range })}
        </p>
      ) : null}
      {comparison !== null ? (
        <p className="card-body" data-testid="cycle-recap-comparison">
          {comparison}
        </p>
      ) : null}
      {change !== null ? (
        <p className="card-body" data-testid="cycle-recap-statistic-change">
          {change}
        </p>
      ) : null}
      {recap.recurringSymptoms.map((symptom) => (
        <p
          className="card-body"
          key={symptom.tag}
          data-testid={`cycle-recap-symptom-${symptom.tag}`}
        >
          {t('cycleRecapRecurringSymptom', {
            symptom: recapSymptomLabel(symptom.tag),
            days: cycleDayList(symptom.cycleDays),
          })}
        </p>
      ))}
      {hasCrampLine ? (
        <p className="card-body" data-testid="cycle-recap-cramps">
          {t('cycleRecapCrampDays', { days: cycleDayList(recap.crampCycleDays ?? []) })}
        </p>
      ) : null}
      <p className="card-body">
        <button className="btn" type="button" onClick={props.onDismiss}>
          {t('cycleRecapDismissLabel')}
        </button>
      </p>
    </section>
  );
}
