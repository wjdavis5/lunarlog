import { Link } from 'react-router';

import { useT } from '../i18n/t';
import { todayLogLines, type TodayLogCardView } from '../lib/profiles/today-log';

/**
 * The home's "Logged today" card: under the estimate, what is logged for
 * today, in the app's words (the browser version of the app's Today log
 * card, issue #1489). The home used to show the estimate, the calendar and
 * the history, and nothing about the day itself, so a day with cramps
 * logged looked the same as a day with nothing logged.
 *
 * It is handed a view and draws it: who sees a card, and what it may say,
 * are decided before it (`todayLogCardView`, and the compiled domain
 * module behind `readTodayLog`). The view holds labels, counts and facts.
 * It has no note text and no tag code, so nothing this component renders
 * can show either.
 *
 * Edit goes to today's day page, the same place as the button above it.
 * Someone who cannot log gets the summary without it.
 */
export function ProfileHomeTodayLog(props: { view: TodayLogCardView; profileId: string }) {
  const t = useT();
  const { view } = props;

  if (view.kind === 'none') return null;

  if (view.kind === 'empty') {
    return (
      <section className="card" data-testid="today-log-card">
        <p className="card-body" data-testid="today-log-empty">
          {t('todayLogEmpty')}
        </p>
      </section>
    );
  }

  const lines = todayLogLines(view.log, t);
  return (
    <section
      className="card"
      aria-labelledby="home-today-log-title"
      data-testid="today-log-card"
    >
      <div className="home-today-log-head">
        <h2 className="card-title" id="home-today-log-title">
          {t('todayLogTitle')}
        </h2>
        {view.canEdit ? (
          // "Edit" alone does not say what it edits to someone moving from
          // link to link, so the link is described by the card's title.
          <Link
            className="nav-link home-today-log-edit"
            to={`/day/${props.profileId}`}
            aria-describedby="home-today-log-title"
            data-testid="today-log-edit"
          >
            {t('todayLogEdit')}
          </Link>
        ) : null}
      </div>
      <ul className="home-today-log-lines">
        {lines.map((line, index) => (
          // The lines are a fixed sequence (flow, tags, PMS, readings,
          // note) rebuilt whole on every change, so position is identity.
          <li key={index} data-testid={`today-log-line-${index}`}>
            {line}
          </li>
        ))}
      </ul>
    </section>
  );
}
