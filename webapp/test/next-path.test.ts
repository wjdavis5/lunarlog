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

  // The limit is on what comes out, not only on what goes in. Resolving a
  // path percent-encodes it, and a letter outside ASCII grows ninefold: 58
  // characters used to come out as 514, which this function then refused
  // when the sign-in cookie handed the value back.
  it('rejects a short value that would grow past the limit once encoded', () => {
    expect(safeNextPath(`/${'中'.repeat(57)}`)).toBeNull();
    expect(safeNextPath(`/invite?note=${'é'.repeat(100)}`)).toBeNull();
    // One that still fits is kept, encoded.
    expect(safeNextPath('/invite?note=café')).toBe('/invite?note=caf%C3%A9');
  });

  it('accepts again whatever it accepted once', () => {
    const inputs = [
      '/invite?code=ABC123&kind=claim',
      '/invite?note=café ✓',
      `/${'中'.repeat(56)}`,
      `/invite?code=${'A'.repeat(512 - '/invite?code='.length)}`,
      '/a/../profiles?x=%2F#top',
      '/profile/01ARZ3NDEKTSV4RRFFQ69G5FAV/day/2026-10-05',
    ];
    for (const input of inputs) {
      const once = safeNextPath(input);
      expect(once, input).not.toBeNull();
      expect((once ?? '').length, input).toBeLessThanOrEqual(512);
      expect(safeNextPath(once), input).toBe(once);
    }
  });

  it('normalises dot segments, so a path cannot climb into the auth screens', () => {
    expect(safeNextPath('/invite/../sign-in')).toBeNull();
    expect(safeNextPath('/a/../profiles')).toBe('/profiles');
  });

  // Found in review: resolving a value removes its dot segments, and what
  // is left can be protocol-relative even though what was typed was not.
  // `/.//evil.example` came back as `//evil.example`, which a browser reads
  // as another site. Only the router's own refusal stood in the way.
  it.each([
    '/.//evil.example',
    '/.//evil.example/pwned',
    '/%2e//evil.example',
    '/%2E//evil.example',
    '/a/..//evil.example',
    '/a/%2e%2e//evil.example',
    '/.//user@evil.example',
    '/././/evil.example',
    '/invite/..//evil.example?code=A',
  ])('rejects %j, which resolves to a protocol-relative address', (value) => {
    expect(safeNextPath(value)).toBeNull();
  });

  // The router decodes a path before it matches one, so an encoded slash
  // or backslash must get no further than a literal one would.
  it.each([
    '/%2Fevil.example',
    '/%2fevil.example',
    '/%5Cevil.example',
    '/%5cevil.example',
    '/invite/%2F%2Fevil.example',
    '/%09/evil.example',
    '/invite%00',
    '/%',
    '/%E0%A4%A',
  ])('rejects %j, which decodes to something a literal path may not be', (value) => {
    expect(safeNextPath(value)).toBeNull();
  });

  it('rejects an empty path segment anywhere, which no page here has', () => {
    expect(safeNextPath('/invite//x')).toBeNull();
    expect(safeNextPath('/profiles//')).toBeNull();
  });

  // The router matches without regard to case or a trailing slash, and
  // after decoding. Each of these is a sign-in screen by another spelling.
  it.each([
    '/Sign-In',
    '/SIGN-UP',
    '/sign-in/',
    '/sign-up/',
    '/Sign-In/Code?email=a@b.co',
    '/AUTH/callback?code=x',
    '/auth',
    '/Forgot-Password/',
    '/RESET-PASSWORD',
    '/sign%2Din',
    '/%73ign-in',
    '/a/../Sign-Up',
  ])('rejects %s, a sign-in screen by another spelling', (value) => {
    expect(safeNextPath(value)).toBeNull();
  });

  it('still accepts a page whose name only starts like a sign-in screen', () => {
    expect(safeNextPath('/authors')).toBe('/authors');
    expect(safeNextPath('/sign-in-help')).toBe('/sign-in-help');
  });

  // Whatever comes back, however it was spelled going in, is a path on
  // this site. Every combination below is hostile or malformed; most are
  // refused, and the few that survive must still be harmless.
  it('never returns a way off the site, for any mix of prefix and target', () => {
    const prefixes = [
      '/',
      '//',
      '/.',
      '/./',
      '/..',
      '/../',
      '/a/..',
      '/a/../',
      '/%2e',
      '/%2e/',
      '/%2e%2e/',
      '/%252e/',
      '/%2f',
      '/%252f',
      '/%5c',
      '/\\',
      '/;',
      '/?',
      '/#',
      '/@',
      '/ ',
      '/%20',
      '/\t',
    ];
    const targets = [
      '/evil.example',
      '//evil.example',
      'evil.example',
      '@evil.example',
      '\\evil.example',
      '%2Fevil.example',
      '%5Cevil.example',
      'https://evil.example',
      'javascript:alert(1)',
    ];
    const origin = 'https://app.example';
    let survivors = 0;
    for (const prefix of prefixes) {
      for (const target of targets) {
        const candidate = `${prefix}${target}`;
        const result = safeNextPath(candidate);
        if (result === null) continue;
        survivors += 1;
        expect(result.startsWith('/'), candidate).toBe(true);
        expect(result.startsWith('//'), candidate).toBe(false);
        expect(result.includes('\\'), candidate).toBe(false);
        const resolved = new URL(result, origin);
        expect(resolved.origin, candidate).toBe(origin);
        expect(resolved.pathname.includes('//'), candidate).toBe(false);
        expect(decodeURIComponent(resolved.pathname).includes('//'), candidate).toBe(false);
      }
    }
    // A scan in which nothing survived would prove nothing about survivors.
    expect(survivors).toBeGreaterThan(0);
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
