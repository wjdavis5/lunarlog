# iOS privacy manifest: required-reason API reconciliation

Operator checklist for `ios/Runner/PrivacyInfo.xcprivacy`'s
`NSPrivacyAccessedAPITypes` declarations (issue #265, closing review finding
C-25). Sibling to
[`ios-export-compliance.md`](ios-export-compliance.md) (a different Apple
regime -- encryption export compliance, not required-reason API usage) and to
issue #254's collected-data-type / HealthKit reconciliation, which this
manifest also carries. Never record a credential in this file.

## The gap this closes

The manifest's `NSPrivacyAccessedAPITypes` array was empty, on the assumption
that every required-reason API in the app is called by a CocoaPod-delivered
Flutter plugin (flutter_secure_storage, shared_preferences, local_auth,
sentry_flutter) declaring its own reasons in its own bundled manifest. That
assumption is false for `pubspec.yaml`'s `sqlite3: ^3.5.2` dependency: there
is no `sqlite3_flutter_libs` plugin and no `ios/Podfile`, so SQLite is
delivered by `package:sqlite3`'s Dart native-build hook, which (confirmed by
reading `hook/build.dart` and
`lib/src/hook/compile/description.dart` at the pinned 3.5.2) defaults
(`source: null`) to downloading a **precompiled `libsqlite3` dynamic library**
from `github.com/simolus3/sqlite3.dart`'s GitHub releases and bundling it into
`Runner.app` with **no privacy manifest of its own**. Any required-reason API
it calls has to be declared in the app's own manifest instead -- that is what
issue #265 fixes.

## Audit performed (2026-09-14, issue #265)

Categories the issue asked to check: file timestamp, system boot time, disk
space, active keyboards, `UserDefaults`, across SQLite's C code, the app's
Flutter/Dart code, and `AppDelegate.swift` (including the HealthKit and
notification handling).

- **File Timestamp declared (`NSPrivacyAccessedAPICategoryFileTimestamp`,
  reason `C617.1`).** SQLite's unix VFS (`os_unix.c`'s `unixFileSize`) calls
  `fstat()` to read the database file's size on every open -- this is the
  well-documented reason apps bundling SQLite need this category, and is
  attributable to the bundled `libsqlite3` dylib this pubspec pulls in.
- **User Defaults declared (`NSPrivacyAccessedAPICategoryUserDefaults`,
  reason `CA92.1`).** `AppDelegate.swift`'s `HealthKitChannelHandler` reads
  and writes `UserDefaults.standard` directly (the `boundProfileId` guard
  state, issue #173) -- this app's own first-party Swift code, not a plugin,
  confirmed by reading the file directly. `CA92.1` is the app-exclusive-access
  reason (not the App Group variant, `1C8F.1` -- this app has no App Group).
- **Not declared: System Boot Time, Disk Space, Active Keyboards.** No
  first-party code (`AppDelegate.swift`, `lib/` Dart/Flutter code) calls any
  API in these categories (grepped for `UserDefaults`/`stat`/`statfs`/
  `ProcessInfo`/`systemUptime`/`activeInputModes` and equivalents; found
  none outside this app's own domain fields that happen to share a
  substring, e.g. `lastModifiedByUserId`, which is unrelated). The default
  SQLite build here (`hook/build.dart`'s default defines: `FTS5`, `RTREE`,
  `MATH_FUNCTIONS`, `DBSTAT_VTAB`, etc. -- no custom VFS, no low-disk-space
  handling compiled in) gives no reason to expect a Disk Space call either.
  Active Keyboards has no plausible caller in a cycle-tracking app.

### Reason codes verified against Apple's documentation

The issue asked to verify reason codes against Apple's official "Describing
use of required reason API" page rather than relying on memory. That page
(`developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api`)
is JavaScript-rendered and not fetchable as plain text from this
environment's tooling -- attempts returned only the page chrome, not the
reason-code table. `C617.1` (File Timestamp) and `CA92.1` (User Defaults, "app
settings access exclusive to the app itself") were instead cross-checked
against multiple independent, mutually-consistent secondary sources quoting
Apple's table (a `react-native-community` discussion thread reproducing the
official codes verbatim, a Bugfender engineering blog post, and Apple
Developer Forum threads discussing `CA92.1`/`1C8F.1`/`AC6B.1`/`C56D.1`
specifically), agreeing independently on both codes and their conditions.
Notably, issue #265's own "Assumptions" section guessed `CA92.1` as the
**Disk Space** reason -- that guess was wrong (`CA92.1` is User Defaults;
Disk Space's closest-matching reason is `E174.1`, "check whether there is
sufficient disk space to write files"); the guess is not carried into the
manifest, since no Disk Space usage was actually found.

### What was NOT done: the Xcode privacy report

Issue #265's first acceptance criterion is running Xcode's "Generate Privacy
Report" (Organizer -> right-click an archive -> Generate Privacy Report)
against a real built archive, which statically scans the linked binary and
every embedded framework/dylib for known required-reason API symbol
signatures -- a static-symbol analysis this text/source audit cannot fully
replace (it can see conditionally-compiled or platform-specific code paths a
source read misses, and it is Apple's own authority, not this document's
best-effort reconstruction). **This could not be run from this environment**:
it needs macOS + Xcode's GUI (Organizer), and there is no `xcodebuild`-only
equivalent (confirmed: Apple provides no CLI for it; the only alternative is
a third-party tool, `fxwx23/PrivacyReportGen`, that extracts the same data
from an `.xcarchive` via `swift package plugin`, not exercised here).

- [ ] **Operator action, before the next App Store submission:** build a
      Runner archive on `Williams-Mini` (see `CLAUDE.md`'s iOS build section)
      and run `Generate Privacy Report` from Xcode's Organizer. Reconcile its
      findings against the two declarations above -- add anything it finds
      that this audit missed, and reconsider (but do not blindly remove)
      anything declared here that it doesn't corroborate, since a report
      against one build configuration can differ from another (e.g. Debug
      vs. Release define sets passed through `hook/build.dart`'s
      `additionalFlags`).
- [ ] Record the report's findings here (or link its saved output) once run.

## Recurring operator action

- [ ] **Regenerate the Xcode privacy report and reconcile
      `NSPrivacyAccessedAPITypes`** before each App Store submission --
      `test/release/privacy_manifest_required_reason_test.dart` only proves
      the manifest text matches what this document says it should, it cannot
      prove that matches the actual linked binary.
- [ ] **Re-run this reconciliation whenever a new native/FFI dependency is
      added** (a new Dart FFI package, a new native build hook, a new
      `sqlite3` `source:` override in `pubspec.yaml`'s `hooks:` block) --
      not only at release time. A new native dependency is exactly how the
      gap this issue closed was introduced in the first place.
- [ ] If the `sqlite3` dependency's `source:` user-define ever changes away
      from the default (`system`, `process`, `executable`, or a custom
      `source` compile -- see `SqliteBinary.forBuild` in the package's
      `lib/src/hook/compile/description.dart`), re-derive this audit: a
      `system`/`process`/`executable` binding links against the OS's own
      `libsqlite3`, which is Apple's responsibility, not this app's, and may
      change what needs declaring here.

## Re-check triggers

Re-open this checklist, the manifest's own comment, and
`test/release/privacy_manifest_required_reason_test.dart` whenever:

- A new native/FFI dependency (Dart native-build hook, new CocoaPod without
  its own privacy manifest) is added.
- The `sqlite3` dependency's version or `source:` configuration changes.
- `AppDelegate.swift` gains a new direct call into `UserDefaults`, file
  attributes, disk space, boot time, or keyboard APIs.
- Apple revises the required-reason API category list or its reason codes.

## Scope note

This closes review finding C-25 and issue #265's required-reason API
declarations only. It does not touch `NSPrivacyCollectedDataTypes` (issue
#254) or `ITSAppUsesNonExemptEncryption` (`ios-export-compliance.md`) --
separate Apple regimes documented separately.
