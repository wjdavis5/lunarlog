import { useState } from 'react';
import { Link } from 'react-router';

import { useT } from '../i18n/t';
import { DASH_SEPARATOR } from '../i18n/punctuation';
import type { ForecastDayCell } from '../domain/schemas';
import type { DayEntryRow } from '../lib/schemas';
import { taxonomy } from '../lib/day/categories';
import {
  canNavigateForward,
  dayCellView,
  defaultLayerTags,
  leadingBlanksFor,
  monthDayIsos,
  shiftMonth,
  toggledLayers,
  weekdayInitials,
} from '../lib/profiles/calendar-cells';

/**
 * The web month calendar (issue #1253): the app's month grid — Sunday
 * first, flow marks by level, the spotting ring, today's ring, symptom
 * layer dots, the predicted-period band, fertile windows, PMS/cramps
 * badges, and the first estimated cycle's day numerals — with the same
 * legend and symptom-layer chooser the app's CalendarLegendSheet /
 * CalendarLayersSheet carry. The forecast decoration is never computed
 * here: it is the domain facade's `calendarForecast` output, so both
 * clients paint the same math.
 */

const kLocale = 'en';

const kCellDateFormat = new Intl.DateTimeFormat(kLocale, {
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
});

/** The layer-dot CSS class for a hit's palette slot (the app's fixed order). */
function layerDotClass(index: number): string {
  return `cal-dot cal-dot-${index + 1}`;
}

function LegendSwatch(props: { kind: string; extraClass?: string }) {
  return (
    <span
      className={`cal-swatch cal-swatch-${props.kind} ${props.extraClass ?? ''}`}
      aria-hidden="true"
    />
  );
}

export function ProfileHomeCalendar(props: {
  todayIso: string;
  profileId: string;
  /** Live entries for the visible profile, keyed by local date. */
  entryByIso: Map<string, DayEntryRow>;
  /** The domain facade's per-date forecast cells. */
  forecastByIso: Map<string, ForecastDayCell>;
  /** Whether the estimate carries a PMS band (the legend keys off it). */
  pmsBandActive: boolean;
  /** Whether the fertile layer renders at all (the composed framing hides it). */
  fertileShown: boolean;
}) {
  const t = useT();
  const [now] = useState(() => new Date(`${props.todayIso}T00:00:00`));
  const [displayed, setDisplayed] = useState(() => ({
    year: now.getFullYear(),
    month: now.getMonth() + 1,
  }));
  // The default layer selection recomputes from the visible entries until
  // the operator first toggles a layer (the app's `_layersUserSet` rule);
  // the selection itself is page memory only.
  const [userLayers, setUserLayers] = useState<string[] | null>(null);
  const [layerLimitHit, setLayerLimitHit] = useState(false);
  const allEntries = [...props.entryByIso.values()];
  const activeLayers = userLayers ?? defaultLayerTags(allEntries);

  const toggleLayer = (code: string) => {
    setLayerLimitHit(false);
    const next = toggledLayers(activeLayers, code);
    if (next === null) {
      setLayerLimitHit(true);
      return;
    }
    setUserLayers(next);
  };

  const monthLabel = t('calendarMonthYearLabel', {
    month: new Intl.DateTimeFormat(kLocale, { month: 'long', timeZone: 'UTC' }).format(
      new Date(Date.UTC(displayed.year, displayed.month - 1, 1)),
    ),
    year: displayed.year,
  });
  const days = monthDayIsos(displayed.year, displayed.month);
  const blanks = leadingBlanksFor(displayed.year, displayed.month);
  const monthHasEntries = days.some((iso) => props.entryByIso.has(iso));

  return (
    <section className="card" aria-labelledby="home-calendar-title">
      <div className="cal-nav">
        <h2 className="card-title" id="home-calendar-title">
          {monthLabel}
        </h2>
        <div className="cal-nav-buttons">
          <button
            type="button"
            className="btn"
            onClick={() => setDisplayed((m) => shiftMonth(m.year, m.month, -1))}
          >
            {t('calendarPreviousMonthTooltip')}
          </button>
          <button
            type="button"
            className="btn"
            onClick={() => setDisplayed({ year: now.getFullYear(), month: now.getMonth() + 1 })}
          >
            {t('calendarTodayTooltip')}
          </button>
          <button
            type="button"
            className="btn"
            disabled={!canNavigateForward(displayed.year, displayed.month, now)}
            onClick={() => setDisplayed((m) => shiftMonth(m.year, m.month, 1))}
          >
            {t('calendarNextMonthTooltip')}
          </button>
        </div>
      </div>

      {!monthHasEntries ? (
        <p className="card-body" data-testid="calendar-empty-banner">
          {t('calendarNoEntriesTitle')}
          {DASH_SEPARATOR}
          {t('calendarNoEntriesBody')}
        </p>
      ) : null}

      <div className="cal-grid" role="grid" aria-label={monthLabel}>
        <div role="row" className="cal-row cal-head">
          {weekdayInitials(kLocale).map((initial, i) => (
            <span role="columnheader" key={`${initial}-${i}`} className="cal-cell cal-weekday">
              {initial}
              <span className="visually-hidden">
                {' '}
                {new Intl.DateTimeFormat(kLocale, { weekday: 'long', timeZone: 'UTC' }).format(
                  new Date(Date.UTC(2023, 9, 1 + i)),
                )}
              </span>
            </span>
          ))}
        </div>
        {chunk(days.length + blanks, 7).map((_, weekIndex) => (
          <div role="row" className="cal-row" key={`week-${weekIndex}`}>
            {Array.from({ length: 7 }, (_, dayInWeek) => {
              const cellIndex = weekIndex * 7 + dayInWeek - blanks;
              if (cellIndex < 0 || cellIndex >= days.length) {
                return (
                  <span
                    role="gridcell"
                    aria-hidden="true"
                    className="cal-cell cal-blank"
                    key={`blank-${weekIndex}-${dayInWeek}`}
                  />
                );
              }
              const iso = days[cellIndex];
              const cell = dayCellView({
                iso,
                todayIso: props.todayIso,
                entryByIso: props.entryByIso,
                forecastByIso: props.forecastByIso,
                activeLayers,
              });
              const decoration = cell.forecast;
              const classes = [
                'cal-cell',
                'cal-day',
                cell.isToday ? 'cal-today' : '',
                cell.spottingStyle ? 'cal-spotting' : '',
                decoration?.predictedBleed ? 'cal-predicted' : '',
                decoration?.fertileWindow ? 'cal-fertile' : '',
              ]
                .filter(Boolean)
                .join(' ');
              const fragments: string[] = [];
              if (decoration?.predictedBleed) fragments.push(t('calendarLegendPredicted'));
              if (decoration?.pmsBadge) fragments.push(t('calendarLegendPms'));
              if (decoration?.crampsBadge) fragments.push(t('calendarLegendCramps'));
              if (decoration?.fertileWindow)
                fragments.push(t('sharingPredictionCalendarLegendFertile'));
              const dayDate = new Date(`${iso}T00:00:00Z`);
              const label = [kCellDateFormat.format(dayDate), ...fragments].join(', ');
              return (
                <span role="gridcell" className={classes} key={iso}>
                  <Link
                    className="cal-day-link"
                    to={`/day/${props.profileId}?date=${iso}`}
                    aria-label={label}
                  >
                    <span className="cal-day-number">{cell.dayNumber}</span>
                    {decoration?.cycleDayNumber != null ? (
                      <span className="cal-cycle-day">{decoration.cycleDayNumber}</span>
                    ) : null}
                    <span className="cal-marks" aria-hidden="true">
                      {cell.spottingStyle
                        ? null
                        : Array.from({ length: cell.flowMarkCount }, (_, i) => (
                            <span className="cal-mark" key={i} />
                          ))}
                    </span>
                    {cell.layerHits.length > 0 ? (
                      <span className="cal-layers" aria-hidden="true">
                        {cell.layerHits.map((code) => (
                          <span
                            className={layerDotClass(activeLayers.indexOf(code))}
                            key={code}
                          />
                        ))}
                      </span>
                    ) : null}
                    {decoration?.pmsBadge ? (
                      <span className="cal-badge cal-badge-pms" aria-hidden="true" />
                    ) : null}
                    {decoration?.crampsBadge ? (
                      <span className="cal-badge cal-badge-cramps" aria-hidden="true" />
                    ) : null}
                  </Link>
                </span>
              );
            })}
          </div>
        ))}
      </div>

      <details className="cal-details">
        <summary>{t('calendarLegend')}</summary>
        <ul className="cal-legend" data-testid="calendar-legend">
          <li>
            <LegendSwatch kind="spotting" /> {t('calendarLegendSpotting')}
          </li>
          <li>
            <LegendSwatch kind="flow" extraClass="cal-swatch-light" />{' '}
            {t('calendarLegendLight')}
          </li>
          <li>
            <LegendSwatch kind="flow" extraClass="cal-swatch-medium" />{' '}
            {t('calendarLegendMedium')}
          </li>
          <li>
            <LegendSwatch kind="flow" extraClass="cal-swatch-heavy" />{' '}
            {t('calendarLegendHeavy')}
          </li>
          <li>
            <LegendSwatch kind="flow" extraClass="cal-swatch-superheavy" />{' '}
            {t('calendarLegendSuperHeavy')}
          </li>
          <li>
            <LegendSwatch kind="symptom" /> {t('calendarLegendSymptom')}
          </li>
          <li>
            <LegendSwatch kind="today" /> {t('calendarLegendToday')}
          </li>
          <li>
            <LegendSwatch kind="predicted" /> {t('calendarLegendPredicted')}
          </li>
          {props.fertileShown ? (
            <li>
              <LegendSwatch kind="fertile" /> {t('sharingPredictionCalendarLegendFertile')}
            </li>
          ) : null}
          {props.pmsBandActive ? (
            <li>
              <LegendSwatch kind="pms" /> {t('calendarLegendPms')}
            </li>
          ) : null}
          <li>
            <LegendSwatch kind="cramps" /> {t('calendarLegendCramps')}
          </li>
          <li className="cal-legend-dots">
            <span className="cal-dot-palette" aria-hidden="true">
              <span className="cal-dot cal-dot-1" />
              <span className="cal-dot cal-dot-2" />
              <span className="cal-dot cal-dot-3" />
            </span>{' '}
            {t('calendarLegendLayerDots')}
          </li>
        </ul>
      </details>

      <details className="cal-details">
        <summary>{t('calendarSymptomLayers')}</summary>
        {layerLimitHit ? (
          <p className="card-body" role="alert" data-testid="layer-limit">
            {t('calendarLayerLimitSnack')}
          </p>
        ) : null}
        <ul className="cal-layer-picker">
          {taxonomy.tags.map((tag) => {
            if (taxonomy.positiveAssertionCodes.includes(tag.code)) return null;
            const checked = activeLayers.includes(tag.code);
            return (
              <li key={tag.code}>
                <label className="cal-layer-option">
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => toggleLayer(tag.code)}
                  />{' '}
                  {tag.display}
                </label>
              </li>
            );
          })}
        </ul>
      </details>
    </section>
  );
}

/** Splits n cells into weeks of 7. */
function chunk(total: number, size: number): number[] {
  const weeks: number[] = [];
  for (let i = 0; i < total; i += size) weeks.push(i);
  return weeks;
}
