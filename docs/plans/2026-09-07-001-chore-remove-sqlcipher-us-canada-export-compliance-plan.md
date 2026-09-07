---
title: Remove SQLCipher, Restrict to US/Canada, Flip Export Compliance - Plan
type: chore
date: 2026-09-07
issue: n/a (operator decision, no tracked issue)
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Remove SQLCipher, Restrict to US/Canada, Flip Export Compliance - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths below are repo-relative.

---

## Goal Capsule

- **Objective:** Unblock iOS TestFlight releases, which were failing App
  Store Connect's export-compliance check ("Invalid Export Compliance
  Code", code 90592) on every recent upload. Rather than obtain a
  compliance code for the existing non-exempt-encryption declaration
  (issue #48's `chore-ios-export-compliance-declaration` work), the
  operator chose to reverse that declaration: remove the app-managed
  at-rest cipher (SQLCipher) entirely, rely on OS-provided at-rest
  protection instead, and restrict App Store distribution to the US and
  Canada.
- **Means:** Drop the `sqlite3`/`sqlcipher` build hook; delete the
  key-management code that existed solely to feed it
  (`lib/data/db/key_store.dart`); simplify the database factory
  (`lib/data/db/db_factory.dart`, `native_db.dart`) to a plain
  file-backed `QueryExecutor`; remove the two cipher-specific fail-closed
  error types (`EncryptionUnavailableError`, `CorruptDatabaseKeyError`) and
  their fail-closed-screen copy, keeping the cipher-independent
  `DatabaseQuarantineError`; flip `ITSAppUsesNonExemptEncryption` to
  `false` in `ios/Runner/Info.plist`, `fastlane/Fastfile`, and
  `ios-release.yml`'s bundle-verification assertion; rewrite
  `docs/ops/ios-export-compliance.md`'s classification and `PRIVACY.md`'s
  two anchored claims accordingly; rework
  `test/release/export_compliance_test.dart`'s guard to assert the
  inverse agreement (no hook, declaration false) instead of the original
  (hook present, declaration true).
- **Authority hierarchy:** This document's Key Technical Decisions own the
  scope of what changes; existing docs
  (`docs/ops/ios-export-compliance.md`, `AGENTS.md`'s security guidelines)
  are the reference for what must stay consistent with what.
- **Stop conditions:** Never claim
  `ITSEncryptionExportComplianceCode` without a real code in hand (R7 of
  the original declaration plan still holds, just aimed at the opposite
  boolean). Never leave the device-credential gate (`local_auth`,
  biometric/passcode) weakened — it is an independent control from the
  at-rest cipher and is unaffected by this change.
- **Execution profile:** `code`; cross-cutting but mechanical — no new
  runtime feature, a deletion/simplification of an existing one plus a
  compliance-declaration flip.
- **Explicit trade-off accepted by the operator:** this is a security
  regression for a minors'-health-data app — the local database no longer
  has an app-managed, per-install AES-256 key independent of the OS. The
  device-credential gate (biometric/passcode before any data is shown)
  is unaffected and remains the primary access control.

---

## Problem Frame

Every recent `ios-release.yml` run failed at the TestFlight upload step with
Apple's `altool` reporting: *"Invalid Export Compliance Code. The export
compliance key value `[]` in the app's Info.plist doesn't match the key
value of the app's export compliance documentation."* App Store Connect had
compliance documentation on file expecting a code that the binary's
`Info.plist` did not carry (empty). The two ways to resolve this were (a)
obtain the expected code/complete the App Store Connect questionnaire for
the existing `true` declaration, or (b) make the declaration accurately
`false` by removing the non-exempt encryption that required it in the
first place. The operator chose (b), paired with an availability
restriction to the US and Canada as an additional measure.

---

## Requirements

- **R1.** No third-party at-rest cipher is compiled into the app on any
  platform (`pubspec.yaml` carries no `sqlite3`/`sqlcipher` build hook).
- **R2.** `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption =
  false`, accurately reflecting R1 and the remaining crypto surface (TLS,
  OS-provided key storage, authentication-only hashing/signing).
- **R3.** `fastlane/Fastfile`'s `submission_information` agrees with R2.
- **R4.** `.github/workflows/ios-release.yml`'s "Verify the exported
  bundle" step asserts the exported binary carries `false`, not `true`.
- **R5.** `test/release/export_compliance_test.dart` fails if the
  build-hook fact and the declaration ever disagree again, in either
  direction.
- **R6.** `PRIVACY.md`'s at-rest-encryption claims and
  `docs/ops/ios-export-compliance.md`'s classification are rewritten to
  match R1-R2, not left stating a cipher that no longer exists.
- **R7.** The device-credential gate (`lib/data/gate/`, `local_auth`)
  keeps working exactly as before — no data is shown without a
  successful biometric/passcode check, regardless of at-rest storage.
- **R8.** No `ITSEncryptionExportComplianceCode` is asserted anywhere
  without a real code in hand.
- **R9 (operator, out-of-repo).** App Store Connect's "Pricing and
  Availability" is set to United States and Canada only.

---

## Key Technical Decisions

- **KTD1 — `DatabaseQuarantineError` survives; the two cipher-specific
  error types do not.** `EncryptionUnavailableError` (no cipher support)
  and `CorruptDatabaseKeyError` (malformed persisted key) exist solely
  because of the app-managed cipher and key store; both are deleted along
  with `key_store.dart`. `DatabaseQuarantineError` protects *any* existing
  file that fails to open or migrate, cipher or not, and is kept as the
  sole fail-closed error class.
- **KTD2 — the `deleteDbKey` device-reset seam is removed, not left as a
  no-op.** `LunarLogRoot.deleteDbKey` (and its default
  `SecureDbKeyStore().deleteKey()`) existed only to delete the cipher key
  as the second half of the file-then-key reset ordering (AE10). With no
  key, this callback would be a permanent no-op; removed instead of kept
  as dead plumbing, along with the tests that pinned its ordering.
- **KTD3 — `ITSAppUsesNonExemptEncryption` flips to `false`, not a
  narrower non-exempt exemption category.** After removal, the app's only
  cryptographic surface is TLS, OS-provided secure storage
  (`flutter_secure_storage`), and authentication/integrity hashing —
  standard exempt categories. The operator explicitly chose the "no
  non-exempt encryption" answer over staying `true` under a narrower EAR
  exemption; `docs/ops/ios-export-compliance.md` is written accordingly,
  with an explicit note that App Store Connect's own questionnaire is
  still the operator's confirmation step, not this document.
- **KTD4 — Android has no separate SQLCipher wiring to remove.** The
  `sqlite3` build hook applies uniformly across platforms; there was never
  an Android-specific toggle. Android's baseline (OS full-disk/file-based
  encryption, `allowBackup="false"`) is unchanged by this removal.
- **KTD5 — historical plan docs that mention SQLCipher are left
  untouched.** `docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md`,
  `docs/plans/2026-09-03-0824-create-privacy-policy-plan.md`, and
  `docs/plans/2026-09-05-001-chore-ios-export-compliance-declaration-plan.md`
  are point-in-time records of decisions made when SQLCipher was in use;
  per this repo's convention, plan docs are historical artifacts, not
  living documentation, and are not retroactively edited.

---

## Verification

- `flutter analyze` clean.
- `flutter test` and `dart run tool/quality_gate.dart` pass (coverage
  floor + CRAP gate).
- Local run of `test/release/export_compliance_test.dart` confirms the
  reversed guard.
- Manual re-run of `ios-release.yml` after merge confirms the migration
  gate, release gate, and TestFlight upload all succeed with no export
  compliance error.
- Operator confirms App Store Connect availability is US/Canada only
  (R9 — not verifiable from the repo).
