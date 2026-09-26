#!/usr/bin/env node
// tool/web_smoke/boot_check.mjs
//
// Issue #1091: the headless-browser regression guard for the web build.
//
// A build can pass `flutter analyze`, compile, and even carry the right
// `_headers`/`_redirects` files, and still blank-page in a browser: Flutter's
// loader can fetch CanvasKit from `www.gstatic.com`, which the deployed CSP
// blocks. A header-parsing test cannot see that. This script serves the real
// `build/web` under the real `_headers` policy and loads it in headless
// Chromium, failing unless the app paints a first frame with no
// Content-Security-Policy violation that is not on the explicit allowlist
// below.
//
// What it does:
//   1. Serves `build/web` on 127.0.0.1, applying every header from
//      `build/web/_headers` except `Strict-Transport-Security`, and with
//      `upgrade-insecure-requests` stripped from the CSP (the server is plain
//      HTTP, so the browser must not rewrite same-origin requests to HTTPS).
//      It implements `_redirects`'s `/* /index.html 200` SPA fallback: a path
//      with no file on disk serves `index.html` with a 200.
//   2. Loads `/` in headless Chromium. It records every
//      `securitypolicyviolation` event (and any console line naming a
//      Content-Security-Policy refusal) and waits for Flutter's first frame
//      via the `flutter-first-frame` window event.
//   3. Fails if any violation is not allowlisted, if no first frame lands
//      within the timeout, or if the `#loading` overlay is still in the DOM
//      after the first frame (it must be removed by `web/loading_overlay.js`,
//      or screen readers keep announcing it).
//
// Usage (from this directory):
//   npm ci
//   npx playwright install chromium          # add --with-deps chromium on Linux CI
//   node boot_check.mjs
//
// Input (env):
//   WEB_BUILD_DIR    Build output directory. Defaults to `<repo>/build/web`.
//   BOOT_TIMEOUT_MS  First-frame timeout in milliseconds. Defaults to 60000.
//
// Exit code: 0 when the build boots cleanly, non-zero otherwise.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium } from 'playwright';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, '..', '..');
const buildDir = resolve(
  process.env.WEB_BUILD_DIR ?? join(repoRoot, 'build', 'web'),
);
const firstFrameTimeoutMs = Number(process.env.BOOT_TIMEOUT_MS ?? 60000);

// Every entry names the blocked URL and why leaving it blocked is safe. THE
// LIST STARTS EMPTY: an entry is added only when a request cannot be removed
// from the build, and the comment must say exactly that. A violation on an
// entry that does not match by URL fails the check.
const ALLOWLIST = [
  {
    // `google_sign_in_web`'s GoogleSignInPlugin constructor calls
    // `loader.loadWebSdk()` when the web plugin registers -- before the app
    // ever touches GoogleSignIn. Google Sign-In is hidden on web
    // (`AppConfig.hasGoogle` excludes web), so the script is blocked by
    // `script-src 'self'` and never runs; this is console noise only, and
    // issue #1096 revisits it. See the PR's "Not done".
    pattern: /^https:\/\/accounts\.google\.com\/gsi\/client(?:[?#]|$)/,
    reason:
      'google_sign_in_web plugin registration; Google is hidden on web and ' +
      'the script stays blocked.',
  },
  {
    // `sentry_flutter` loads its JS SDK from a hardcoded Sentry CDN URL when a
    // DSN is configured (`SENTRY_DSN`). The SDK exposes no option to self-host
    // or skip that bundle cleanly, so `script-src 'self'` blocks it and it
    // stays blocked; Dart-level error capture is unaffected. See the PR's
    // "Not done".
    pattern: /^https:\/\/browser\.sentry-cdn\.com\/.*\/bundle\.tracing(?:\.min)?\.js$/,
    reason:
      'sentry_flutter JS SDK CDN; blocked and never loaded (no self-host ' +
      'option exists).',
  },
];

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
  '.bin': 'application/octet-stream',
};

/// Parses a Cloudflare/Netlify `_headers` document into a
/// `header-name -> value` map. Selector lines, blanks, and `#` comments are
/// ignored; header lines are the indented `Name: value` pairs. The build only
/// uses the `/*` selector, so a single flat map is enough.
function parseHeaderFile(contents) {
  const headers = {};
  for (const raw of contents.split('\n')) {
    if (!raw.trim()) continue;
    if (raw.trimStart().startsWith('#')) continue;
    if (!raw.startsWith(' ') && !raw.startsWith('\t')) continue;
    const colon = raw.indexOf(':');
    if (colon < 0) continue;
    const name = raw.slice(0, colon).trim();
    const value = raw.slice(colon + 1).trim();
    if (name) headers[name] = value;
  }
  return headers;
}

/// The headers actually served: the `_headers` policy minus HSTS (plain-HTTP
/// localhost) and minus `upgrade-insecure-requests` (which would rewrite
/// same-origin requests to HTTPS that nothing is listening on).
function servedHeaders(raw) {
  const headers = { ...raw };
  for (const name of Object.keys(headers)) {
    if (name.toLowerCase() === 'strict-transport-security') delete headers[name];
  }
  for (const name of Object.keys(headers)) {
    if (name.toLowerCase() !== 'content-security-policy') continue;
    headers[name] = headers[name]
      .split(';')
      .map((directive) => directive.trim())
      .filter(
        (directive) =>
          directive && !/^upgrade-insecure-requests$/i.test(directive),
      )
      .join('; ');
  }
  return headers;
}

function contentTypeFor(pathname) {
  const dot = pathname.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  return MIME_TYPES[pathname.slice(dot).toLowerCase()] ?? 'application/octet-stream';
}

async function main() {
  const indexPath = join(buildDir, 'index.html');
  let headersRaw = {};
  try {
    headersRaw = parseHeaderFile(await readFile(join(buildDir, '_headers'), 'utf8'));
  } catch {
    fail(`'${buildDir}/_headers' is missing; the build was not served under its real policy.`);
  }
  const headers = servedHeaders(headersRaw);
  let redirects = '';
  try {
    redirects = await readFile(join(buildDir, '_redirects'), 'utf8');
  } catch {
    // No `_redirects` means no SPA fallback; still check the boot, but deep
    // links are a separate concern the shell script already fails on.
  }
  const spaFallback = /^\s*\/\*\s+\/index\.html\s+200\s*$/m.test(redirects);

  const server = createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    let pathname = decodeURIComponent(url.pathname);
    if (pathname.endsWith('/')) pathname += 'index.html';
    const relative = pathname.replace(/^\/+/, '');
    const candidate = resolve(buildDir, relative);
    // Reject path traversal outright; fall through to the SPA fallback.
    const inBuild = candidate === buildDir || candidate.startsWith(buildDir + sep);
    let body;
    let status = 200;
    let contentTypePath = candidate;
    if (!inBuild) {
      status = 404;
      body = Buffer.from('not found');
    } else {
      try {
        body = await readFile(candidate);
      } catch {
        if (spaFallback) {
          body = await readFile(indexPath);
          contentTypePath = indexPath;
        } else {
          status = 404;
          body = Buffer.from('not found');
        }
      }
    }
    res.writeHead(status, {
      ...headers,
      'Content-Type':
        status === 200
          ? contentTypeFor(contentTypePath)
          : 'text/plain; charset=utf-8',
    });
    res.end(body);
  });

  await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen));
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/`;
  console.log(`Boot check: serving ${buildDir} at ${url}`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  await context.addInitScript(() => {
    window.__lunarlogCspViolations = [];
    window.__lunarlogFirstFrame = false;
    const record = (event) => {
      const entry = {
        blockedURI: event.blockedURI ?? '',
        violatedDirective: event.violatedDirective ?? '',
        effectiveDirective: event.effectiveDirective ?? '',
        sourceFile: event.sourceFile ?? '',
        lineNumber: event.lineNumber ?? 0,
      };
      // The event is dispatched once; guard against a double listener.
      const key = JSON.stringify(entry);
      if (!window.__lunarlogCspViolations.some((v) => v.__key === key)) {
        window.__lunarlogCspViolations.push({ ...entry, __key: key });
      }
    };
    document.addEventListener('securitypolicyviolation', record);
    window.addEventListener('securitypolicyviolation', record);
    window.addEventListener('flutter-first-frame', () => {
      window.__lunarlogFirstFrame = true;
    });
  });

  const page = await context.newPage();
  const consoleViolations = [];
  page.on('console', (message) => {
    const text = message.text();
    if (/content security policy/i.test(text)) consoleViolations.push(text);
  });
  page.on('pageerror', (error) => {
    // A page error is not automatically a CSP failure, but print it for the
    // PR body so a non-CSP boot failure is visible.
    console.log(`[pageerror] ${error.message}`);
  });

  const startedAt = Date.now();
  let firstFrameMs = null;
  let loadingRemoved = false;
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForFunction(() => window.__lunarlogFirstFrame === true, null, {
      timeout: firstFrameTimeoutMs,
    });
    firstFrameMs = Date.now() - startedAt;
    // Let any late fallback font / worker requests surface their violations,
    // and give web/loading_overlay.js a moment to remove `#loading`.
    await page.waitForTimeout(2000);
    loadingRemoved = await page.evaluate(
      () => document.getElementById('loading') === null,
    );
  } catch (error) {
    console.log(`First frame not observed within ${firstFrameTimeoutMs} ms: ${error.message}`);
  }

  const events = await page.evaluate(
    () => window.__lunarlogCspViolations ?? [],
  );
  await browser.close();
  server.close();

  const allowlisted = (value) => ALLOWLIST.find((entry) => entry.pattern.test(value));
  const blockedEvents = events.filter((event) => !allowlisted(event.blockedURI));
  const allowedEvents = events.filter((event) => allowlisted(event.blockedURI));

  // Console lines carry one or more URLs; treat a line as allowed only if
  // every URL it names is allowlisted.
  const blockedConsole = [];
  const allowedConsole = [];
  for (const text of consoleViolations) {
    const urls = text.match(/https?:\/\/[^\s'"`]+/g) ?? [];
    if (urls.length === 0 || urls.some((u) => !allowlisted(u))) {
      blockedConsole.push(text);
    } else {
      allowedConsole.push(text);
    }
  }

  console.log('');
  console.log(`First frame: ${firstFrameMs === null ? 'NOT RENDERED' : `rendered in ${firstFrameMs} ms`}`);
  console.log(`Loading overlay removed: ${loadingRemoved ? 'yes' : 'NO'}`);
  console.log(`CSP violations: ${events.length} event(s), ${consoleViolations.length} console line(s)`);
  for (const event of allowedEvents) {
    const entry = allowlisted(event.blockedURI);
    console.log(`  [allowlisted] ${event.blockedURI} (${event.violatedDirective})`);
    console.log(`      ${entry.reason}`);
  }
  for (const event of blockedEvents) {
    console.log(`  [BLOCKED] ${event.blockedURI || '(inline/empty)'} (${event.violatedDirective}) from ${event.sourceFile}:${event.lineNumber}`);
  }
  for (const text of allowedConsole) {
    console.log(`  [allowlisted console] ${text}`);
  }
  for (const text of blockedConsole) {
    console.log(`  [BLOCKED console] ${text}`);
  }

  if (firstFrameMs === null) {
    fail('The app never painted a first frame under its own CSP.');
  }
  if (!loadingRemoved) {
    fail(
      'The #loading overlay is still in the DOM after the first frame; it ' +
        'stays in the accessibility tree and screen readers keep announcing ' +
        'it. web/loading_overlay.js must remove it on flutter-first-frame.',
    );
  }
  if (blockedEvents.length > 0 || blockedConsole.length > 0) {
    fail(
      `The build produced ${blockedEvents.length + blockedConsole.length} CSP violation(s) ` +
        'not on the explicit allowlist. Fix the request, or add a URL-matched ' +
        'allowlist entry with a comment naming why leaving it blocked is safe.',
    );
  }
  console.log('');
  console.log('Boot check passed: first frame rendered with no unexpected CSP violation.');
}

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}

main().catch((error) => fail(error?.stack ?? String(error)));
