import { useEffect, useMemo } from 'react';
import { Link, useSearchParams } from 'react-router';

import { useT } from '../i18n/t';
import { calendarForecast, cycleHistory, getDomainModule, predict } from '../domain/client';
import type { ForecastDayCell } from '../domain/schemas';
import { emptySyncedData } from '../lib/domain';
import { browserTimeZone, todayInBrowserZone } from '../lib/day/day-entry-policy';
import { spottingIsosFor } from '../lib/profiles/calendar-cells';
import {
  profileDomainInputs,
  profileListsFromSyncedData,
  profileModeFromDb,
  showsFertileWindow,
  withClockInputs,
} from '../lib/profiles/profile-views';
import {
  useHasSyncSession,
  useCurrentUserId,
  useSyncedData,
  useSyncSignalsRefetch,
} from '../lib/queries';
import type { DayEntryRow } from '../lib/schemas';
import { ProfileHomeCalendar } from './ProfileHomeCalendar';
import { ProfileHomeComparison, ProfileHomeHistory } from './ProfileHomeHistory';
import { ProfileHomeStatus } from './ProfileHomeStatus';
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

  if (!signedIn) return <SignedOutHome />;

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
        </div>
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
        <ProfileHome profileId={active.id} todayIso={todayInBrowserZone()} />
      ) : null}
    </main>
  );
}

/** One active profile's home: status card, month calendar, history. */
function ProfileHome(props: { profileId: string; todayIso: string }) {
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
      <ProfileHomeCalendar
        todayIso={props.todayIso}
        profileId={props.profileId}
        entryByIso={entryByIso}
        forecastByIso={forecastByIso}
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
        </>
      ) : null}
      <section className="card">
        <p className="card-body">
          <Link className="nav-link" to={`/day/${props.profileId}`}>
            {t('calendarTodayTooltip')}
          </Link>
          {' · '}
          <Link className="nav-link" to={`/profile/${props.profileId}/guardians`}>
            {t('profilePickerMenuGuardians')}
          </Link>
        </p>
      </section>
    </div>
  );
}
