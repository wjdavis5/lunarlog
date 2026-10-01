import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';

import { useT, type TFunction } from '../i18n/t';
import { getSupabaseClient, type AppSupabaseClient } from '../lib/supabase';
import {
  browserTimeZone,
  isIsoLocalDate,
  todayInBrowserZone,
  validateDayDate,
} from '../lib/day/day-entry-policy';
import {
  bbtRangeIn,
  bbtUnitFromDb,
  convertTemperature,
  convertWeight,
  weightRangeIn,
  weightUnitFromDb,
  type BbtUnit,
  type WeightUnit,
} from '../lib/day/measurements';
import {
  canEditProfileMetadata,
  canWriteDayContent,
  resolveCallerRole,
  SELECTABLE_FLOW_LEVELS,
  LIFECYCLE_MODES,
  type CallerRole,
  type DayEdit,
  type FlowLevel,
  type LoadedDayView,
  MAX_NOTE_LENGTH,
  type SavePlanField,
} from '../lib/day/payloads';
import {
  isSingleSelectCategory,
  resolveDayCategories,
  taxonomy,
  tagsByCategory,
} from '../lib/day/categories';
import { useDayView, useSaveDay } from '../lib/day/use-day';
import {
  DomainModuleMissingError,
  getDomainModule,
  validateDayEntryDate,
} from '../domain/client';

/**
 * The web day editor (issue #1254): the app day sheet's categories — flow
 * and spotting, symptom tags, notes (including private), BBT, weight,
 * ovulation/pregnancy test tags, cycle corrections and life-stage modes —
 * written through the same `sync_push` path the phones use. Saves write
 * straight through; a failed save stays on screen with a retry and is never
 * silently dropped; closing the tab with unsaved edits warns first. A
 * viewer gets the same day read-only.
 */

const FLOW_LABEL_IDS: Record<FlowLevel, Parameters<TFunction>[0]> = {
  none: 'flowLevelNone',
  spotting: 'flowLevelSpotting',
  not_bleeding: 'flowLevelNotBleeding',
  light: 'flowLevelLight',
  medium: 'flowLevelMedium',
  heavy: 'flowLevelHeavy',
  super_heavy: 'flowLevelSuperHeavy',
};

const LIFECYCLE_MODE_LABEL_IDS = {
  tracking: 'webDayModeTracking',
  conceive: 'webDayModeConceive',
  pregnancy: 'webDayModePregnancy',
  perimenopause: 'webDayModePerimenopause',
  postpartum: 'webDayModePostpartum',
} as const;

function Chip({
  label,
  selected,
  onPress,
  disabled,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
  disabled: boolean;
}) {
  return (
    <button
      type="button"
      className={selected ? 'chip chip-selected' : 'chip'}
      aria-pressed={selected}
      onClick={onPress}
      disabled={disabled}
    >
      {label}
    </button>
  );
}

function editFromView(view: LoadedDayView | undefined): DayEdit {
  if (view === undefined) {
    return {
      flow: 'none',
      flowExplicitlySet: false,
      spotting: false,
      pms: false,
      tags: [],
      note: null,
      notePrivate: false,
      bbt: null,
      weight: null,
      mode: null,
      manualCycleStart: false,
      excludeCycleFromAverage: false,
    };
  }
  const spotting = view.observations.some(
    (o) => o.deleted_at === null && o.category === 'spotting',
  );
  const bbtRow = view.observations.find(
    (o) => o.deleted_at === null && o.category === 'bbt' && o.source === 'manual',
  );
  const weightRow = view.observations.find(
    (o) => o.deleted_at === null && o.category === 'weight' && o.source === 'manual',
  );
  const entry = view.entry;
  // Issue #1287: a stored measurement keeps the unit it was logged in
  // (`observations.unit`), which can differ from the profile's current
  // unit preference — the seed converts it, exactly like the app's day
  // sheet (lib/ui/logging/day_sheet.dart) does, so the field shows the
  // physical value in the profile's unit instead of a raw number that
  // reads as out of range (or silently rewrites the row on save).
  const bbtUnit = bbtUnitFromDb(view.profile.bbt_unit);
  const weightUnit = weightUnitFromDb(view.profile.weight_unit);
  return {
    flow: (entry?.flow as DayEdit['flow']) ?? 'none',
    flowExplicitlySet: false,
    spotting,
    pms: entry?.pms ?? false,
    tags: [...(entry?.tags ?? [])],
    note: entry?.note ?? null,
    notePrivate: entry?.note_private ?? false,
    bbt:
      bbtRow === undefined || bbtRow.value_num === null
        ? null
        : convertTemperature(bbtRow.value_num, bbtUnitFromDb(bbtRow.unit), bbtUnit),
    weight:
      weightRow === undefined || weightRow.value_num === null
        ? null
        : convertWeight(weightRow.value_num, weightUnitFromDb(weightRow.unit), weightUnit),
    mode: null,
    manualCycleStart: view.cycleOverride?.manual_start ?? false,
    excludeCycleFromAverage: view.cycleOverride?.excluded_from_average ?? false,
  };
}

function serializeEdit(edit: DayEdit): string {
  return JSON.stringify(edit);
}

export function DayPage({ client: clientProp }: { client?: AppSupabaseClient | null }) {
  const t = useT();
  const params = useParams();
  const profileId = params.profileId ?? '';
  const [searchParams] = useSearchParams();
  const dateParam = searchParams.get('date');
  const dateIso =
    dateParam !== null && isIsoLocalDate(dateParam) ? dateParam : todayInBrowserZone();
  const todayIso = todayInBrowserZone();
  const tz = browserTimeZone();

  const client = clientProp === undefined ? getSupabaseClient() : clientProp;
  const day = useDayView(client, profileId, dateIso);
  const view = day.view;
  const saveMutation = useSaveDay(client, profileId);

  const [edit, setEdit] = useState<DayEdit>(() => editFromView(view));
  const [loadedKey, setLoadedKey] = useState('');
  const [savedBaseline, setSavedBaseline] = useState('');
  // Set when a save comes back LWW-declined (#1289): the next settled
  // refetch must re-seed the editor from the server's winning state —
  // the losing values are exactly what a retry must not re-push.
  const [declinedReseed, setDeclinedReseed] = useState(false);

  // Re-seed the editor whenever the server's state for this day changes
  // identity or content (first load, a same-date merge handback) — but
  // never while the operator is mid-edit (their keystrokes win; the merge
  // notices plus the next load carry the convergence).
  const viewKey =
    view === undefined
      ? ''
      : `${profileId}/${dateIso}/${view.entry?.id ?? 'new'}/${view.entry?.updated_at ?? ''}`;
  const dirty = loadedKey !== '' && serializeEdit(edit) !== savedBaseline;
  useEffect(() => {
    if (view !== undefined && viewKey !== loadedKey && !dirty) {
      const fresh = editFromView(view);
      setEdit(fresh);
      setLoadedKey(viewKey);
      setSavedBaseline(serializeEdit(fresh));
    }
  }, [view, viewKey, loadedKey, dirty]);

  // The declined-save half of that convergence (#1289): an LWW decline
  // leaves the edit dirty on purpose only until the invalidation refetch
  // brings back the day's newer stored state — then the editor re-seeds
  // from it even mid-edit, Save re-disables (nothing left to save), and a
  // retry can no longer push the stale full row over the other device's
  // newer flow/tags/note. Waiting for the refetch to settle (not just for
  // a viewKey change) also covers the equal-instant decline where the
  // winning row differs only in content.
  useEffect(() => {
    if (!declinedReseed || view === undefined || day.isFetching) return;
    const fresh = editFromView(view);
    setEdit(fresh);
    setLoadedKey(viewKey);
    setSavedBaseline(serializeEdit(fresh));
    setDeclinedReseed(false);
  }, [declinedReseed, view, viewKey, day.isFetching]);

  const role: CallerRole = useMemo(() => resolveCallerRole(view?.membership ?? null), [view]);
  const readOnly = !canWriteDayContent(role);
  const isSubject = view?.membership?.is_subject === true;
  const metadataAllowed = canEditProfileMetadata(role);

  // Date bounds (#848, checked through the compiled domain module when it
  // is loaded — the #1251 module is the owner of this rule; the pure port
  // below is the fallback for a build that ships without it). An
  // out-of-bounds day renders read-only with the reason before anything is
  // pushed.
  const bounds = useMemo(() => {
    const birthYear = view?.profile.birth_year ?? null;
    try {
      const result = validateDayEntryDate(getDomainModule(), {
        date: dateIso,
        today: todayIso,
        birthYear: birthYear ?? undefined,
      });
      return result.status === 'valid'
        ? { valid: true as const }
        : { valid: false as const, violation: result.status };
    } catch (error) {
      if (error instanceof DomainModuleMissingError) {
        return validateDayDate(dateIso, todayIso, birthYear);
      }
      throw error;
    }
  }, [dateIso, todayIso, view]);

  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      // Closing the tab with an unsaved edit warns first; the browser
      // supplies its own generic text in the dialog.
      event.preventDefault();
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [dirty]);

  const patch = useCallback((next: Partial<DayEdit>) => {
    setEdit((current) => ({ ...current, ...next }));
  }, []);

  const toggleTag = useCallback((code: string, categoryName: string | null) => {
    setEdit((current) => {
      const has = current.tags.includes(code);
      if (has) {
        return { ...current, tags: current.tags.filter((tag) => tag !== code) };
      }
      if (categoryName !== null && isSingleSelectCategory(categoryName)) {
        // A day carries exactly one option of a single-select category.
        const siblings = new Set(
          taxonomy.tags.filter((tag) => tag.category === categoryName).map((tag) => tag.code),
        );
        return {
          ...current,
          tags: [...current.tags.filter((tag) => !siblings.has(tag)), code],
        };
      }
      return { ...current, tags: [...current.tags, code] };
    });
  }, []);

  const onSave = () => {
    if (client === null || view === undefined || !bounds.valid || readOnly || !dirty) return;
    // Baseline the exact edit that is being pushed: a successful save makes
    // it the loaded state (the refetch then converges the editor onto the
    // server's stored copy — merge results included), while a failed save
    // leaves the banner up and every value editable for retry.
    const snapshot = edit;
    saveMutation.mutate(
      { edit, view, dateIso, todayIso, tz },
      {
        onSuccess: (result) => {
          // Keystrokes made while the push was in flight stay in the
          // editor; the baseline only absorbs what the server accepted.
          // A partly-rejected push still resolves, so the baseline must
          // not move for it: the edit stays dirty — Save (retry) enabled,
          // the beforeunload warning armed — and the banner's values
          // survive the invalidation refetch instead of being re-seeded
          // away. An LWW-declined push is the one exception (#1289): the
          // server kept newer content, so the re-seed effect above waits
          // for the refetch and converges the editor onto it before Save
          // re-enables — a retry must never re-push the losing row.
          if (result.rejectedFields.length === 0 && !result.ourEntryDeclined) {
            setSavedBaseline(serializeEdit(snapshot));
          }
          if (result.ourEntryDeclined) {
            setDeclinedReseed(true);
          }
        },
      },
    );
  };

  const saveError = saveMutation.error instanceof Error ? saveMutation.error : null;
  const saveResult = saveMutation.data ?? null;
  const rejectedFields: Set<SavePlanField> = new Set(saveResult?.rejectedFields ?? []);

  // Unconfigured build, or a configured one visited without a session:
  // both show the sign-in prompt (the web sign-in itself is #1250).
  if (client === null || day.signedOut) {
    return (
      <main className="page">
        <h1 className="display">{t('gateLockScreenAppTitle')}</h1>
        <section className="card">
          <p className="card-body">{t('webDayNeedsSignIn')}</p>
        </section>
      </main>
    );
  }

  const grouped = tagsByCategory();
  const surfaced = view !== undefined ? resolveDayCategories(view.profile) : [];
  // The `tests` category (ovulation/pregnancy results) has its own fieldset
  // below rather than a slot in the symptom picker (issue #1291): skipping it
  // here keeps its chips to exactly one copy, and gating that fieldset on
  // `surfaced` makes it honour the profile's tracking_preferences like every
  // other category.
  const symptomCategories = surfaced.filter((category) => category.name !== 'tests');
  const testsSurfaced = surfaced.some((category) => category.name === 'tests');
  const bbtUnit = (view?.profile.bbt_unit ?? 'celsius') as BbtUnit;
  const weightUnit = (view?.profile.weight_unit ?? 'kg') as WeightUnit;
  const bbtRange = bbtRangeIn(bbtUnit);
  const weightRange = weightRangeIn(weightUnit);

  const storedNote = view?.entry?.note ?? null;
  const storedPrivate = view?.entry?.note_private ?? false;
  const noteMasked = !isSubject && storedPrivate && storedNote === null;
  // The privacy toggle's own rules (#849): chosen while the stored note is
  // still empty; never set onto an already-shared note; never cleared.
  const privateLockedOn = storedPrivate;
  const privateLockedOff = !storedPrivate && storedNote !== null && storedNote !== '';
  const privateDisabled =
    readOnly || (!isSubject && view !== undefined) || privateLockedOn || privateLockedOff;

  const dateHeading = t('webDayPageTitle', {
    profileName: view?.profile.display_name ?? profileId,
    date: dateIso,
  });

  return (
    <main className="page">
      <h1 className="display">{dateHeading}</h1>
      <nav>
        <Link className="nav-link" to="/">
          {t('webDayBackToToday')}
        </Link>
      </nav>

      {day.isPending ? (
        <section className="card">
          <p className="card-body" aria-busy="true">
            {t('webDaySaving')}
          </p>
        </section>
      ) : null}

      {day.isError ? (
        <section className="card" role="alert">
          <p className="card-body">{t('webDayNoAccess')}</p>
        </section>
      ) : null}

      {!day.isPending && !day.isError && view !== undefined ? (
        <>
          {role === 'viewer' ? (
            <section className="card" aria-live="polite">
              <p className="card-body">
                {view.membership === null ? t('webDayNoAccess') : t('webDayReadOnlyViewer')}
              </p>
            </section>
          ) : null}

          {!bounds.valid ? (
            <section className="card" role="alert">
              <p className="card-body">
                {bounds.violation === 'futureDate'
                  ? t('webDayErrorFuture')
                  : t('webDayErrorBirthYear')}
              </p>
            </section>
          ) : null}

          {saveResult !== null && saveResult.ourEntryDeclined ? (
            <section className="card" role="alert">
              <p className="card-body">{t('webDayDeclinedNotice')}</p>
            </section>
          ) : null}
          {saveResult !== null && saveResult.mergedLoserCount > 0 ? (
            <section className="card" role="status">
              <p className="card-body">{t('webDayMergedNotice')}</p>
            </section>
          ) : null}

          <fieldset className="card day-group" disabled={readOnly || !bounds.valid}>
            <legend className="card-title">{t('webDayFlowSection')}</legend>
            <div className="chip-row" role="group" aria-label={t('webDayFlowSection')}>
              {SELECTABLE_FLOW_LEVELS.map((level) => (
                <Chip
                  key={level}
                  label={t(FLOW_LABEL_IDS[level])}
                  selected={edit.flow === level}
                  onPress={() => patch({ flow: level, flowExplicitlySet: true })}
                  disabled={readOnly}
                />
              ))}
            </div>
            <div className="chip-row">
              <Chip
                label={t('webDaySpottingToggle')}
                selected={edit.spotting}
                onPress={() => patch({ spotting: !edit.spotting })}
                disabled={readOnly}
              />
              <Chip
                label={t('webDayPmsToggle')}
                selected={edit.pms}
                onPress={() => patch({ pms: !edit.pms })}
                disabled={readOnly}
              />
            </div>
            {rejectedFields.has('flow') || rejectedFields.has('entry') ? (
              <p className="field-error" role="alert">
                {t('webDayRejectedField')}
              </p>
            ) : null}
          </fieldset>

          <fieldset className="card day-group" disabled={readOnly}>
            <legend className="card-title">{t('webDaySymptomsSection')}</legend>
            {symptomCategories.map((category) => {
              const codes = grouped.get(category.name) ?? [];
              return (
                <div key={category.name} className="tag-category">
                  <p className="card-title">{category.label}</p>
                  <div className="chip-row" role="group" aria-label={category.label}>
                    {codes.map((tag) => (
                      <Chip
                        key={tag.code}
                        label={tag.display}
                        selected={edit.tags.includes(tag.code)}
                        onPress={() => toggleTag(tag.code, category.name)}
                        disabled={readOnly}
                      />
                    ))}
                  </div>
                </div>
              );
            })}
            {view.customTags.length > 0 ? (
              <div className="tag-category">
                <p className="card-title">{t('webDaySymptomsSection')}</p>
                <div className="chip-row" role="group" aria-label={t('webDaySymptomsSection')}>
                  {view.customTags.map((tag) => (
                    <Chip
                      key={tag.id}
                      label={tag.display_name}
                      selected={edit.tags.includes(tag.code)}
                      onPress={() => toggleTag(tag.code, null)}
                      disabled={readOnly}
                    />
                  ))}
                </div>
              </div>
            ) : null}
            {rejectedFields.has('tags') ? (
              <p className="field-error" role="alert">
                {t('webDayRejectedField')}
              </p>
            ) : null}
          </fieldset>

          <fieldset className="card day-group" disabled={readOnly}>
            <legend className="card-title">{t('webDayMeasurementsSection')}</legend>
            <label className="field-label" htmlFor="day-bbt">
              {t('webDayBbtLabel', { unit: bbtUnit === 'celsius' ? '°C' : '°F' })}
            </label>
            <input
              id="day-bbt"
              className="field-input"
              type="number"
              step="0.1"
              inputMode="decimal"
              value={edit.bbt === null ? '' : String(edit.bbt)}
              onChange={(event) =>
                patch({
                  bbt: event.target.value === '' ? null : Number(event.target.value),
                })
              }
            />
            {edit.bbt !== null && (edit.bbt < bbtRange.min || edit.bbt > bbtRange.max) ? (
              <p className="field-error" role="alert">
                {t('webDayErrorBbtRange', { min: bbtRange.min, max: bbtRange.max })}
              </p>
            ) : null}
            {rejectedFields.has('bbt') ? (
              <p className="field-error" role="alert">
                {t('webDayRejectedField')}
              </p>
            ) : null}

            <label className="field-label" htmlFor="day-weight">
              {t('webDayWeightLabel', { unit: weightUnit })}
            </label>
            <input
              id="day-weight"
              className="field-input"
              type="number"
              step="0.1"
              inputMode="decimal"
              value={edit.weight === null ? '' : String(edit.weight)}
              onChange={(event) =>
                patch({
                  weight: event.target.value === '' ? null : Number(event.target.value),
                })
              }
            />
            {edit.weight !== null &&
            (edit.weight < weightRange.min || edit.weight > weightRange.max) ? (
              <p className="field-error" role="alert">
                {t('webDayErrorWeightRange', { min: weightRange.min, max: weightRange.max })}
              </p>
            ) : null}
            {rejectedFields.has('weight') ? (
              <p className="field-error" role="alert">
                {t('webDayRejectedField')}
              </p>
            ) : null}
          </fieldset>

          {testsSurfaced ? (
            <fieldset className="card day-group" disabled={readOnly}>
              <legend className="card-title">{t('webDayTestsSection')}</legend>
              <div className="chip-row" role="group" aria-label={t('webDayTestsSection')}>
                {(grouped.get('tests') ?? []).map((tag) => (
                  <Chip
                    key={tag.code}
                    label={tag.display}
                    selected={edit.tags.includes(tag.code)}
                    onPress={() => toggleTag(tag.code, null)}
                    disabled={readOnly}
                  />
                ))}
              </div>
            </fieldset>
          ) : null}

          <fieldset className="card day-group" disabled={readOnly}>
            <legend className="card-title">{t('webDayNotesSection')}</legend>
            {noteMasked ? (
              <p className="card-body">{t('webDayNotePrivateMasked')}</p>
            ) : (
              <textarea
                className="field-input"
                aria-label={t('webDayNotesSection')}
                rows={4}
                maxLength={MAX_NOTE_LENGTH}
                placeholder={t('webDayNotePlaceholder')}
                value={edit.note ?? ''}
                onChange={(event) => patch({ note: event.target.value })}
                readOnly={readOnly}
              />
            )}
            <div className="chip-row">
              <label className="toggle">
                <input
                  type="checkbox"
                  checked={edit.notePrivate}
                  disabled={privateDisabled}
                  onChange={(event) => patch({ notePrivate: event.target.checked })}
                />
                {t('webDayNotePrivate')}
              </label>
            </div>
            {privateLockedOn ? (
              <p className="field-hint">{t('webDayNotePrivateLockedOn')}</p>
            ) : null}
            {privateLockedOff ? (
              <p className="field-hint">{t('webDayNotePrivateLockedOff')}</p>
            ) : null}
            {!privateLockedOn && !privateLockedOff && !isSubject && view !== undefined ? (
              <p className="field-hint">{t('webDayNotePrivateSubjectOnly')}</p>
            ) : null}
            {rejectedFields.has('note') ? (
              <p className="field-error" role="alert">
                {t('webDayRejectedField')}
              </p>
            ) : null}
          </fieldset>

          {metadataAllowed ? (
            <>
              <fieldset className="card day-group" disabled={readOnly}>
                <legend className="card-title">{t('webDayCycleSection')}</legend>
                <label className="toggle">
                  <input
                    type="checkbox"
                    checked={edit.manualCycleStart}
                    onChange={(event) => patch({ manualCycleStart: event.target.checked })}
                  />
                  {t('webDayManualStart')}
                </label>
                <label className="toggle">
                  <input
                    type="checkbox"
                    checked={edit.excludeCycleFromAverage}
                    onChange={(event) =>
                      patch({ excludeCycleFromAverage: event.target.checked })
                    }
                  />
                  {t('webDayExcludeFromAverage')}
                </label>
                {rejectedFields.has('cycleOverride') ? (
                  <p className="field-error" role="alert">
                    {t('webDayRejectedField')}
                  </p>
                ) : null}
              </fieldset>

              <fieldset className="card day-group" disabled={readOnly}>
                <legend className="card-title">{t('webDayModeSection')}</legend>
                <select
                  className="field-input"
                  aria-label={t('webDayModeSection')}
                  value={edit.mode ?? view.mode?.mode ?? 'tracking'}
                  onChange={(event) => patch({ mode: event.target.value as DayEdit['mode'] })}
                >
                  {LIFECYCLE_MODES.map((mode) => (
                    <option key={mode} value={mode}>
                      {t(LIFECYCLE_MODE_LABEL_IDS[mode])}
                    </option>
                  ))}
                </select>
                {rejectedFields.has('mode') ? (
                  <p className="field-error" role="alert">
                    {t('webDayRejectedField')}
                  </p>
                ) : null}
              </fieldset>
            </>
          ) : null}

          <section className="card day-actions">
            {saveError !== null ? (
              <p className="field-error" role="alert">
                {t('webDaySaveFailed')}
              </p>
            ) : null}
            <button
              type="button"
              className="save-button"
              onClick={onSave}
              disabled={readOnly || !bounds.valid || saveMutation.isPending || !dirty}
            >
              {saveMutation.isPending ? t('webDaySaving') : t('webDaySave')}
            </button>
            {saveMutation.isSuccess && !dirty && !saveResult?.ourEntryDeclined ? (
              <span className="save-status" role="status">
                {t('webDaySaved')}
              </span>
            ) : null}
          </section>
        </>
      ) : null}
    </main>
  );
}
