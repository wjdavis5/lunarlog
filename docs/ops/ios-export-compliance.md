# iOS export-compliance declaration

Operator checklist for lunarlog's App Store export-compliance answer
([plan](../plans/2026-09-05-001-chore-ios-export-compliance-declaration-plan.md),
issue [#48](https://github.com/wjdavis5/lunarlog/issues/48), closing review
finding #28 from issue #37). Tick items here as they are done; this is the
honest record of what the operator has and has not filed. Never record a
credential, CCATS number, or ERN value in this file — only whether one has
been obtained.

## What lunarlog encrypts

- **SQLCipher, AES-256, at rest.** `pubspec.yaml`'s `hooks: user_defines:
  sqlite3: source: sqlcipher` build hook makes `package:sqlite3` bundle
  SQLCipher instead of plain SQLite. `lib/data/db/native_db.dart` asserts
  `PRAGMA cipher_version` and applies `PRAGMA key` at open time — third-party
  encryption compiled into the binary, not OS-provided crypto.
- **Per-install key.** A 256-bit `Random.secure()` key held in
  `flutter_secure_storage` (`lib/data/db/key_store.dart`) — iOS Keychain,
  `first_unlock_this_device`, non-syncable.
- **SHA-256** from `package:crypto` for OIDC nonces and invitation-token
  hashes.
- **`pointycastle 4.0.0`**, bundled transitively through the Supabase/auth
  stack (`pubspec.lock`); no `lib/` code imports it directly.
- **TLS** to Supabase for cloud sync.
- **Not part of this declaration:** the web build is deliberately
  unencrypted (`LUNARLOG_WEB_SYNC` dev iteration only, never in CI or a
  shipped artifact) and carries no export-compliance surface.

## Consistency anchor

This declaration must stay consistent with `PRIVACY.md`'s public claims
(`:15`, `:65`, `:85`, `:89` — "encrypted at rest using SQLCipher (AES-256)").
If one changes, both change. Before this fix, `fastlane/Fastfile` told App
Store Connect the app used no encryption while `PRIVACY.md` told users the
opposite; that contradiction is what issue #48 / finding #28 flagged.

## The classification and why

**Non-exempt, third-party, non-proprietary encryption.** None of Apple's
listed export-compliance exemptions apply to a compiled-in third-party
at-rest database cipher: it isn't limited to OS-provided crypto, it isn't
HTTPS-only, it isn't authentication-only, its key is far above 56 bits, and
the app isn't US/Canada-only. Declaring `ITSAppUsesNonExemptEncryption =
true` is the accurate answer.

## Where the declaration lives

1. `ios/Runner/Info.plist` — `ITSAppUsesNonExemptEncryption = true`. **This
   is authoritative**: App Store Connect reads it from the built binary, so
   it covers TestFlight uploads and manual submissions, not just
   `fastlane ios submit`.
2. `fastlane/Fastfile` — the `submit` lane's `submission_information`
   `export_compliance_*` answers, aligned to agree with the plist.
3. `.github/workflows/ios-release.yml` — the "Verify the exported bundle"
   step asserts the key survived the Xcode build into the archived
   `Runner.app`, failing the release if it did not.
4. `test/release/export_compliance_test.dart` — a repo guard test that
   fails if the SQLCipher build hook and the declaration ever disagree, in
   either direction.

## Recurring operator actions

Answering "uses non-exempt encryption" puts the app on Apple's mass-market
self-classification path. These are operator actions outside the repo — no
code change satisfies them:

- [ ] Confirm the mass-market self-classification eligibility (ECCN
      5D992.c under License Exception ENC) applies to lunarlog's use of
      SQLCipher.
- [ ] Obtain an ERN (Encryption Registration Number) for
      `com.wjdavis5.lunarlog`, if App Store Connect requests one at
      submission.
- [ ] File the annual self-classification report to BIS/NSA, once
      required (typically triggered by the first qualifying submission).
- [ ] Decide the app's intended French App Store availability (the
      `export_compliance_available_on_french_store` answer) — left unset
      in `fastlane/Fastfile` rather than guessed; set it once the operator
      has an actual answer.

## What to do if App Store Connect asks for compliance documentation or a code

Obtain the real documentation or code first. Only then:

1. Add `ITSEncryptionExportComplianceCode` to `ios/Runner/Info.plist` with
   the real code.
2. Update `test/release/export_compliance_test.dart`'s R7 assertions to
   allow the now-legitimate code instead of forbidding it.

**Never flip the declaration back to `false`** to make the prompt go away —
that reintroduces the exact inaccuracy issue #48 closes.

## Re-check triggers

Re-open this checklist and `test/release/export_compliance_test.dart`
whenever:

- A crypto dependency is added or removed.
- The `sqlcipher` build hook in `pubspec.yaml` is dropped or changed.
- What the app encrypts, or how, changes.

## Scope note

This closes review finding #28 only. Findings #6, #7, and #25 — the wider
"release gates have no mechanical guard" group — remain open and are
tracked separately.
