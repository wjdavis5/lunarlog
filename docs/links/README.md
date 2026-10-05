# Invite/claim universal-link hosting (issue #129, app side; hosting: #384, #450)

The app side honours `https://<domain>/invite?code=...&profile=...&kind=...`
whenever a build carries `--dart-define=LUNARLOG_LINK_DOMAIN=<domain>`.

## Hosted domain and credentials

- **Hosted domain:** `lunarlog.app` (apex domain).
  - Also the candidate passkey relying-party ID (`PASSKEY_RP_ID`) for issue #30's activation.
- **Apple Developer Team ID:** `5273C9R3V4` (bundle ID: `com.wjdavis5.lunarlog`).
- **Android signing fingerprints:** Deferred. Play Store / Android release is deferred,
  so `assetlinks.json` remains in the repo as a template but is deliberately not published
  until real signing certificate fingerprints exist.

## Cloudflare Worker hosting (`site/`)

The apex domain `lunarlog.app` is served by one Cloudflare Worker (`site/`,
Worker source in `site/worker/`, Astro site in `site/src/`) with static assets,
deployed automatically by `.github/workflows/site-deploy.yml` (renamed from
`links-deploy.yml`, issue #1099):
- `/.well-known/apple-app-site-association` is served as `application/json`, 200, no redirect.
- `/invite*` serves `invite.html` with query strings preserved.
- `/fhir/*` is reserved (issue #961): a plain 404, never a redirect.
- All other paths are the Astro build output (`assets.directory` is `./dist`),
  including the styled 404 page (`not_found_handling: "404-page"`).
- `assets.run_worker_first` is `["/.well-known/*", "/invite*"]` (issue #1090), so the
  Worker owns both routes instead of the static-asset layer answering them first.
- `site/public/_headers` adds the strict, third-party-free response headers
  (CSP, HSTS, `X-Frame-Options: DENY`, no-referrer, nosniff, Permissions-Policy)
  to the static-asset responses. Worker-generated routes keep the headers
  `site/worker/index.ts` sets.
- `observability.logs.invocation_logs` is disabled (`false`) so request lines and query
  parameters are not retained.
- Custom domain route: `lunarlog.app` (Workers custom domain creates/binds the DNS record).
- The future web app (#831) can share or front this Worker.

**`www.lunarlog.app` -> apex is a follow-up (issue #1099).** Workers
static-asset `_redirects` does not support domain-level redirects, and the
Worker is only invoked for the `run_worker_first` paths, so the redirect needs
a Cloudflare Bulk Redirect (or an equivalent dashboard/zone rule) rather than
repo config. Until then `www.lunarlog.app` is not attached to the Worker.


## Where to serve each file

- `apple-app-site-association` at
  `https://lunarlog.app/.well-known/apple-app-site-association`, served as
  `application/json`, no redirects, no file extension in the URL.
- `assetlinks.json` at `https://lunarlog.app/.well-known/assetlinks.json` (deferred).
- `invite.html` for `https://lunarlog.app/invite*`, preserving the query
  string exactly (the code the app needs arrives only in the URL). The page
  deliberately offers only the custom-scheme `Open in lunarlog` button: the
  `Open in the web app` button (issue #1255) is withheld until #1258 serves
  the React client at `app.lunarlog.app` — until then that origin is the
  Flutter web build, which rejects https invite links (issue #1279).

## Privacy notes for the hoster

- Keep the page exactly as dependency-free as it is: no analytics, no
  third-party scripts, no cookies, no personalisation. The copy is
  deliberately neutral (no profile/child/inviter names).
- Disable HTTP access logging for `/invite*` if the hoster allows it: a
  redeemable code in a query string is visible to anything that logs
  request lines. The page itself (`no-referrer` + `noreferrer` links)
  never leaks it in a Referer header and never persists it anywhere.
