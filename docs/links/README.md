# Invite/claim universal-link hosting (issue #129, app side; hosting: #384)

The app side honours `https://<domain>/invite?code=...&profile=...&kind=...`
whenever a build carries `--dart-define=LUNARLOG_LINK_DOMAIN=<domain>`.
These three files are the human-operated half, ready to host once the
domain, DNS, and hosting from issue #384 exist. Nothing here is referenced
by the app or by any workflow; live validation against Apple's and
Google's checkers is explicitly not done (no domain exists yet).

## Placeholders to replace

- `__LUNARLOG_LINK_DOMAIN__` — the hosted domain, in:
  `ios/Runner/Runner.entitlements`, `ios/Runner/DebugProfile.entitlements`
  (`applinks:` entry), and
  `android/app/src/main/AndroidManifest.xml` (App Link intent-filter host).
- `__TEAMID__` — the Apple Developer Team ID, in
  `docs/links/apple-app-site-association` (`appID`).
- `__SHA256_CERT_FINGERPRINT__` — the Android signing certificate's
  SHA-256 fingerprint, in `docs/links/assetlinks.json`. Release and debug
  fingerprints differ; list each certificate that must verify.

## Where to serve each file

- `apple-app-site-association` at
  `https://<domain>/.well-known/apple-app-site-association`, served as
  `application/json`, no redirects, no file extension in the URL.
- `assetlinks.json` at `https://<domain>/.well-known/assetlinks.json`,
  served as `application/json`.
- `invite.html` for `https://<domain>/invite*`, preserving the query
  string exactly (the code the app needs arrives only in the URL).

## Privacy notes for the hoster

- Keep the page exactly as dependency-free as it is: no analytics, no
  third-party scripts, no cookies, no personalisation. The copy is
  deliberately neutral (no profile/child/inviter names).
- Disable HTTP access logging for `/invite*` if the hoster allows it: a
  redeemable code in a query string is visible to anything that logs
  request lines. The page itself (`no-referrer` + `noreferrer` links)
  never leaks it in a Referer header and never persists it anywhere.
