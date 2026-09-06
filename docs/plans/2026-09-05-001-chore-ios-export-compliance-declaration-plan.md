---
title: Declare Non-Exempt Encryption for SQLCipher in iOS Export Compliance - Plan
type: chore
date: 2026-09-05
issue: wjdavis5/lunarlog#48
origin: wjdavis5/lunarlog#37 (code review finding #28)
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Declare Non-Exempt Encryption for SQLCipher in iOS Export Compliance - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths below are repo-relative.

---

## Goal Capsule

- **Objective:** Make lunarlog's iOS export-compliance declaration truthful and deterministic. The app compiles SQLCipher in and applies `PRAGMA key` at open time, yet `fastlane/Fastfile:47` tells App Store Connect the app does not use encryption. Replace that with an accurate declaration that travels with every binary and cannot silently drift.
- **Means:** Add `ITSAppUsesNonExemptEncryption` to `ios/Runner/Info.plist` (the declaration then ships inside the built `Runner.app`), align `fastlane/Fastfile`'s `submission_information` so it can never contradict the plist, extend the existing "Verify the exported bundle" CI step to assert the key is present in the *exported* binary, add a repo guard test tying the declaration to the SQLCipher build hook, and record the classification decision plus the operator's recurring filing duties in `docs/ops/`.
- **Authority hierarchy:** Issue #48 owns the requirement; this document's Key Technical Decisions own the classification and the mechanics; the implementation units own file-level execution.
- **Stop conditions:** Stop and surface to the operator if implementation would require asserting a CCATS / ERN / compliance code that the operator has not actually obtained. This plan declares what is true and documents the filing obligation; it must never invent a compliance code, and must never flip the declaration back to "no encryption" to make a submission pass.
- **Execution profile:** `code`; Standard depth. No Dart runtime behavior changes — this is release configuration, CI verification, a guard test, and an operator decision record.
- **Scope note:** This closes review finding #28 only. Findings #6, #7, and #25 (the wider "release gates have no mechanical guard" group) stay open.

---

## Problem Frame

`fastlane/Fastfile:47` sends `export_compliance_uses_encryption: false` to App Store Connect on every `submit_for_review` run. That answer is false in fact:

- `pubspec.yaml:80-87` sets `hooks: user_defines: sqlite3: source: sqlcipher`, which makes `package:sqlite3`'s native build hook bundle **SQLCipher** instead of plain SQLite. This is a third-party encryption implementation compiled into the shipped binary. (There is no `sqlite3_flutter_libs` / `sqlcipher_flutter_libs` plugin and no `ios/Podfile` — the build hook is the whole wiring, which is why the SQLCipher fact is easy to miss.)
- `lib/data/db/native_db.dart` asserts `PRAGMA cipher_version` is available (`:24-32`, failing closed via `EncryptionUnavailableError`) and applies `PRAGMA key` (`:39`) — AES-256 encryption of data at rest, keyed by a per-install 256-bit `Random.secure()` key held in `flutter_secure_storage` (`lib/data/db/key_store.dart`).
- `pointycastle 4.0.0` is bundled transitively through the Supabase/auth stack (`pubspec.lock`), even though no `lib/` code imports it directly.
- `PRIVACY.md` already tells users, publicly, that the local database is "encrypted at rest using SQLCipher (AES-256)" (`:15`, `:85`). The App Store declaration currently contradicts the app's own published privacy policy.

Apple's listed export-compliance exemptions cover apps whose encryption is limited to what the OS provides, HTTPS calls, authentication only, keys of 56 bits or less, or US/Canada-only availability. A compiled-in third-party AES-256 database cipher fits none of them, so the "no encryption" answer is inaccurate rather than merely conservative.

Two consequences follow, and both matter more than the single wrong boolean:

1. **The declaration does not travel with the binary.** It exists only in a Ruby lane that runs on the `submit_for_review` path. A build uploaded to TestFlight, or submitted by any route other than `fastlane ios submit`, carries no declaration at all — App Store Connect then asks the question interactively and a human answers it from memory.
2. **Nothing couples the declaration to the fact it describes.** If someone later drops the SQLCipher hook, or adds another crypto dependency, no test or CI step notices that the compliance answer has gone stale in either direction.

---

## Requirements

- **R1.** The shipped iOS binary must itself declare its encryption usage: `ITSAppUsesNonExemptEncryption` present in `ios/Runner/Info.plist`, so the answer is identical for a TestFlight upload, a manual submission, and a `fastlane ios submit` run.
- **R2.** The declared value must be accurate for what lunarlog actually compiles in — non-exempt, third-party, non-proprietary encryption (SQLCipher / AES-256 at rest).
- **R3.** `fastlane/Fastfile`'s `submission_information` must agree with the Info.plist declaration rather than contradict it, and must supply the sibling `export_compliance_*` answers that become meaningful once encryption usage is admitted.
- **R4.** The `ios-release.yml` "Verify the exported bundle" step must fail the release if the exported `Runner.app` does not carry the expected declaration — proving R1 against the actual artifact, not the source tree.
- **R5.** A repo test must fail if the declaration and the SQLCipher build hook ever disagree, in either direction (hook removed but declaration kept, or declaration weakened while the hook stays).
- **R6.** The classification rationale and the operator's recurring, out-of-code obligations (annual self-classification report, ERN, and what to do if App Store Connect asks for compliance documentation) must be written down where the release checklists already live, and must be consistent with the encryption claims `PRIVACY.md` already makes publicly.
- **R7.** No compliance code, CCATS number, or ERN may be asserted in the repo unless the operator has actually obtained it.

---

## Key Technical Decisions

### KTD1. Declare non-exempt encryption (`ITSAppUsesNonExemptEncryption = true`), not an exemption

lunarlog compiles SQLCipher into the binary and encrypts the local database with AES-256. None of Apple's listed exemption categories (OS-provided crypto only, HTTPS only, authentication only, ≤56-bit keys, US/Canada-only distribution) apply to a third-party at-rest database cipher. Declaring `true` is the accurate answer, and it is what issue #48 asks for.

The alternative — keeping an exemption claim — was rejected: it is the current state and it is what finding #28 flags as wrong. See *Alternatives Considered*.

**Consequence the operator must accept:** answering "uses non-exempt encryption" moves the app onto the mass-market self-classification path (ECCN 5D992.c under License Exception ENC). App Store Connect may ask for compliance documentation or a compliance code on submission. That filing is an operator action, not a code change — U5 records it, and R7 forbids fabricating a code to satisfy the prompt.

### KTD2. Info.plist is the single source of truth; Fastlane is aligned, not authoritative

When `ITSAppUsesNonExemptEncryption` is present in the bundle's Info.plist, App Store Connect reads the answer from the binary and stops asking per-build. That is exactly the "declarations travel deterministically with every binary" property issue #48 asks for, and it covers upload paths the fastlane lane never touches.

`fastlane/Fastfile` is therefore updated to *agree* rather than to carry the decision alone — a lane that still said `false` would be a contradiction sitting in the repo waiting to be believed by the next reader, even if App Store Connect ignored it.

### KTD3. Verify in the exported artifact, not just the source plist

`ios-release.yml` already has a "Verify the exported bundle" step that runs `plutil -extract` against `build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist` and hard-fails on a wrong bundle id, a too-low `MinimumOSVersion`, or a missing `PrivacyInfo.xcprivacy`. The compliance declaration belongs in exactly that step: it is the only check that proves the key survived the Xcode build into the artifact that gets uploaded. A source-tree test alone cannot prove that (`INFOPLIST_FILE = Runner/Info.plist` is set for all three Runner configurations today, but that is a build setting an implementer could change).

### KTD4. Couple the declaration to the fact via a `dart:io` repo guard test

No test in the repo currently reads a plist, a Fastfile, or a workflow YAML. `test/architecture/layering_test.dart` is the only precedent for a repo-file-scanning test, and it establishes the pattern: a `flutter test` case that walks real repo files with `dart:io` using bare repo-relative paths (CWD is the repo root under `flutter test`), asserts a non-zero scan so a wrong path cannot make it vacuously pass, gives the detector its own falsification coverage against hand-written fixtures, and needs no new dependency. The compliance guard mirrors it, reading `pubspec.yaml`, `ios/Runner/Info.plist`, and `fastlane/Fastfile` as text and asserting they tell one consistent story.

This is a bidirectional guard by design: it fails if SQLCipher is dropped while the declaration stays, as well as the reverse. A stale over-declaration is a smaller problem than a stale under-declaration, but it is still a lie about the binary.

### KTD5. New test directory `test/release/`, not `test/architecture/`

The layering guard is the pattern to mirror, but `test/architecture/` is named for the layering/purity rules it enforces. A release-compliance guard is a different concern and gets `test/release/export_compliance_test.dart`. It scans only repo files, so it adds nothing to `lib/` and cannot move the 90% coverage floor or the CRAP gate.

---

## Scope Boundaries

**In scope**

- The `ITSAppUsesNonExemptEncryption` declaration and its Fastlane alignment.
- CI verification of the declaration in the exported bundle.
- The repo guard test tying declaration to build hook.
- The operator decision record and filing checklist.
- README / AGENTS.md pointers to that record.

**Out of scope (non-goals)**

- Changing what the app encrypts, how, or with which library. SQLCipher stays; `lib/` behavior is untouched.
- Android / Play Store compliance. `play-store-release.yml` has no equivalent declaration surface.
- The `PrivacyInfo.xcprivacy` privacy manifest — a different Apple regime, already present and verified.
- Filing the ERN or the annual self-classification report. Those are operator actions performed outside the repo; U5 records them and their triggers.

### Deferred to Follow-Up Work

- Review findings **#6, #7, #25** — the rest of the "release gates & compliance" triage group from issue #37, where the documented release gate (no submit until in-app account deletion ships) has no mechanical guard. A general release-gate guard could subsume U3's bundle check later; keep U3 narrow now.
- Adding `ITSEncryptionExportComplianceCode` to Info.plist. Only meaningful once the operator holds a real code (R7). U5 records the trigger.

---

## Implementation Units

### U1. Declare the encryption usage in `ios/Runner/Info.plist`

**Goal:** The shipped binary states its own export-compliance answer.

**Requirements:** R1, R2, R7.

**Dependencies:** none.

**Files:**
- `ios/Runner/Info.plist` (modify)

**Approach:**
1. Add the `ITSAppUsesNonExemptEncryption` boolean key set to true, placed in the file's existing alphabetical-ish key ordering (it sorts near the `CF*`/`LS*` block; keep the file's existing tab indentation and plist structure).
2. Add a short XML comment above it, matching the file's existing commenting style (`<!-- U4 (KTD8): ... -->`, `<!-- U7: ... -->`), naming SQLCipher as the reason and pointing at the ops doc from U5.
3. Do **not** add `ITSEncryptionExportComplianceCode` — R7 forbids asserting a code the operator does not hold.

No `.pbxproj` change is needed: `INFOPLIST_FILE = Runner/Info.plist` is already set for the Runner target's Debug, Release, and Profile configurations.

**Patterns to follow:** the existing commented keys in `ios/Runner/Info.plist` (`CFBundleURLTypes`, `NSFaceIDUsageDescription`) — each carries a one-line comment explaining why it exists.

**Test scenarios:** covered by U4's guard test and U3's bundle check; this unit adds no independently testable behavior. `Test expectation: none -- declarative plist key, verified by U3 (artifact) and U4 (source).`

**Verification:** `ios/Runner/Info.plist` still parses as a valid plist (`plutil -lint` on a macOS machine, or the U4 test's parse assertion on any machine); the key reads back as boolean true.

---

### U2. Align `fastlane/Fastfile`'s submission information with the declaration

**Goal:** The submission lane stops asserting the opposite of the binary.

**Requirements:** R2, R3, R7.

**Dependencies:** U1.

**Files:**
- `fastlane/Fastfile` (modify — the `submission_information` hash in the `submit` lane, currently at line 44-48)

**Approach:**
1. Flip `export_compliance_uses_encryption` from `false` to `true`.
2. Add the sibling `deliver` export-compliance answers that only become meaningful once encryption usage is admitted, so the lane is self-describing rather than half-answered: the platform, that the encryption is **third-party** (SQLCipher) and **not proprietary**, that it is **not exempt**, that the encryption has not changed since the previous submission (`encryption_updated`), and the French-store availability answer. Use `deliver`'s documented `export_compliance_*` option names; do not invent keys.
3. Leave `add_id_info_uses_idfa` and `content_rights_contains_third_party_content` unchanged.
4. Add a comment block above the hash stating that `ios/Runner/Info.plist` is authoritative (KTD2) and that these values exist to agree with it, with a pointer to the U5 ops doc.
5. Do not set any compliance-code option (R7).

**Patterns to follow:** the Fastfile's existing style — grouped keys with a short explanatory comment above each group, as `automatic_release` and `skip_metadata` already have.

**Test scenarios:**
- U4's guard test asserts the Fastfile no longer contains `export_compliance_uses_encryption: false` and does contain the `true` form.
- U4's guard test asserts the Fastfile does not declare a compliance code (R7 regression guard).

**Verification:** `fastlane ios submit` is not runnable locally (it needs live ASC credentials and a processed build). Verification is: the file parses as Ruby (`ruby -c fastlane/Fastfile`), the U4 guard passes, and the first real submission run after this lands is watched for a `deliver` rejection on an unknown option name.

**Execution note:** `deliver`'s accepted `submission_information` keys change between fastlane majors. Confirm the exact option names against the installed fastlane's `deliver` documentation before writing them, rather than from memory — a wrong key name fails at submit time, on the release path, which is the worst place to discover it.

---

### U3. Verify the declaration in the exported bundle in `ios-release.yml`

**Goal:** A release cannot ship an artifact whose Info.plist lost the declaration.

**Requirements:** R1, R4.

**Dependencies:** U1.

**Files:**
- `.github/workflows/ios-release.yml` (modify — the "Verify the exported bundle" step, currently at lines 344-358)

**Approach:**
1. Inside the existing step, extract `ITSAppUsesNonExemptEncryption` from the already-computed `$plist` path (`build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist`) with `plutil -extract ... raw -o -`, mirroring how `MinimumOSVersion` and `CFBundleIdentifier` are read.
2. Fail with an `::error::` annotation and a non-zero exit if the key is absent (`plutil` exits non-zero — the step already runs under `set -euo pipefail`, so guard the extraction so the failure message is the compliance one, not a bare plutil error) or if its value is not the expected `true`.
3. Echo the resolved value alongside the existing `minimum OS: ... bundle: ...` line so the release log records what was declared.
4. Keep it in the existing step rather than adding a new one — it is the same "does the artifact match what we promised" check as the bundle id, minimum OS, and privacy-manifest assertions already there.

**Patterns to follow:** the three existing assertions in that step — `plutil -extract` into a shell variable, then a `[ ... ] || { echo "::error::..."; exit 1; }` guard; the `PrivacyInfo.xcprivacy` check is the closest analogue for a presence assertion.

**Test scenarios:**
- Cannot be unit-tested; it is workflow shell. Prove it by reasoning plus one deliberate local dry-run of the shell fragment against two fixture plists (one with the key, one without) on any machine with `plutil`, or by asserting the same logic in the U4 test if no macOS machine is at hand.
- The negative case matters most: confirm a *missing* key fails the step rather than silently producing an empty string that compares equal to nothing.

**Verification:** the shell fragment exits 0 for a plist containing the key set to true and exits 1 with an `::error::` line for a plist missing it, and for a plist where it is false.

**Execution note:** `set -euo pipefail` plus a missing key makes `plutil -extract` abort the step before the intended error message prints. Structure the extraction so the compliance-specific message is what the release log shows.

---

### U4. Guard test: declaration, build hook, and Fastlane must agree

**Goal:** The declaration cannot drift from the SQLCipher fact in either direction.

**Requirements:** R2, R3, R5, R7.

**Dependencies:** U1, U2.

**Files:**
- `test/release/export_compliance_test.dart` (create)

**Approach:**
1. Read the three repo files by repo-relative path with `dart:io` — `pubspec.yaml`, `ios/Runner/Info.plist`, `fastlane/Fastfile`. `flutter test` runs with the repo root as CWD, which `test/architecture/layering_test.dart` already relies on.
2. Assert each file was found and is non-empty before asserting content, so a moved or renamed file fails loudly instead of vacuously passing — the same non-vacuity discipline the layering guard uses with its non-zero scanned-file assertion.
3. Detect the SQLCipher fact from `pubspec.yaml`'s `hooks: user_defines: sqlite3: source: sqlcipher` block. Prefer parsing the YAML structurally over substring matching so a mention inside a comment cannot satisfy the guard; if adding a YAML parser is not warranted for one test, match on the nested key path with an anchored pattern and say so in the test's doc comment.
4. Assert `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption` as `<true/>` — match the key element and its following value element rather than testing for the bare key string, so a `<false/>` value cannot pass.
5. Assert `fastlane/Fastfile` sets `export_compliance_uses_encryption` to `true` and contains no `false` form of it.
6. Assert no compliance-code option is present in either file (R7).
7. Write the whole thing as one coherent rule with a library-level doc comment explaining *why* — the layering guard's doc comment is the model: it states the rule, the detection subtleties, and what would otherwise be gotten wrong.

**Patterns to follow:**
- `test/architecture/layering_test.dart` — `dart:io` file reads at bare repo-relative paths, a long `///` rationale followed by `library;`, anchored regexes with a comment explaining each subtlety, non-vacuity assertions, a group named for the governing decision (`group('layering (KTD2)', ...)` → `group('export compliance (KTD1/KTD2)', ...)`), and self-falsification coverage for the detector itself. No new dependency.
- `test/tool/quality/crap_gate_test.dart` and `coverage_filter_test.dart` — `Directory.systemTemp.createTempSync(...)` + `writeAsStringSync` when the falsification cases need fixture files on disk.

**Test scenarios:**
- SQLCipher hook declared + Info.plist declares true + Fastfile says true → passes.
- Info.plist key missing entirely → fails with a message naming `ios/Runner/Info.plist` and the key.
- Info.plist key present but `<false/>` → fails (guards against matching the key name alone).
- Fastfile still contains `export_compliance_uses_encryption: false` → fails with a message naming `fastlane/Fastfile`.
- SQLCipher hook removed from `pubspec.yaml` while the declaration remains → fails, telling the reader to re-classify rather than to delete the declaration.
- A commented-out mention of the hook in `pubspec.yaml` does not satisfy the SQLCipher detection (detector falsification case, mirroring the layering test's "detects the forms a violation can take" case).
- Any of the three files missing or empty → fails with a path-specific reason, not a null dereference.
- Optional, if U3's logic is mirrored here: a fixture plist missing the key is rejected by the same matcher used against the real file.

**Verification:** `flutter test test/release/export_compliance_test.dart` passes; temporarily reverting U1 or U2 makes it fail with a message that names the offending file and the fix.

---

### U5. Record the classification decision and the operator's filing duties

**Goal:** The next person to touch a release knows why the answer is what it is, and what recurring obligation it creates.

**Requirements:** R6, R7.

**Dependencies:** KTD1 (the decision itself); can be written in parallel with U1-U4.

**Files:**
- `docs/ops/ios-export-compliance.md` (create)
- `README.md` (modify — the release-workflow paragraph around line 130-136, and/or the privacy/limitations list around line 232)
- `AGENTS.md` (modify — the "iOS App Store / TestFlight Release Workflow (Primary)" bullet block around line 102)

**Approach:**
1. Write `docs/ops/ios-export-compliance.md` following the shape of `docs/ops/supabase-go-live.md` — an operator checklist, not a narrative. Cover:
   - **What lunarlog encrypts:** SQLCipher AES-256 at rest via the `pubspec.yaml` build hook and `PRAGMA key` in `lib/data/db/native_db.dart`; a per-install 256-bit key in `flutter_secure_storage` (iOS Keychain, `first_unlock_this_device`, non-syncable); SHA-256 from `package:crypto` for OIDC nonces and invitation-token hashes; `pointycastle 4.0.0` bundled transitively; TLS to Supabase. Note that the web build is deliberately unencrypted and is iteration-only, so it is not part of this declaration.
   - **Consistency anchor:** the declaration must stay consistent with `PRIVACY.md`'s public claims (`:15`, `:65`, `:85`, `:89`). If one changes, both change.
   - **The classification and why:** non-exempt, third-party, non-proprietary; why none of Apple's listed exemption categories fit; a pointer back to this plan and to issue #48 / finding #28 in #37.
   - **Where the declaration lives:** `ios/Runner/Info.plist` (authoritative), `fastlane/Fastfile` (aligned), the `ios-release.yml` bundle check, and the `test/release/` guard — so a reader can find all four.
   - **Recurring operator actions:** the mass-market self-classification path (ECCN 5D992.c), obtaining an ERN, and the annual self-classification report. Mark these as unchecked boxes with owner = operator, and state plainly that they are outside the repo and that no code change satisfies them.
   - **What to do if App Store Connect asks for compliance documentation or a code:** obtain it, then add `ITSEncryptionExportComplianceCode` to Info.plist and update the guard test — never flip the declaration back to make the prompt go away.
   - **Re-check triggers:** adding or removing any crypto dependency, dropping the SQLCipher hook, or changing what is encrypted.
2. Add a one-line pointer from `README.md`'s release-workflow paragraph and from `AGENTS.md`'s iOS release bullet block, matching how both already point at `docs/ops/supabase-go-live.md`.

**Patterns to follow:** `docs/ops/supabase-go-live.md` (checklist shape, "settings the code cannot apply" framing); the existing `docs/ops/` links in `README.md` and `AGENTS.md`.

**Test scenarios:** `Test expectation: none -- documentation. Verified by review against R6/R7 and by confirming the added links resolve.`

**Verification:** the new file exists at `docs/ops/ios-export-compliance.md`, is linked from both `README.md` and `AGENTS.md`, and states no compliance code the operator does not hold.

---

## Verification Contract

Run from the repo root, in this order:

1. `flutter pub get`
2. `flutter analyze` — must be clean.
3. `flutter test` — full suite, including the new `test/release/export_compliance_test.dart`.
4. `dart run tool/quality_gate.dart` — the 90% line-coverage floor and the per-method CRAP gate (threshold 10). This is the CI `check` job's step right after `flutter test` in `ci.yml`. This change adds no `lib/` code, so the gate result must be **unchanged** from the base branch; a movement here means something unintended landed in `lib/`. (Note the `ios-release.yml` `verify` job runs analyze + test but *not* the quality gate, so `ci.yml` is where this is actually enforced.)
5. `ruby -c fastlane/Fastfile` — syntax check for U2 (any machine with Ruby).
6. macOS only, if available: `plutil -lint ios/Runner/Info.plist`, and the U3 shell fragment exercised against a with-key and a without-key fixture plist.

Not runnable here, and deliberately deferred to the release path: `fastlane ios submit` (needs live App Store Connect credentials and a processed build) and the full `ios-release.yml` run (needs the macOS runner and signing material). The first release run after this lands is the real proof for U2 and U3 — watch that run's "Verify the exported bundle" step output and any `deliver` option-name rejection.

---

## Definition of Done

- `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption` as true, with an explanatory comment (R1, R2).
- `fastlane/Fastfile` no longer says the app uses no encryption, and its `export_compliance_*` answers agree with the plist (R3).
- `.github/workflows/ios-release.yml` fails the release when the exported `Runner.app` does not carry the declaration (R4).
- `test/release/export_compliance_test.dart` exists, passes, and fails when the declaration and the SQLCipher hook disagree in either direction (R5).
- `docs/ops/ios-export-compliance.md` exists and is linked from `README.md` and `AGENTS.md` (R6).
- No CCATS number, ERN, or `ITSEncryptionExportComplianceCode` appears anywhere in the repo (R7).
- `flutter analyze` clean; `flutter test` green; `dart run tool/quality_gate.dart` result unchanged from base.
- Issue #48 closed with a note that findings #6, #7, and #25 remain open.

---

## Alternatives Considered

- **Keep the exemption claim (`ITSAppUsesNonExemptEncryption = false`).** Rejected: this is the current state and the thing finding #28 identifies as inaccurate. A compiled-in third-party AES-256 database cipher does not fit any of Apple's listed exemption categories, and an inaccurate declaration is a worse position than the paperwork the accurate one creates.
- **Fix the Fastfile boolean only, leave Info.plist alone.** Rejected: it addresses the wrong half of the problem. The declaration would still exist only on the `submit_for_review` path, so TestFlight uploads and manual submissions would carry no declaration at all — issue #48's "travel deterministically with every binary" requirement would be unmet.
- **Info.plist only, leave the Fastfile at `false`.** Rejected: App Store Connect would likely honor the plist, but the repo would contain a lane that asserts the opposite of the binary, which the next reader would reasonably believe.
- **Guard the declaration only in CI, no repo test.** Rejected: the CI check runs on the macOS release path, so a contributor breaks it late and remotely. The `flutter test` guard fails in seconds locally and is where the *reason* for the declaration is written down.
- **Guard the declaration only in a test, no CI check.** Rejected: a source-tree test cannot prove the key survived the Xcode build into the uploaded artifact. Both checks answer different questions (KTD3).

---

## Risks and Open Questions

- **[Risk] Declaring non-exempt encryption can add a submission prompt for compliance documentation.** App Store Connect may ask for a CCATS or compliance code once encryption usage is admitted. Mitigation: U5 documents the mass-market self-classification path and the escalation, and R7 forbids fabricating a code. Internal TestFlight testing is unaffected; the practical exposure is a first App Store submission — which is already gated behind in-app account deletion per the existing release gate, so there is time to file.
- **[Risk] `deliver`'s `submission_information` option names differ across fastlane majors.** A wrong key fails at submit time on the release path. Mitigation: U2's execution note requires confirming names against the installed fastlane rather than from memory; U4 pins the one key whose value carries the decision.
- **[Risk] `set -euo pipefail` swallows U3's intended error message** when `plutil -extract` aborts on a missing key. Mitigation: called out as U3's execution note, with the missing-key case as an explicit test scenario.
- **[Open question — operator]** Has an ERN been obtained, or an annual self-classification report filed, for `com.wjdavis5.lunarlog`? U5 records these as unchecked operator boxes. Implementation does not block on the answer; a first App Store submission does.
- **[Open question — operator]** Is the app intended to be available on the French App Store? U2 needs the `export_compliance_available_on_french_store` answer. Default to the app's actual intended territory availability; if that is undecided, record it as an unchecked box in U5's doc rather than guessing in the Fastfile.

---

## Sources

- Issue [wjdavis5/lunarlog#48](https://github.com/wjdavis5/lunarlog/issues/48) — the requirement.
- Issue [wjdavis5/lunarlog#37](https://github.com/wjdavis5/lunarlog/issues/37) — finding #28 (`fastlane/Fastfile:47`, swift-ios reviewer, score 75) and the "Release gates & compliance" triage group.
- `pubspec.yaml:80-87` (`hooks: user_defines: sqlite3: source: sqlcipher`), `lib/data/db/native_db.dart:24-40` (`PRAGMA cipher_version`, `PRAGMA key`), `lib/data/db/key_store.dart` (256-bit `Random.secure()` key in `flutter_secure_storage`) — the encryption fact being declared.
- `PRIVACY.md:15`, `:65`, `:85`, `:89` — the public encryption claims the declaration must stay consistent with.
- `.github/workflows/ios-release.yml` "Verify the exported bundle" step — the existing artifact-assertion pattern U3 extends.
- `test/architecture/layering_test.dart` — the `dart:io` repo-guard test pattern U4 mirrors.
- `docs/ops/supabase-go-live.md` — the operator-checklist shape U5 follows.
- `AGENTS.md` "Quality gates" and release sections — the verification commands and the existing release gate.
