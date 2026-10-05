import { useT, type TFunction } from '../i18n/t';
import { DOT_SEPARATOR, LABEL_COLON } from '../i18n/punctuation';
import type { CycleHistoryView } from '../domain/schemas';

/**
 * The web home's cycle history and comparison (issue #1253): the history
 * list and statistics the app's cycle-history section renders (open cycle
 * pinned first, outlier/omitted badges, the averages), plus a compact
 * side-by-side of the two most recent completed cycles — the app's
 * cycle-comparison screen's length and bleed-day rows, computed from the
 * same domain view. All copy rides the ARB catalogue.
 */

const kLocale = 'en';

const kDateFormat = new Intl.DateTimeFormat(kLocale, { dateStyle: 'medium', timeZone: 'UTC' });

function formatDate(iso: string): string {
  return kDateFormat.format(new Date(`${iso}T00:00:00Z`));
}

/** The closed cycles, newest first (the open cycle is excluded). */
function closedCycles(view: CycleHistoryView) {
  return view.items.filter((item) => !item.open);
}

/**
 * A possibly fractional day count with its unit, as the app writes it
 * (`formatDays`, lib/ui/overview/cycle_history_section.dart): a whole
 * number bare, anything else to one decimal, and "day" or "days" chosen
 * from the number itself. The page used to print the bare number, so
 * "Variation 0" did not say what it was counting, and it rounded an
 * average of 28.5 to 29 where the app shows 28.5.
 */
export function formatDays(t: TFunction, value: number): string {
  const display = Number.isInteger(value) ? String(value) : value.toFixed(1);
  return t('daysValue', { count: value, value: display });
}

/** One comparison row: "Length: 28 days · Bleed days: 5 days", entirely catalogue-sourced. */
export function compareRow(
  t: TFunction,
  lengthDays: number | null,
  bleedDays: number | null,
): string {
  const length =
    lengthDays !== null ? formatDays(t, lengthDays) : t('cycleComparisonOngoingLabel');
  const bleed = bleedDays !== null ? t('daysCount', { count: bleedDays }) : '—';
  return [
    `${t('cycleComparisonLengthLabel')}${LABEL_COLON}${length}`,
    `${t('cycleComparisonBleedDaysLabel')}${LABEL_COLON}${bleed}`,
  ].join(DOT_SEPARATOR);
}

export function ProfileHomeHistory(props: { history: CycleHistoryView }) {
  const t = useT();
  const view = props.history;
  return (
    <section className="card" aria-labelledby="home-history-title">
      <h2 className="card-title" id="home-history-title">
        {t('cycleHistoryTitle')}
      </h2>
      {view.meanCycleLengthDays !== null || view.meanPeriodLengthDays !== null ? (
        <dl className="home-stats">
          <div>
            <dt>{t('cycleHistoryAvgCycle')}</dt>
            <dd data-testid="stat-avg-cycle">
              {view.meanCycleLengthDays !== null
                ? formatDays(t, view.meanCycleLengthDays)
                : '—'}
            </dd>
          </div>
          <div>
            <dt>{t('cycleHistoryAvgPeriod')}</dt>
            <dd data-testid="stat-avg-period">
              {view.meanPeriodLengthDays !== null
                ? formatDays(t, view.meanPeriodLengthDays)
                : '—'}
            </dd>
          </div>
          <div>
            <dt>{t('cycleHistoryVariation')}</dt>
            <dd data-testid="stat-variation">
              {view.variationDays !== null
                ? t('daysCount', { count: view.variationDays })
                : '—'}
            </dd>
          </div>
        </dl>
      ) : null}
      {view.items.length === 0 ? (
        <p className="card-body">{t('calendarKeepLogging')}</p>
      ) : (
        <ul className="home-history" data-testid="cycle-history-list">
          {view.items.map((item) => (
            <li key={item.start}>
              {item.open ? (
                <span>
                  {t('cycleHistoryCurrentCycleStarted', { date: formatDate(item.start) })}
                </span>
              ) : (
                <span>
                  {t('webHomeCycleStartedLength', {
                    startedDate: formatDate(item.start),
                    length: item.lengthDays ?? 0,
                  })}
                </span>
              )}
              {item.outlier ? <span className="badge">{t('cycleHistoryOutlier')}</span> : null}
              {item.omitted ? (
                <span className="badge">{t('cycleHistorySkippedExcluded')}</span>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export function ProfileHomeComparison(props: { history: CycleHistoryView }) {
  const t = useT();
  const closed = closedCycles(props.history);
  // With fewer than two completed cycles there is nothing to compare, so
  // there is no card. The app's empty state for this ("Select two cycles
  // from your cycle history...") describes a picker this page does not
  // have: here the two newest cycles are compared automatically.
  if (closed.length < 2) return null;
  const [newest, previous] = closed;
  const lengthDiff =
    newest.lengthDays !== null && previous.lengthDays !== null
      ? Math.abs(newest.lengthDays - previous.lengthDays)
      : null;
  const bleedDiff =
    newest.bleedDays !== null && previous.bleedDays !== null
      ? Math.abs(newest.bleedDays - previous.bleedDays)
      : null;
  return (
    <section className="card" aria-labelledby="home-compare-title">
      <h2 className="card-title" id="home-compare-title">
        {t('cycleComparisonScreenTitle')}
      </h2>
      <dl className="home-compare">
        <div>
          <dt>{t('cycleComparisonSideHeading', { date: formatDate(newest.start) })}</dt>
          <dd>{compareRow(t, newest.lengthDays, newest.bleedDays)}</dd>
        </div>
        <div>
          <dt>{t('cycleComparisonSideHeading', { date: formatDate(previous.start) })}</dt>
          <dd>{compareRow(t, previous.lengthDays, previous.bleedDays)}</dd>
        </div>
        <div>
          <dt>{t('cycleComparisonLengthDifferenceLabel')}</dt>
          <dd data-testid="compare-length-diff">
            {lengthDiff !== null
              ? t('daysCount', { count: lengthDiff })
              : t('cycleComparisonLengthDifferenceUnknown')}
          </dd>
        </div>
        <div>
          <dt>{t('cycleComparisonBleedDaysDifferenceLabel')}</dt>
          <dd data-testid="compare-bleed-diff">
            {bleedDiff !== null
              ? t('daysCount', { count: bleedDiff })
              : t('cycleComparisonLengthDifferenceUnknown')}
          </dd>
        </div>
      </dl>
    </section>
  );
}
