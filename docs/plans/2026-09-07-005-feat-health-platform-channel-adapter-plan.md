---
title: First-Party HealthKit / Health Connect Platform Channel Adapter - Plan
type: feat
date: 2026-09-07
issue: wjdavis5/lunarlog#173
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-173
execution: code
---

# First-Party HealthKit / Health Connect Platform Channel Adapter - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written after implementation to record what shipped and
why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** one first-party `MethodChannel` (`lunarlog/health`) with a
  Swift `HKHealthStore` half and a Kotlin `HealthConnectClient` half over a
  platform-neutral domain port, so the whole Health Platform Sync epic
  (#193 through #246) has exactly one place to enforce the #153 guard.
- **Means:** the issue's option (b), decided and recorded (see below); the
  pub.dev `health` package is deliberately absent from `pubspec.yaml`.
- **Authority hierarchy:** issue #173 owns the decision and acceptance
  checklist (binding); #153's landed guard (`HealthSyncBinding` /
  `health_sync_policy.dart`) owns the predicate — the native mirrors copy
  it, never re-derive it; the issue's own comment contract notes (from the
  #319/#180 review) own the exclusive-end timezone additions.
- **Stop conditions honored:** no `health` package; no Dart-side-only
  guard; no settings-UI activation (`AppConfig.hasHealthSync` stays false
  until #193/#202 put a user-visible write flow behind it).

---

## The (a) vs (b) Decision

Recorded where a future contributor will actually meet it — the library
doc of `lib/domain/health/health_platform.dart` — and cross-referenced
from every adapter file (Dart, Swift, Kotlin) and this plan. Summary:
**(b) first-party channel**, because the `health` package covers only
`MENSTRUATION_FLOW` of the cycle-relevant types on either platform (so (a)
means either single-type Clue parity or two competing implementations of
the same data-type concept), because the #153 guard must be enforced in
one place across every type this epic adds (a package write path cannot
run a native guard at all), and because the package has no iOS observer
support for the epic's later background work. The full argument, with the
cost-benefit, lives in the port's library doc so it is not re-litigated.

## What Shipped

### U1. Platform-neutral domain port — `lib/domain/health/health_platform.dart`

Pure Dart (R14/R16, no Flutter imports; `layering_test.dart` discipline
holds): `HealthPlatformStore` with one method per data-type concept —
`writeMenstrualFlow`, `writeIntermenstrualBleeding` (the #193/#202 v1
surface) — plus the session surface every write flow needs:
`isAvailable`, `bindProfile`/`unbindProfile` (the native binding mirror's
setters), `requestWriteAuthorization`. Later types (cervical mucus,
ovulation test, BBT, sexual activity, symptom categories) extend the
interface one method at a time; nothing existing changes when they do.
Supporting types: `HealthFlowValue` (the closed, platform-intersection
transport vocabulary — `unspecified/light/medium/heavy`; lunarlog's
`FlowLevel`-with-episode-membership mapping is deliberately #193/#202's
function, not a domain concern), `HealthGuardFacts` (the #153 guard's
inputs; `minorBindingAllowed` is deliberately NOT a field — the adapters
take it as a constructor parameter sourced from
`AppConfig.healthSyncMinorBindingAllowed`, so no call site can invent a
per-call bypass), `HealthPlatformResult` (sealed: allowed / refused(check)
/ unavailable / permissionDenied / failed(message)).

### U2. The wire codec — `lib/data/health/health_channel_codec.dart`

Pure, fully tested, no Flutter imports: guard-args encoder, day-args
encoder, result decoder, method-name constants, and the
[HealthSyncCheck]↔wire-string mapping (the enum's own names, so the
native mirrors cannot drift on vocabulary). One deliberate choice: OS
write failures cross as `FlutterError(code: "writeFailed", ...)` rather
than result strings, keeping "the guard refused" (string results) cleanly
separated from "the OS threw" (exceptions).

### U3. The shared Dart adapter — `lib/data/health/health_channel.dart`

`MethodChannelHealthPlatform` (the engine), `UnsupportedHealthPlatform`
(the `UnsupportedPasskeyCeremonyClient` pattern for web/desktop — fails
`unavailable()`, never crashes), and `createHealthPlatform()` (pins iOS/
Android, else Unsupported). The engine's load-bearing property: every
guarded method is literally `_guard(facts) ?? _invokeGuarded(...)` —
`HealthSyncBinding.canWrite` runs first, and a deny returns
`refused(check)` with **zero channel invocations**. Day/payload argument
maps are *builders* evaluated only after the guard allowed, so a denied
write never even computes (let alone throws on) a day envelope, and a
guard denial wins even when the time zone is also bad. The engine is
deliberately NOT coverage-excluded — it is fully driven under `flutter
test` via a mock MethodChannel.

### U4. The platform pins — `lib/data/health/ios_health_channel.dart` +
`android_health_channel.dart`

Constructor-only subclasses of the engine, each the named home for its
platform's future pure mapping functions (#193's
`FlowLevel`→`HKCategoryValueVaginalBleeding` table lands in the iOS file;
#202's flow constants and period-record upsert surface in the Android
file). Both are coverage-excluded (see U8) — the exclusion hides nothing:
all shared logic lives in the non-excluded engine and codec.

### U5. Swift half — `ios/Runner/AppDelegate.swift`
(`HealthKitChannelHandler`)

Registered on `lunarlog/health` in
`didInitializeImplicitFlutterEngine`, right beside the `lunarlog/privacy`
channel (the established registration pattern). Kept in AppDelegate.swift
rather than its own file on purpose: a new `.swift` file needs an Xcode
project-file edit that cannot be safely hand-written without a Mac, and
CI has no pre-merge iOS compile catch for a pbxproj typo. The handler
implements: `isAvailable` (the one deliberately unguarded method — a
static capability probe, no health store access), `bind`/`unbind`
(UserDefaults `lunarlog.health.boundProfileId`), the guard mirror
(`guardDecision`, mirroring `HealthSyncBinding._evaluate` including the
`_isMinorNow` birth-year computation), `requestWriteAuthorization` (guard
→ prompt for the two v1 types; iOS reports completion, not the user's
choice), `writeMenstrualFlow` (interval sample from `startMs`/`endMs` with
`HKMetadataKeyMenstrualCycleStart`), and `writeIntermenstrualBleeding`
(`notApplicable` category sample). Menstrual flow raw values are declared
as bare `Int`s (0/1/2/3) documented identical to both
`HKCategoryValueVaginalBleeding` and the deprecated
`HKCategoryValueMenstrualFlow` (A3-14), so the file compiles against any
SDK with no availability branch — swapping to the iOS 18 symbol yields
the same integers.

### U6. Kotlin half — `android/.../HealthConnectAdapter.kt` +
`MainActivity` + `build.gradle.kts`

Registered on `lunarlog/health` in `configureFlutterEngine` (the privacy
channel's pattern). Guard mirror over a SharedPreferences
`lunarlog.health.boundProfileId`; Health Connect writes are suspend calls
each served by a per-call coroutine scope (no lifecycle to manage);
`requestWriteAuthorization` uses Health Connect's ActivityResult contract,
launcher registered at adapter-construction time (during `onCreate`, the
last legal moment), one pending prompt at a time; `MenstruationFlowRecord`
(from `instantMs`+`zoneOffsetMs` — Health Connect's instant form) and
`IntermenstrualBleedingRecord` (no value field); `SecurityException` on
insert maps to `permissionDenied`. `connect-client:1.1.0` (current
stable) added to `build.gradle.kts` — the `minSdk 26` pin from #166
already satisfied its floor. All numeric channel args are read through an
`as? Number` helper because StandardMessageCodec delivers ints as
`Int`/`Long` by magnitude.

### U7. The native guard mirror — the safety property

Both native halves re-evaluate the #153 predicate **before any health API
touch**, from their own natively-stored binding (`UserDefaults` /
`SharedPreferences`) — not a Dart-supplied bound id. The predicate
duplication (Dart + Swift + Kotlin) is deliberate and documented as such
in each file: the sides cannot share code, and the mirror is what makes
"a bug in Dart-side call ordering must not bypass the safety property"
(issue #173, implementation item 4) true rather than aspirational.
Fail-closed on disagreement: a write proceeds only when BOTH the
Dart-stored and natively-stored bindings name the written profile. The
stored value is a random profile ULID, not health data. `bind` mirrors
`canBind`'s proposed-binding semantics (evaluates against the id being
bound, stores only if every other check passes); every write/authorization
call mirrors `canWrite`'s stored-binding semantics.

### U8. Quality gates — `tool/quality/exclusions.dart`

Two entries, `lib/data/health/ios_health_channel.dart` and
`lib/data/health/android_health_channel.dart`, each with a why-comment in
the file's established style. The literal checklist item says "new native
Swift/Kotlin files," but the gate instruments Dart only (lcov `SF:`
records never contain Swift/Kotlin), so the honest landing is the Dart
side of each native pairing — the comments say so explicitly, following
the `firebase_push_token_source.dart` precedent's lesson (an exclusion
must never quietly hide testable logic): the engine and codec are NOT
excluded and carry the full guard-ordering/codec test suites.

### U9. Tests

- `test/data/health/health_channel_test.dart` — the guard-ordering proof:
  every deny reason (`noBinding`, `profileNotBound`, `notOwner`,
  `minorRequiresOwnershipTransfer`) asserted as zero channel invocations
  across all four guarded methods; the allowed path's exact wire envelope
  (guard args + DST-aware day args + payload); native deny-string
  passthrough; `unavailable`/`permissionDenied`/unknown-string/
  `PlatformException`/`MissingPluginException` mapping; `isAvailable`
  pass-through; best-effort `unbindProfile`; unresolvable-time-zone
  failing after (and never displacing) the guard; `UnsupportedHealthPlatform`
  clean-failure behavior; the `createHealthPlatform` platform pins.
- `test/data/health/health_channel_codec_test.dart` — the wire protocol
  contract: guard-args maps (present and null forms), the full day
  envelope for a fixed date/zone, the fall-back-day offset divergence,
  agreement with `day_boundary.dart`'s own functions, unknown-zone
  throwing, and every result-string decode branch.
- `test/domain/health/day_boundary_test.dart` — extended for
  `localDayEndExclusive` (inclusive-end + 1s, 23/25-hour DST days) and
  `endZoneOffsetFor` (differs from the midnight offset across both DST
  transition directions, equals the day-after's own midnight offset).

### U10. Timezone contract additions — `lib/domain/health/day_boundary.dart`

`localDayEndExclusive` + `endZoneOffsetFor`, exactly as the issue's own
comment (the #319/#180 review contract notes) required "before wiring
Health Connect": Health Connect interval records want a genuinely
exclusive end carrying its own `endZoneOffset`, which differs from
`zoneOffsetFor`'s midnight offset on a DST day. The channel's day
envelope carries both ends and both offsets so #202's period records need
no codec change.

---

## Decisions & Trade-offs

- **`AppConfig.hasHealthSync` stays `false`.** Its doc said "flip to true
  in the PR that adds the first adapter," but this PR is the channel layer
  only — no write flow calls it yet, so flipping would surface the
  Settings tile live with nothing observable behind it (the exact state
  the flag exists to prevent). The doc comment was updated to name #193/
  #202 as the flip point. Consequence, accepted deliberately:
  `bindProfile`/`unbindProfile` have no production caller yet; the
  flag-flip PR must wire `HealthSyncScreen`'s bind/unbind (and the
  sign-out device reset, which should also `unbindProfile` so a stale
  native mirror can't linger — fail-closed either way) through the port.
- **`isAvailable` unguarded.** A static capability probe (HK
  `isHealthDataAvailable()` / HC `getSdkStatus`) touches no health store
  and no user data; Settings needs it before any binding exists. Every
  method that can touch the store (bind aside, which is the mirror's own
  setter, itself predicate-checked) carries the guard.
- **Native mirrors, not a shared predicate.** The issue demanded
  Dart-side gating not be trusted alone; the only way to enforce that is
  to duplicate the predicate natively and give each side its own stored
  binding. Documented as the safety property in all three languages.
- **Flow values as bare raw Ints in Swift.** Compiles against any SDK
  with no availability branch or deprecation warning; the raw values are
  identical across `HKCategoryValueMenstrualBleeding`/`HKCategoryValueVaginalBleeding`
  (A3-14). A maintainer on Xcode may swap to the named symbol; the
  integers do not change.

## Verification

- `flutter analyze` clean; `flutter test` green (2422 tests, of which 156
  health-related); `dart run tool/quality_gate.dart` green (94.61%
  coverage vs the 90% floor, CRAP gate clean) with the two new
  exclusions.
- The Android Kotlin half is **compile-verified on this machine**:
  `:app:compileDebugKotlin` (Gradle, Android Studio's JBR, Flutter SDK
  from `/c/src/flutter`) against the pinned `connect-client:1.1.0` —
  which caught three real 1.1.0 API drifts before review (the
  `createWritePermission` → `getWritePermission(KClass)` permission
  model, the internal `Metadata` constructor behind the public
  `Metadata.manualEntry()` factory, and a `kotlin.Metadata` import
  shadowing worked around with an aliased import).
- CI's `check` job compiles both native halves on PRs (`flutter build apk
  --debug` and `flutter build ios --release --no-codesign`), which is the
  compile-level verification for the Swift half this Windows machine
  cannot provide.

## Not Done / Deferred

- No device-level verification of either native half (no macOS/Xcode, no
  Android device/emulator run here): the Swift handler's compilation and
  both platforms' actual HK/HC write behavior, the Health Connect
  permission sheet, and the HealthKit authorization prompt are verified
  only at the compile level (Kotlin locally, Swift via CI) and remain
  subject to the #193/#202 device checklists.
- `HealthSyncScreen` is untouched: binding still writes only the
  device-local setting; the native mirror's setters have no production
  caller until the flag-flip PR (see Decisions).
- Reads/imports (the #180 read direction, #217) are not part of this
  adapter; the port is write/authorization-shaped per #173's scope.
