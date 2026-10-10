# Play Store release runbook

`.github/workflows/play-store-release.yml` builds, signs, and publishes the
Android app to Google Play. It is manual dispatch only. As of 2026-10-10 it
has never completed a green run, because its credentials have never been
provisioned (issue #1791). This runbook is the owner's path to the first
green run.

## Why the first runs failed

Both runs, on 2026-09-02 and 2026-09-03, failed in "Configure Android
signing key" with `Secret ANDROID_KEYSTORE_BASE64 is empty or not
configured`. Nothing else in the workflow was wrong at that point. The
workflow has since grown a `preflight` job (issue #1791) that runs first,
fails in seconds, and names every missing secret at once, so a credentials
problem is one red job rather than a build that dies part-way through.

## What to provision

Five repository secrets. Names and contents only; never commit values.

1. `ANDROID_KEYSTORE_BASE64`. The release keystore, base64-encoded. Create
   one with `keytool -genkeypair -v -keystore release.jks -alias <alias>
   -keyalg RSA -keysize 2048 -validity 10000`, then encode it. On Windows,
   PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))`.
   On macOS or Linux, `base64 -i release.jks` or `base64 -w0 release.jks`.
   Keep the `.jks` file itself outside the repo, and back it up. Losing it
   means losing the ability to update the Play listing under the same
   signing identity.
2. `ANDROID_KEYSTORE_PASSWORD`. The keystore password.
3. `ANDROID_KEY_ALIAS`. The key alias inside the keystore.
4. `ANDROID_KEY_PASSWORD`. The key's own password.
5. `PLAY_STORE_JSON_KEY`. A Google Cloud service account key JSON with the
   Google Play Android Developer API enabled, and the service account
   invited in Play Console under Users and permissions with release
   permissions for lunarlog.

Set them with:

```bash
gh secret set ANDROID_KEYSTORE_BASE64 --repo wjdavis5/lunarlog < release.jks.b64
gh secret set ANDROID_KEYSTORE_PASSWORD --repo wjdavis5/lunarlog
gh secret set ANDROID_KEY_ALIAS --repo wjdavis5/lunarlog
gh secret set ANDROID_KEY_PASSWORD --repo wjdavis5/lunarlog
gh secret set PLAY_STORE_JSON_KEY --repo wjdavis5/lunarlog < play-service-account.json
```

The keystore secret's value is the base64 text, not the raw `.jks` file.
For the passwords, let `gh` prompt rather than passing `--body`, so the
values stay out of shell history.

## Dispatch

```bash
gh workflow run play-store-release.yml --repo wjdavis5/lunarlog -f track=internal
```

Inputs: `track` (internal, alpha, beta, or production), `qa_build` (internal
track only), and `confirm_production` (type `production` for a production
dispatch).

The gates that run before the build, in order: the secrets preflight, the
production release gate (`RELEASE_GATE_ACCOUNT_DELETION`), the Play health
declaration gate, the Supabase migrations gate, the QA build gate, the CI
check-runs gate, then analyze and test. The versionCode is clamped above
the highest Play already holds in the same namespace (production 1xxx, QA
501xxx).

## Expected outputs

- The run's artifacts: `app-release.aab` (uploaded to Play) and
  `app-release.apk` (kept on the run).
- The build appears on the selected track in Play Console.
- A green run is issue #1791's acceptance.

## Verifying the credentials without a release

Dispatch to `internal`. The preflight and the signing step prove the
credentials before the build does real work. If the signing step fails on
the base64 decode, the secret is malformed rather than missing.

## Not yet provisioned, and not checked by the preflight

- The six client-side `FCM_*` secrets are unset, so a release build today
  compiles without push, and caregiver alerts do not reach the device.
  Provisioning them is part of the launch checklist, issue #1797.
- `SENTRY_AUTH_TOKEN` is unset, so the debug-symbol upload step warns and
  skips. That step is deliberately non-fatal. Tracked in issue #19.
