import { useT } from '../i18n/t';
import { LABEL_COLON, LIST_SEPARATOR } from '../i18n/punctuation';
import type { InsightsReport } from '../domain/schemas';

/**
 * Symptom trends on the web (issue #1796): the anticipated cramp window, the
 * recurring symptom patterns with their trend and timing, and the typical
 * bleed rhythm. It mirrors the phone's `SymptomTrendsSection`
 * (lib/ui/insights/symptom_trends_section.dart) minus the literacy-library
 * card, whose web equivalent is the site's guides. Every number and every
 * display string is the compiled domain module's own output (see
 * `insightsReportSchema`); nothing is recomputed here.
 */

const kCrampDateFormat = new Intl.DateTimeFormat('en', {
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
});

function formatCrampDates(isoDates: string[]): string {
  return isoDates
    .map((iso) => kCrampDateFormat.format(new Date(`${iso}T00:00:00Z`)))
    .join(LIST_SEPARATOR);
}

/** The phone's tag treatment: underscores to spaces, first letter up. */
export function symptomTagLabel(tag: string): string {
  const spaced = tag.replaceAll('_', ' ');
  return spaced.length === 0 ? spaced : spaced[0].toUpperCase() + spaced.slice(1);
}

export function ProfileHomeInsights(props: { report: InsightsReport }) {
  const t = useT();
  const { report } = props;
  return (
    <section className="card" aria-labelledby="home-insights-title">
      <h2 className="card-title" id="home-insights-title">
        {t('symptomTrendsTitle')}
      </h2>

      {report.crampPrediction !== null ? (
        <div data-testid="cramp-prediction">
          <p className="card-body">
            <strong>{t('crampPredictionTitle')}</strong>
          </p>
          <p className="card-body" data-testid="cramp-summary">
            {report.crampPrediction.summaryText}
          </p>
          {report.crampPrediction.predictedDates.length > 0 ? (
            <p className="card-body" data-testid="cramp-dates">
              {t('crampPredictionDates', {
                dates: formatCrampDates(report.crampPrediction.predictedDates),
              })}
            </p>
          ) : null}
          <p className="card-body" data-testid="cramp-observed">
            {t('crampPredictionObserved', {
              observed: report.crampPrediction.observedCycleCount,
              total: report.crampPrediction.totalCyclesAnalyzed,
            })}
          </p>
          <p className="card-body" data-testid="cramp-disclaimer">
            {report.crampPrediction.disclaimer}
          </p>
        </div>
      ) : null}

      <div data-testid="symptom-patterns">
        <p className="card-body">
          <strong>{t('symptomTrendsRecurring')}</strong>
        </p>
        {!report.hasEnoughData || report.symptomPatterns.length === 0 ? (
          <p className="card-body" data-testid="symptom-patterns-empty">
            {t('symptomTrendsEmpty')}
          </p>
        ) : (
          <>
            <ul className="home-history" data-testid="symptom-patterns-list">
              {report.symptomPatterns.map((pattern) => (
                <li key={pattern.tag}>
                  <span>
                    <strong>{symptomTagLabel(pattern.tag)}</strong>
                    {LIST_SEPARATOR}
                    {pattern.trendDisplayName}
                  </span>
                  <span className="badge">{pattern.timingSummary}</span>
                  <span>
                    {t('symptomTrendsLogged', {
                      occurrences: pattern.totalOccurrences,
                      cycles: pattern.cycleCount,
                    })}
                  </span>
                </li>
              ))}
            </ul>
            <p className="card-body" data-testid="symptom-patterns-disclaimer">
              {t('symptomTrendsDisclaimer')}
            </p>
          </>
        )}
      </div>

      {report.flowPattern !== null ? (
        <p className="card-body" data-testid="flow-pattern">
          <strong>{t('symptomTrendsFlowTitle')}</strong>
          {LABEL_COLON}
          {t('symptomTrendsFlowSubtitle', {
            day: report.flowPattern.typicalPeakDay,
            flow: report.flowPattern.typicalPeakFlow,
          })}
        </p>
      ) : null}
    </section>
  );
}
