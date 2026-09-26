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

## Cloudflare Worker hosting (`web/links/`)

The apex domain `lunarlog.app` is served by a Cloudflare Worker (`web/links/`) with
static assets, deployed automatically by `.github/workflows/links-deploy.yml`:
- `/.well-known/apple-app-site-association` is served as `application/json`, 200, no redirect.
- `/invite*` serves `invite.html` with query strings preserved.
- `observability.logs.invocation_logs` is disabled (`false`) so request lines and query
  parameters are not retained.
- Custom domain route: `lunarlog.app` (Workers custom domain creates/binds the DNS record).
- The future web app (#831) can share or front this Worker.

## Where to serve each file

- `apple-app-site-association` at
  `https://lunarlog.app/.well-known/apple-app-site-association`, served as
  `application/json`, no redirects, no file extension in the URL.
- `assetlinks.json` at `https://lunarlog.app/.well-known/assetlinks.json` (deferred).
- `invite.html` for `https://lunarlog.app/invite*`, preserving the query
  string exactly (the code the app needs arrives only in the URL).

## Privacy notes for the hoster

- Keep the page exactly as dependency-free as it is: no analytics, no
  third-party scripts, no cookies, no personalisation. The copy is
  deliberately neutral (no profile/child/inviter names).
- Disable HTTP access logging for `/invite*` if the hoster allows it: a
  redeemable code in a query string is visible to anything that logs
  request lines. The page itself (`no-referrer` + `noreferrer` links)
  never leaks it in a Referer header and never persists it anywhere.
