import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Page, Route } from '@playwright/test';

/**
 * The fabricated signed-in world the profile-home e2e suite asserts
 * against and the site's browser CTA capture renders (issue #1431): the
 * Maya and Priya profiles with Maya's late-September 2026 entries, served
 * by fetch interception at the boundaries the Worker and the #1252 data
 * layer actually call — no backend, no real data, deterministic ULID ids.
 *
 * Two consumers keep this module honest: `profile-home.spec.ts` asserts
 * the rendered home, and `browser-home-capture.spec.ts` turns the same
 * render into the marketing site's `today-browser-light.png`.
 */

export const messages = JSON.parse(
  readFileSync(join(import.meta.dirname, '..', 'src', 'i18n', 'messages.en.json'), 'utf8'),
) as Record<string, string>;

export const UID = '00000000-0000-4000-8000-00000000000u1';
export const RICH_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
export const PREGNANT_ID = '01M2FWKNG0ZMH2ANCH7R2CM2YC';

/** The one day entry the "what is logged today" fixtures decorate. */
export const TODAY_ENTRY_ID = '01M2FWKNG0ZMH2ANCH7R2CM2E3';

/** The note `loggedSnapshot` carries; the page must never display it. */
export const FIXTURE_NOTE = 'zebra crossing after the dentist';

export interface Row {
  [key: string]: unknown;
}

export function profile(id: string, displayName: string, sortOrder: number): Row {
  return {
    id,
    user_id: UID,
    display_name: displayName,
    is_minor: false,
    sort_order: sortOrder,
    archived_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    mode: 'standard',
    irregular_framing: null,
    birth_year: 1990,
    relationship: 'self',
    last_period_start: null,
    typical_cycle_length_days: null,
    typical_period_length_days: null,
    bbt_unit: 'celsius',
    weight_unit: 'kg',
    tracking_preferences: null,
  };
}

export function entry(id: string, profileId: string, localDate: string, flow: string): Row {
  return {
    id,
    user_id: UID,
    profile_id: profileId,
    local_date: localDate,
    tz: 'UTC',
    flow,
    tags: [],
    note: null,
    note_private: false,
    pms: false,
    source: 'manual',
    source_id: null,
    import_id: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
  };
}

/** The snapshot `sync_pull` answers with — deterministic, ULID ids. */
export const snapshot = {
  profiles: [profile(RICH_ID, 'Maya', 0), profile(PREGNANT_ID, 'Priya', 1)],
  day_entries: [
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E1', RICH_ID, '2026-09-28', 'medium'),
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E2', RICH_ID, '2026-09-29', 'light'),
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E3', RICH_ID, '2026-09-30', 'medium'),
  ],
  observations: [],
  profile_modes: [
    {
      profile_id: PREGNANT_ID,
      mode: 'pregnancy',
      mode_started_on: null,
      estimated_due_date: null,
      postpartum_birth_date: null,
      birth_control_method: null,
      birth_control_started_on: null,
      birth_control_stopped_on: null,
      health_sync_consent: false,
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
  ],
  cycle_overrides: [],
  care_notes: [],
  visit_prep_items: [],
  profile_tag_registry: [],
  profile_guardians: [
    {
      id: 'a0000000-0000-4000-8000-000000000001',
      profile_id: RICH_ID,
      user_id: UID,
      role: 'primary_guardian',
      status: 'accepted',
      display_name: null,
      invited_by: null,
      is_subject: true,
      revoked_at: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
    {
      id: 'a0000000-0000-4000-8000-000000000002',
      profile_id: PREGNANT_ID,
      user_id: UID,
      role: 'primary_guardian',
      status: 'accepted',
      display_name: null,
      invited_by: null,
      is_subject: true,
      revoked_at: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
  ],
};

/** A snapshot's `sync_pull` answer, as a route fulfillment. */
export async function json(route: Route, body: unknown): Promise<void> {
  await route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(body),
  });
}

/**
 * Installs the signed-in fetch facade. Registration order matters: the
 * catch-all goes first so Playwright matches the specific routes after
 * it (later registrations win).
 */
export async function installSignedInFacade(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', (route) =>
    json(route, { message: 'e2e: unmocked rest call', details: route.request().url() }),
  );
  await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, snapshot));
  await page.route('**/rest/v1/rpc/sync_watermark', (route) => json(route, 100_000));
  await page.route('**/auth/session', (route) =>
    json(route, {
      access_token: 'e2e-access-token',
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: UID, email: 'e2e@example.com' },
    }),
  );
}

/**
 * The snapshot with Maya's 30 September filled in: flow, tags, a note, a
 * reading. `subject` decides the profile_guardians marker (the app's lens
 * rule: a guardian's front page does not say what was logged).
 */
export function loggedSnapshot(subject: boolean) {
  return {
    ...snapshot,
    day_entries: snapshot.day_entries.map((row) =>
      row['id'] === TODAY_ENTRY_ID
        ? {
            ...row,
            tags: ['cramps', 'fatigue', 'unprotected_sex'],
            note: FIXTURE_NOTE,
            pms: true,
          }
        : row,
    ),
    observations: [
      {
        id: '01M2FWKNG0ZMH2ANCH7R2CM2B1',
        day_entry_id: TODAY_ENTRY_ID,
        profile_id: RICH_ID,
        local_date: '2026-09-30',
        tz: 'UTC',
        observed_at: null,
        category: 'bbt',
        code: null,
        value_num: 36.7,
        value_text: null,
        unit: 'celsius',
        intensity: null,
        excluded: false,
        source: 'manual',
        source_id: null,
        created_at: '2026-09-30T08:00:00Z',
        updated_at: '2026-09-30T08:00:00Z',
        deleted_at: null,
        server_version: 4,
      },
    ],
    profile_guardians: snapshot.profile_guardians.map((row) => ({
      ...row,
      is_subject: subject,
    })),
  };
}

let configuredProbe: boolean | null = null;

/**
 * True when the build carries Supabase config (the app signs in at all).
 *
 * CI workflows pass `LUNARLOG_APP_CONFIGURED` ("true" or "false") based on
 * secret presence (issue #1662). When set, we avoid the 5s probe so that a
 * slow web app start does not quietly skip capture and cause a missing figure.
 * When unset (local test runs), it falls back to probing whether the signed-in
 * home appears within 5 seconds. An unconfigured build never leaves the welcome,
 * so there the wait runs out, once per worker.
 */
export async function buildIsConfigured(page: Page): Promise<boolean> {
  if (process.env.LUNARLOG_APP_CONFIGURED !== undefined) {
    return process.env.LUNARLOG_APP_CONFIGURED === 'true';
  }
  if (configuredProbe !== null) return configuredProbe;
  await installSignedInFacade(page);
  await page.goto('/');
  configuredProbe = await page
    .getByLabel(messages['webHomeProfileSwitcherLabel'] ?? 'Profile')
    .waitFor({ state: 'visible', timeout: 5_000 })
    .then(
      () => true,
      () => false,
    );
  return configuredProbe;
}
