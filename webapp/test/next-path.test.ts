import { describe, expect, it } from 'vitest';

import { safeNextPath, withNext } from '../src/lib/next-path';

/**
 * The `next` parameter comes from the address bar, so anyone can put
 * anything in it. The sign-in pages navigate to whatever this returns:
 * it must never hand back a way off the site.
 */
describe('safeNextPath', () => {
  it('accepts a path on this site, with its query and fragment', () => {
    expect(safeNextPath('/invite?code=ABC123')).toBe('/invite?code=ABC123');
    expect(safeNextPath('/invite?code=ABC123&kind=claim')).toBe(
      '/invite?code=ABC123&kind=claim',
    );
    expect(safeNextPath('/profiles')).toBe('/profiles');
    expect(safeNextPath('/day/01ARZ3NDEKTSV4RRFFQ69G5FAV?date=2026-09-30#notes')).toBe(
      '/day/01ARZ3NDEKTSV4RRFFQ69G5FAV?date=2026-09-30#notes',
    );
    expect(safeNextPath('/')).toBe('/');
  });

  it('rejects nothing-at-all', () => {
    expect(safeNextPath(null)).toBeNull();
    expect(safeNextPath(undefined)).toBeNull();
    expect(safeNextPath('')).toBeNull();
  });

  it.each([
    'https://evil.example/invite',
    'http://evil.example',
    '//evil.example/invite',
    '///evil.example',
    '/\\evil.example',
    '\\\\evil.example',
    '/invite\\..\\..\\evil',
    'javascript:alert(1)',
    'data:text/html,<p>x',
    'evil.example/invite',
    'invite?code=ABC',
    ' /invite',
    '/invite\n//evil.example',
    '/\t/evil.example',
    '/invite\u0000',
  ])('rejects %j', (value) => {
    expect(safeNextPath(value)).toBeNull();
  });

  it.each([
    '/sign-in',
    '/sign-in?next=/sign-in',
    '/sign-in/code?email=a@b.co',
    '/sign-up',
    '/forgot-password',
    '/reset-password',
    '/auth/callback?code=x',
    '/auth/session',
  ])('rejects the sign-in screens themselves (%s), which would loop', (value) => {
    expect(safeNextPath(value)).toBeNull();
  });

  it('rejects a value too long to be a path anyone was sent to', () => {
    expect(safeNextPath(`/invite?code=${'A'.repeat(600)}`)).toBeNull();
  });

  it('normalises dot segments, so a path cannot climb into the auth screens', () => {
    expect(safeNextPath('/invite/../sign-in')).toBeNull();
    expect(safeNextPath('/a/../profiles')).toBe('/profiles');
  });
});

describe('withNext', () => {
  it('leaves a path alone when there is nowhere to return to', () => {
    expect(withNext('/sign-in', null)).toBe('/sign-in');
  });

  it('adds the return path, encoded, as the first or a further parameter', () => {
    expect(withNext('/sign-in', '/invite?code=A&kind=claim')).toBe(
      '/sign-in?next=%2Finvite%3Fcode%3DA%26kind%3Dclaim',
    );
    expect(withNext('/sign-in/code?email=a%40b.co', '/invite?code=A')).toBe(
      '/sign-in/code?email=a%40b.co&next=%2Finvite%3Fcode%3DA',
    );
  });

  it('round-trips through the address bar', () => {
    const target = '/invite?code=A&kind=claim';
    const url = new URL(withNext('/sign-in', target), 'https://x.invalid');
    expect(safeNextPath(url.searchParams.get('next'))).toBe(target);
  });
});
