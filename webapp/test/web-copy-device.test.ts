import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import messages from '../src/i18n/messages.en.json';

/**
 * The web client shares its catalogue with the phone app, and a string
 * written for the phone can be false in a browser. Several were: the
 * invitation page said the profile "will sync to this device", the archive
 * confirmation that its history "stays on this device", and the account
 * deletion that it removes "the copy on this device". This client keeps
 * nothing in the browser. It is the promise the welcome page makes, so
 * saying otherwise three screens later is worse than loose wording.
 *
 * This scans every catalogue id the client's source names and fails on
 * wording that only fits a phone, so a borrowed string is noticed when it
 * is borrowed.
 */

const SRC = join(import.meta.dirname, '..', 'src');
const catalogue = messages as Record<string, string>;

function sourceFiles(dir: string): string[] {
  const found: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      // The generated catalogue itself names every id, used or not.
      if (name !== 'i18n') found.push(...sourceFiles(path));
    } else if (/\.tsx?$/.test(name)) {
      found.push(path);
    }
  }
  return found;
}

/** Every catalogue id that appears as a string literal in the client. */
function usedIds(): string[] {
  const used = new Set<string>();
  for (const file of sourceFiles(SRC)) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(/['"]([a-z][A-Za-z0-9]+)['"]/g)) {
      const id = match[1] ?? '';
      if (id in catalogue) used.add(id);
    }
  }
  return [...used].sort();
}

/**
 * Ids allowed to say "this device", each for a reason.
 *
 * - `webAuthSignOutEverywhereRevocationFailed`: "This device is signed
 *   out" is about the session, which is the one thing a browser does hold.
 */
const DEVICE_WORDING_ALLOWED = new Set(['webAuthSignOutEverywhereRevocationFailed']);

describe('web copy', () => {
  const ids = usedIds();

  it('finds the ids the client uses (a scan that matches nothing proves nothing)', () => {
    expect(ids.length).toBeGreaterThan(300);
    expect(ids).toContain('webInviteNeutralIntro');
    expect(ids).toContain('householdLogToday');
  });

  it('never says data is on, or synced to, "this device"', () => {
    const offenders = ids
      .filter((id) => !DEVICE_WORDING_ALLOWED.has(id))
      .filter((id) => /\bthis device\b/i.test(catalogue[id] ?? ''));
    expect(offenders).toEqual([]);
  });

  it('never tells the reader to tap', () => {
    const offenders = ids.filter((id) => /\btap(s|ped|ping)?\b/i.test(catalogue[id] ?? ''));
    expect(offenders).toEqual([]);
  });

  it('shows no internal issue number to the reader', () => {
    const offenders = ids.filter((id) => /\bissue #\d+|\(#\d+\)/i.test(catalogue[id] ?? ''));
    expect(offenders).toEqual([]);
  });

  it('says where an accepted invitation goes: the account', () => {
    for (const id of [
      'webInviteNeutralIntro',
      'webInvitePreviewIntro',
      'webInviteSubjectIntro',
    ]) {
      expect(catalogue[id], id).toMatch(/your account/);
    }
  });

  it('ties an emailed link to this browser, the only place it completes', () => {
    expect(catalogue['webAuthConfirmEmailInfo']).toMatch(/in this browser/);
    expect(catalogue['webAuthResetInfo']).toMatch(/in this browser/);
  });
});
