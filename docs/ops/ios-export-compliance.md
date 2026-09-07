# iOS export-compliance declaration

Operator checklist for lunarlog's App Store export-compliance answer
([plan](../plans/2026-09-05-001-chore-ios-export-compliance-declaration-plan.md),
issue [#48](https://github.com/wjdavis5/lunarlog/issues/48), closing review
finding #28 from issue #37). Reversed by the SQLCipher-removal /
US-Canada-only chore: the app no longer compiles a third-party at-rest
cipher into the binary. Tick items here as they are done; this is the
honest record of what the operator has and has not filed. Never record a
credential, CCATS number, or ERN value in this file — only whether one has
been obtained.

## What lunarlog encrypts (post-SQLCipher)

- **At-rest database encryption is now the OS's responsibility** — iOS Data
  Protection (native) / Android's platform encryption. The app no longer
  bundles a third-party cipher or manages its own database key; there is no
  `PRAGMA key`, no per-install key in `flutter_secure_storage` for the
  database, and no cipher-availability preflight at startup. See
  `lib/data/db/native_db.dart` and `lib/data/db/db_factory.dart`.
- **The device-credential gate is unrelated and unaffected** — `local_auth`
  still blocks the UI from showing any data until the device owner
  authenticates (biometric or passcode), independent of how the underlying
  file is stored. Removing the app-managed cipher did not touch this
  control.
- **TLS** to Supabase for cloud sync.
- **SHA-256** from `package:crypto` for OIDC nonces and invitation-token
  hashes.
- **`pointycastle`**, bundled transitively through the Supabase/auth stack
  (`pubspec.lock`); no `lib/` code imports it directly.
- **`flutter_secure_storage`** for the Supabase session and PKCE verifier
  (`lib/data/auth/secure_local_storage.dart`) — backed by the OS Keychain
  (iOS) / Keystore-wrapped EncryptedSharedPreferences (Android), not an
  app-compiled cipher.
- **Not part of this declaration:** the web build carries no
  export-compliance surface (browser storage is the platform's
  responsibility).

## Consistency anchor

This declaration must stay consistent with `PRIVACY.md`'s public claims. As
part of this reversal, `PRIVACY.md`'s SQLCipher/AES-256 lines were rewritten
to describe OS-level at-rest protection instead — see that file's own
history for the prior anchor text. If `PRIVACY.md`'s at-rest-encryption
description changes again, this declaration changes too.

## The classification and why

**No non-exempt encryption.** With the app-managed cipher removed, the only
cryptography left in the binary is: TLS (a standard exempt category —
HTTPS/TLS used for its ordinary purpose), OS-provided key storage via
`flutter_secure_storage` (exempt — limited to what the platform itself
provides), and hashing/signing used for authentication and token integrity
(exempt — authentication-only use). None of that is a compiled-in,
proprietary, confidentiality-purpose cipher over user data. Declaring
`ITSAppUsesNonExemptEncryption = false` reflects that.

This declaration is paired with restricting the app's App Store
availability to the United States and Canada (an App Store Connect
territory setting, not a code change) as an additional, independent
belt-and-suspenders measure — not a substitute for the technical exemption
analysis above.

**This is not a legal verdict.** The operator is expected to walk through
App Store Connect's own compliance questionnaire for the app/build and
confirm the exemption category it presents matches this reasoning, rather
than relying solely on this document.

## Where the declaration lives

1. `ios/Runner/Info.plist` — `ITSAppUsesNonExemptEncryption = false`. **This
   is authoritative**: App Store Connect reads it from the built binary, so
   it covers TestFlight uploads and manual submissions, not just
   `fastlane ios submit`.
2. `fastlane/Fastfile` — the `submit` lane's `submission_information`
   `export_compliance_*` answers, aligned to agree with the plist.
3. `.github/workflows/ios-release.yml` — the "Verify the exported bundle"
   step asserts the declaration survived the Xcode build into the archived
   `Runner.app`, failing the release if it did not.
4. `test/release/export_compliance_test.dart` — a repo guard test that
   fails if the sqlcipher build hook and the declaration ever disagree, in
   either direction (hook re-added without flipping the declaration back to
   true, or the declaration flipped to true with no hook present).

## Recurring operator actions

- [ ] Confirm the App Store Connect compliance questionnaire for the app
      agrees with a "no encryption" / fully-exempt answer once a build is
      uploaded — this may present as a one-time per-app question or a
      per-build "Missing Compliance" prompt.
- [ ] Set the app's App Store Connect availability to United States and
      Canada only (Pricing and Availability), if not already done.
- [ ] Decide the app's intended French App Store availability (the
      `export_compliance_available_on_french_store` answer) once the app is
      not US/Canada-restricted, if that ever changes.

## What to do if App Store Connect asks for compliance documentation or a code

This should not normally happen once the declaration is false, but if App
Store Connect nonetheless requests documentation or a code:

1. Obtain the real documentation or code first.
2. Add `ITSEncryptionExportComplianceCode` to `ios/Runner/Info.plist` with
   the real code.
3. Update `test/release/export_compliance_test.dart`'s R7 assertions to
   allow the now-legitimate code instead of forbidding it.
4. Re-evaluate whether `ITSAppUsesNonExemptEncryption` should actually be
   `true` — a request for a compliance code is a signal the classification
   above may be wrong for this app's actual configuration.

**Never flip the declaration to whichever value makes a prompt go away**
without re-deriving it from what the binary actually does — that is the
exact inaccuracy issue #48 originally closed.

## Re-check triggers

Re-open this checklist and `test/release/export_compliance_test.dart`
whenever:

- A crypto dependency is added or removed.
- An at-rest cipher (SQLCipher or otherwise) is added back to the
  `sqlite3` build hook or elsewhere.
- What the app encrypts, or how, changes.
- The App Store Connect availability territory list changes away from
  US/Canada-only.

## Scope note

This closes review finding #28 only. Findings #6, #7, and #25 — the wider
"release gates have no mechanical guard" group — remain open and are
tracked separately.
