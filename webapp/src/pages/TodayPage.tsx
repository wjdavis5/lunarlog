import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';

import { useT } from '../i18n/t';
import {
  calendarForecast,
  cycleHistory,
  getDomainModule,
  insights,
  predict,
} from '../domain/client';
import type { ForecastDayCell } from '../domain/schemas';
import { emptySyncedData } from '../lib/domain';
import { browserTimeZone, todayInBrowserZone } from '../lib/day/day-entry-policy';
import { firstRunSeen, markFirstRunSeen } from '../lib/first-run';
import { spottingIsosFor } from '../lib/profiles/calendar-cells';
import {
  callerRoleFor,
  guardianLensFor,
  profileDomainInputs,
  profileListsFromSyncedData,
  profileModeFromDb,
  showsFertileWindow,
  withClockInputs,
} from '../lib/profiles/profile-views';
import {
  readTodayLog,
  todayLogCardView,
  type TodayLogCardView,
} from '../lib/profiles/today-log';
import { canWriteDayContent } from '../lib/day/payloads';
import {
  useHasSyncSession,
  useCurrentUserId,
  useSyncedData,
  useSyncSignalsRefetch,
} from '../lib/queries';
import type { DayEntryRow } from '../lib/schemas';
import { FirstRunCard } from './FirstRunCard';
import { ProfileHomeCalendar } from './ProfileHomeCalendar';
import { ProfileHomeComparison, ProfileHomeHistory } from './ProfileHomeHistory';
import { ProfileHomeInsights } from './ProfileHomeInsights';
import { ProfileHomeStatus } from './ProfileHomeStatus';
import { ProfileHomeTodayLog } from './ProfileHomeTodayLog';
import { SignedOutHome } from './SignedOutHome';

/**
 * The profile home (issue #1253): pick a profile, see today's cycle day
 * and phase, the next-period estimate with its confidence — computed by
 * the compiled domain module (#1251), framed by the profile's care mode
 * (#853) and suppressed by life-stage modes and birth control — and
 * browse the month calendar and cycle history with the app's own layers.
 * Data is the #1252 synced snapshot; every computation is a pure
 * function of it plus the browser's clock and IANA zone, and nothing is
 * persisted (the nothing-stored rule covers this page like every other).
 */
export function TodayPage() {
  const t = useT();
  const [searchParams, setSearchParams] = useSearchParams();
  const signedIn = useHasSyncSession();
  const synced = useSyncedData();
  const me = useCurrentUserId(signedIn).data ?? null;

  // First-run orientation (issue #1795): a module-scoped session flag, so a
  // dismiss survives client-side navigation; a reload is a new session.
  const [firstRunDismissed, setFirstRunDismissed] = useState(() => firstRunSeen());

  useEffect(() => {
    document.title = t('gateLockScreenAppTitle');
  }, [t]);

  const lists = useMemo(
    () => profileListsFromSyncedData(synced.data ?? emptySyncedData(), me),
    [synced.data, me],
  );
  const live = useMemo(
    () =>
      [...lists.mine, ...lists.shared].sort(
        (a, b) => a.sort_order - b.sort_order || (a.id < b.id ? -1 : 1),
      ),
    [lists],
  );
  // Live updates ride the sync_signals subscription (issue #1252): any
  // change to a visible profile re-pulls, and the memoised domain outputs
  // recompute off the new snapshot.
  useSyncSignalsRefetch(live.map((profile) => profile.id));

  // ?profile=<id> picks the profile; an unknown or missing id falls back
  // to the first live profile and is written back so the address bar
  // always names what is on screen.
  const requested = searchParams.get('profile');
  const active = live.find((p) => p.id === requested) ?? live[0] ?? null;
  useEffect(() => {
    if (active !== null && active.id !== requested) {
      setSearchParams({ profile: active.id }, { replace: true });
    }
  }, [active, requested, setSearchParams]);

  // Today is the browser's today, read once per render so the button, the
  // card and the calendar under them all mean the same day.
  const todayIso = todayInBrowserZone();
  const activeId = active?.id ?? null;

  // What is logged today for the active profile: the one answer the
  // button's label and the "Logged today" card are both read from, as in
  // the app. It is the compiled domain module's answer over the snapshot
  // already in hand, so no request is made for it and it follows every
  // re-pull. A module that is missing or refuses the call leaves it null,
  // which reads as "Log today" and no card: never a wrong one.
  const todayLog = useMemo(() => {
    const data = synced.data;
    if (data === undefined || activeId === null) return null;
    try {
      return readTodayLog(getDomainModule(), data, activeId, todayIso);
    } catch {
      return null;
    }
  }, [synced.data, activeId, todayIso]);

  if (!signedIn) return <SignedOutHome />;

  // The same test the day editor applies to its own form: no accepted
  // membership counts as a viewer, and a viewer cannot write a day.
  const canLogActive =
    active !== null &&
    canWriteDayContent(
      callerRoleFor(synced.data ?? emptySyncedData(), active.id, me) ?? 'viewer',
    );

  // Who sees the card. A guardian's page says nothing of what was logged
  // (the app's lens rule, guardianLensFor); the person the profile is
  // about sees it. Until the account id has loaded there is no telling the
  // two apart, so nothing is shown rather than shown to the wrong reader.
  const todayLogView: TodayLogCardView =
    active === null || me === null
      ? { kind: 'none' }
      : todayLogCardView({
          log: todayLog,
          lens: guardianLensFor(synced.data ?? emptySyncedData(), active.id, me),
          canLog: canLogActive,
        });

  if (synced.isError) {
    return (
      <main className="page">
        <h1 className="display">{t('profilePickerTitle')}</h1>
        <section className="card">
          <p className="card-body">{t('webProfilesLoadFailed')}</p>
        </section>
      </main>
    );
  }

  return (
    <main className="page">
      {live.length > 0 ? (
        <div className="home-switcher">
          <label className="visually-hidden" htmlFor="profile-switcher">
            {t('webHomeProfileSwitcherLabel')}
          </label>
          <select
            id="profile-switcher"
            className="home-switcher-select"
            value={active?.id ?? ''}
            onChange={(event) => setSearchParams({ profile: event.target.value })}
          >
            {live.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.display_name}
              </option>
            ))}
          </select>
          <Link className="nav-link" to="/profiles">
            {t('profilePickerTitle')}
          </Link>
          {active !== null ? (
            <Link className="nav-link" to={`/profile/${active.id}/guardians`}>
              {t('profilePickerMenuGuardians')}
            </Link>
          ) : null}
          {/* Guardian notes and care notes had a page and no link to it:
              the only way in was to know the address. */}
          {active !== null ? (
            <Link className="nav-link" to={`/profile/${active.id}/notes`}>
              {t('webDayNotesSection')}
            </Link>
          ) : null}
          {/* The one thing most visits are for, so it is the first button
              on the page and the only filled one. It used to be a text
              link under everything else, labelled "Today" like the header
              link that goes somewhere else. A viewer cannot log, so a
              viewer is not offered it; the calendar still opens any day.
              It reads "Edit today" once today has something logged, as
              the app's button does. */}
          {active !== null && canLogActive ? (
            <Link className="btn btn-primary home-log-today" to={`/day/${active.id}`}>
              {t(todayLog?.hasContent === true ? 'todayLogFabEdit' : 'householdLogToday')}
            </Link>
          ) : null}
        </div>
      ) : !firstRunDismissed ? (
        <FirstRunCard
          onContinue={() => {
            markFirstRunSeen();
            setFirstRunDismissed(true);
          }}
        />
      ) : (
        <section className="card">
          <p className="card-title">{t('profilePickerEmptyTitle')}</p>
          <p className="card-body">{t('profilePickerEmptyBody')}</p>
          <p className="card-body">
            <Link className="nav-link" to="/profiles">
              {t('profilePickerEmptyAddAction')}
            </Link>
          </p>
        </section>
      )}

      {active !== null ? (
        <ProfileHome profileId={active.id} todayIso={todayIso} todayLogView={todayLogView} />
      ) : null}
    </main>
  );
}

/** One active profile's home: status card, today's log, month calendar, history. */
function ProfileHome(props: {
  profileId: string;
  todayIso: string;
  todayLogView: TodayLogCardView;
}) {
  const t = useT();
  const synced = useSyncedData();
  const tz = browserTimeZone();

  const profile = synced.data?.profiles.find((row) => row.id === props.profileId);
  const inputs = useMemo(() => {
    const data = synced.data;
    if (data === undefined || profile === undefined) return null;
    return profileDomainInputs(data, props.profileId);
  }, [synced.data, props.profileId, profile]);

  // The domain module is synchronous and holds no state between calls;
  // memoising on the inputs keeps an 18-month history from recomputing
  // on every render (the parity suite times this shape at well under a
  // millisecond per call, so even a recompute would be honest — this is
  // hygiene, not a guard). A missing module (a dev build without the
  // artifact) or a failed call renders the estimate's own load-error copy
  // — never a crash.
  const domain = useMemo(() => {
    if (inputs === null) return null;
    try {
      const module = getDomainModule();
      const request = withClockInputs(inputs, props.todayIso, tz);
      return {
        prediction: predict(module, request),
        history: cycleHistory(module, request),
        forecast: calendarForecast(module, request),
        insights: insights(module, request),
      };
    } catch {
      return null;
    }
  }, [inputs, props.todayIso, tz]);

  const entryByIso = useMemo(() => {
    const map = new Map<string, DayEntryRow>();
    for (const row of synced.data?.day_entries ?? []) {
      if (row.profile_id !== props.profileId || row.deleted_at !== null) continue;
      map.set(row.local_date, row);
    }
    return map;
  }, [synced.data, props.profileId]);

  const spottingIsos = useMemo(
    () =>
      spottingIsosFor(entryByIso.values(), synced.data?.observations ?? [], props.profileId),
    [entryByIso, synced.data, props.profileId],
  );

  const forecastByIso = useMemo(() => {
    const map = new Map<string, ForecastDayCell>();
    if (domain === null) return map;
    for (const [iso, cell] of Object.entries(domain.forecast.cells)) {
      map.set(iso, cell);
    }
    return map;
  }, [domain]);

  if (profile === undefined) {
    return (
      <section className="card">
        <p className="card-body">{t('webDayNoAccess')}</p>
      </section>
    );
  }

  return (
    <div className="home-stack">
      {domain === null ? (
        <section className="card">
          <p className="card-body">{t('overviewEstimateLoadError')}</p>
        </section>
      ) : (
        <ProfileHomeStatus
          prediction={domain.prediction}
          profileMode={profile.mode}
          storedIrregularFraming={profile.irregular_framing ?? null}
          todayIso={props.todayIso}
          displayName={profile.display_name}
        />
      )}
      {/* Directly under the estimate, above the calendar: what is logged
          today. Draws nothing for a reader who is not shown it. */}
      <ProfileHomeTodayLog view={props.todayLogView} profileId={props.profileId} />
      <ProfileHomeCalendar
        todayIso={props.todayIso}
        profileId={props.profileId}
        entryByIso={entryByIso}
        forecastByIso={forecastByIso}
        // The domain says which day, if any, to mark as the last-period
        // date given at setup (issue #1476).
        setupPeriodMarkIso={domain?.forecast.setupPeriodMarkDate ?? null}
        // The PMS legend swatch only shows while the live estimate
        // actually carries a band — the app's "no band rather than a
        // noisy one" rule (issue #220).
        pmsBandActive={
          domain !== null &&
          domain.prediction.kind === 'active' &&
          !domain.prediction.staleHistory &&
          domain.prediction.pms !== null
        }
        spottingIsos={spottingIsos}
        // The irregular framing and the Perimenopause life stage hide the
        // fertile layer (showsFertileWindow); a stale history draws no
        // forecast at all.
        fertileShown={
          domain !== null &&
          domain.prediction.kind === 'active' &&
          !domain.prediction.staleHistory &&
          showsFertileWindow({
            profileMode: profileModeFromDb(profile.mode),
            storedIrregularFraming: profile.irregular_framing ?? null,
            tier: domain.prediction.tier,
            lifecycleMode: inputs?.lifecycleMode ?? null,
          })
        }
      />
      {domain !== null ? (
        <>
          <ProfileHomeHistory history={domain.history} />
          <ProfileHomeComparison history={domain.history} />
          <ProfileHomeInsights report={domain.insights} />
        </>
      ) : null}
    </div>
  );
}
