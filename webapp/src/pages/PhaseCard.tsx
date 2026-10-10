import { useT } from '../i18n/t';
import type { PhaseInsights } from '../domain/schemas';

/**
 * The phase card (issue #1796): the phone's `PhaseInsightsCard`
 * (lib/ui/insights/phase_insights_card.dart). For a statistical prediction
 * it shows the open cycle's current subphase - name, cycle-day range, the
 * typical-cycle explainer, what to track, the hedge when the estimate is
 * uncertain, a link to the literacy article on the site, and the source
 * line. A non-statistical prediction (pack-driven or hormonal, issue #1118)
 * has no ovulatory subphase and gets the basis's own copy instead. Every
 * string is the domain's or the catalogue's; nothing is recomputed here.
 */

const kLearnBase = 'https://lunarlog.app/learn/';

export function PhaseCard(props: { insights: PhaseInsights }) {
  const t = useT();
  const { insights } = props;
  if (insights.basis !== null && insights.basis !== 'statistical') {
    return (
      <section className="card" data-testid="phase-card-regimen">
        <p className="card-body">
          {t(
            insights.basis === 'statisticalOnHormonalMethod'
              ? 'phaseInsightsHormonalNoStartDateBody'
              : 'phaseInsightsHormonalContraceptionBody',
          )}
        </p>
      </section>
    );
  }
  const phase = insights.phase;
  if (phase === null) return null;
  return (
    <section className="card" aria-labelledby="home-phase-title">
      <h2 className="card-title" id="home-phase-title">
        {phase.displayName}
      </h2>
      <p className="card-body" data-testid="phase-range">
        {phase.cycleDayRangeText}
      </p>
      <p className="card-body" data-testid="phase-explainer">
        {t('phaseInsightsTypicalCycleLead')} {phase.biologicalExplainer}
      </p>
      <p className="card-body">
        <strong>{t('phaseInsightsHelpfulToTrack')}</strong>
      </p>
      <p className="card-body" data-testid="phase-tracking">
        {phase.whatToTrack}
      </p>
      {phase.isHedged && phase.hedgedNotice !== null ? (
        <p className="card-body" data-testid="phase-hedged">
          {phase.hedgedNotice}
        </p>
      ) : null}
      {phase.primaryArticleTitle !== null ? (
        <p className="card-body">
          <a
            className="nav-link"
            href={`${kLearnBase}${phase.primaryArticleId}/`}
            rel="noreferrer noopener"
            data-testid="phase-article"
          >
            {t('phaseInsightsReadArticle', { title: phase.primaryArticleTitle })}
          </a>
        </p>
      ) : null}
      <p className="card-body" data-testid="phase-source">
        {t('phaseInsightsSource', { source: phase.source, date: phase.reviewDate })}
      </p>
    </section>
  );
}
