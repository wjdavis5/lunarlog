/// Platform-neutral health-store port (Issue #173) — the one interface
/// every HealthKit / Health Connect data-type write goes through, one
/// method per data-type *concept*, never per platform SDK call.
///
/// ## Design note: first-party channel over the `health` package (the
/// issue's (a) vs (b) decision — recorded here so it is not re-litigated)
///
/// **Decision: option (b), a first-party `MethodChannel` (`lunarlog/health`)
/// with a Swift `HKHealthStore` implementation on iOS and a Kotlin
/// `HealthConnectClient` implementation on Android. The pub.dev `health`
/// package (v13.3.2) is deliberately NOT a dependency and must not be
/// added.**
///
/// Why (b) over (a) (`health` package + a second channel for the rest):
///
///  1. **Type surface.** The `health` package covers only
///     `MENSTRUATION_FLOW` of the cycle-relevant types on either platform
///     — no intermenstrual bleeding, cervical mucus, ovulation test, basal
///     body temperature, sexual activity, or the ~39 HealthKit symptom
///     category types (the package's own README notes both platforms
///     expose more types than it covers). Depending on it means either
///     single-type parity with Clue (defeating the differentiator types
///     of #217/#228/#210/#238) or two competing implementations of the
///     same data-type concept in one app — the exact duplication this
///     port exists to make impossible.
///  2. **One place for the safety invariant.** The #153 (HS-1) guard
///     (profile↔device-owner binding + owner-not-guardian, see
///     `health_sync_policy.dart`) must be enforced identically across
///     *every* type this epic adds. A package-limited surface would force
///     the flow type through the package's own write path — which cannot
///     run lunarlog's native guard at all — while every other type went
///     through ours: two code paths, two (well, one and zero) places to
///     enforce the same load-bearing property. A single first-party
///     channel keeps it in one place, enforced natively before any health
///     API touch (see the adapters' docs and the plan of record).
///  3. **Background/observer support.** The package has no iOS observer
///     query support at all and Android-only permission helpers; the
///     epic's later background work (#217/#186) needs the native handles
///     a first-party channel owns outright.
///
/// The cost of (b) — maintaining two native implementations behind one
/// protocol — is bounded: both sides speak the small, versioned message
/// set in `lib/data/health/health_channel_codec.dart`, and all
/// cross-platform logic (guard evaluation on the Dart side, day/zone
/// conversion via `day_boundary.dart`) stays in pure, tested Dart.
///
/// ## Shape of the port
///
/// * Methods are per data-type concept (`writeMenstrualFlow`,
///   `writeIntermenstrualBleeding`) — the minimum the epic's v1 parity
///   issues (#193/#202) need. Later types (cervical mucus, ovulation
///   test, BBT, sexual activity, symptom categories) extend this
///   interface with one method each and one codec entry each; nothing
///   about the existing surface changes when they do.
/// * Every guarded method takes a [HealthGuardFacts] — the same inputs
///   `HealthSyncBinding.canWrite` evaluates — because **the adapter, not
///   the eventual call site, owns the guard call**: every implementation
///   must invoke `HealthSyncBinding.canWrite` *before* touching the
///   channel, and the native handler re-evaluates the same predicate
///   from its own natively-stored binding before touching
///   `HKHealthStore`/`HealthConnectClient` at all. A bug in Dart-side
///   call ordering therefore cannot bypass the safety property: the
///   native mirror denies (and never touches the health API) even if
///   Dart never checked. The duplication is the safety property — see
///   the native files and the plan of record for why the mirror cannot
///   be factored into one place (the two sides cannot share code).
/// * Results are typed ([HealthPlatformResult]), never bare bools, so a
///   refusal carries its [HealthSyncCheck] reason all the way back to
///   the caller.
///
/// Pure Dart (R14/R16): no Flutter, channel, or platform imports here —
/// `test/architecture/layering_test.dart` enforces the discipline. The
/// implementations live in `lib/data/health/` (`ios_health_channel.dart`,
/// `android_health_channel.dart`, over the shared `health_channel.dart`).
library;

import '../models/local_date.dart';
import '../models/profile.dart';
import 'health_sync_policy.dart';

/// The closed, platform-intersection set of menstrual-flow intensities
/// this port can write. Mirrors the common ground of HealthKit's
/// `HKCategoryValueVaginalBleeding` (`unspecified`/`light`/`medium`/
/// `heavy`; `none` exists there but is deliberately absent here — a
/// "no sample" day is expressed by *not writing*, per #193's mapping
/// table) and Health Connect's `MenstruationFlowRecord` flow constants
/// (`FLOW_UNKNOWN`/`FLOW_LIGHT`/`FLOW_MEDIUM`/`FLOW_HEAVY`).
///
/// This is a *transport* vocabulary, not a domain one: mapping lunarlog's
/// [FlowLevel] (plus episode membership for the spotting rule) onto these
/// values is #193/#202's pure mapping function, which lives beside the
/// adapters in `lib/data/health/` — it does not belong in the domain.
enum HealthFlowValue {
  unspecified,
  light,
  medium,
  heavy;

  /// The wire string used on the `lunarlog/health` channel. Both native
  /// implementations and `health_channel_codec.dart` recognize exactly
  /// this closed set.
  String toWire() => switch (this) {
        unspecified => 'unspecified',
        light => 'light',
        medium => 'medium',
        heavy => 'heavy',
      };

  /// Parses the wire string; null when [raw] is not in the closed set (a
  /// newer native side than this Dart side, or corruption) — callers
  /// treat null as a protocol error, never a silent fallback.
  static HealthFlowValue? fromWire(String? raw) => switch (raw) {
        'unspecified' => unspecified,
        'light' => light,
        'medium' => medium,
        'heavy' => heavy,
        _ => null,
      };
}

/// The guard inputs every guarded port method carries: which [profile]'s
/// data is about to be written to this device's OS health store, and the
/// ownership facts `HealthSyncBinding.canWrite` evaluates (see
/// `health_sync_policy.dart` — [ownerUserId] is resolved via
/// [ownerUserIdFor] from the profile's guardian rows; [signedInUserId]
/// is the signed-in account's user id, null when signed out).
///
/// [minorBindingAllowed] is deliberately NOT a field here: it must be
/// sourced from `AppConfig.healthSyncMinorBindingAllowed` and nowhere
/// else, so the adapters take it as a constructor parameter from their
/// production wiring rather than accepting it per call — no call site can
/// invent its own per-call bypass.
class HealthGuardFacts {
  const HealthGuardFacts({
    required this.profile,
    required this.signedInUserId,
    required this.ownerUserId,
  });

  final Profile profile;

  /// The signed-in account's user id, or null when signed out.
  final String? signedInUserId;

  /// The profile's resolved owner (`ownerUserIdFor` over its accepted
  /// guardian rows), or null when ownership has not resolved.
  final String? ownerUserId;
}

/// The typed outcome of every guarded port method. A refusal carries its
/// [HealthSyncCheck] reason; platform failures are distinguished so the
/// caller (and, later, Settings copy) can tell "the guard said no" from
/// "HealthKit isn't on this device" from "the OS rejected the write".
sealed class HealthPlatformResult {
  const HealthPlatformResult();

  /// The guard (Dart- or native-side) allowed the operation and the
  /// platform performed it (for `requestWriteAuthorization`: the prompt
  /// completed).
  const factory HealthPlatformResult.allowed() = HealthPlatformAllowed;

  /// The guard refused; [check] is the deny reason, never
  /// [HealthSyncCheck.allowed]. No health API was touched.
  const factory HealthPlatformResult.refused(HealthSyncCheck check) =
      HealthPlatformRefused;

  /// No health store exists on this device (no HealthKit — e.g. iPad
  /// before iOS 17 — or Health Connect not installed/enabled).
  const factory HealthPlatformResult.unavailable() = HealthPlatformUnavailable;

  /// The OS denied the required permissions for this operation.
  const factory HealthPlatformResult.permissionDenied() =
      HealthPlatformPermissionDenied;

  /// The platform threw or answered with something this Dart side does
  /// not understand (including an unresolvable time zone — the write is
  /// refused rather than written at a wrong instant). [message] is
  /// diagnostic, never user-facing.
  const factory HealthPlatformResult.failed(String message) =
      HealthPlatformFailed;
}

final class HealthPlatformAllowed extends HealthPlatformResult {
  const HealthPlatformAllowed();
}

final class HealthPlatformRefused extends HealthPlatformResult {
  const HealthPlatformRefused(this.check) : assert(check != HealthSyncCheck.allowed);

  final HealthSyncCheck check;
}

final class HealthPlatformUnavailable extends HealthPlatformResult {
  const HealthPlatformUnavailable();
}

final class HealthPlatformPermissionDenied extends HealthPlatformResult {
  const HealthPlatformPermissionDenied();
}

final class HealthPlatformFailed extends HealthPlatformResult {
  const HealthPlatformFailed(this.message);

  final String message;
}

/// A `writeMenstrualFlow` payload: one logged day's bleed intensity for
/// the bound profile, plus the HealthKit cycle-start flag (#193:
/// `HKMetadataKeyMenstrualCycleStart` must be set on every menstrual
/// flow sample — true on the first day of a cycle, false otherwise,
/// sourced from `lib/domain/episodes/episodes.dart` by the caller).
///
/// [date]/[tzName] are the entry's own civil date and IANA zone (never
/// the device's current zone): the adapter converts them to platform
/// instants through `day_boundary.dart` — the #180 timezone contract —
/// so no native side ever does timezone arithmetic of its own.
class HealthMenstrualFlowWrite {
  const HealthMenstrualFlowWrite({
    required this.facts,
    required this.date,
    required this.tzName,
    required this.flow,
    required this.cycleStart,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;
  final HealthFlowValue flow;
  final bool cycleStart;
}

/// A `writeIntermenstrualBleeding` payload: one logged day of bleeding
/// outside a period episode (#193/A3-4's spotting rule — this type has
/// no intensity on either platform; HealthKit's
/// `intermenstrualBleeding` carries `HKCategoryValueNotApplicable` and
/// Health Connect's `IntermenstrualBleedingRecord` has no value field
/// at all: the record's existence is the datum). [date]/[tzName] as in
/// [HealthMenstrualFlowWrite].
class HealthIntermenstrualBleedingWrite {
  const HealthIntermenstrualBleedingWrite({
    required this.facts,
    required this.date,
    required this.tzName,
  });

  final HealthGuardFacts facts;
  final LocalDate date;
  final String tzName;
}

/// The platform-neutral health-store port (see the library doc for the
/// (a)-vs-(b) design decision). Implementations: `lib/data/health/`
/// (`MethodChannelHealthPlatform` shared, `IOSHealthChannel` and
/// `AndroidHealthChannel` pinning it to each platform's native
/// counterpart; `UnsupportedHealthPlatform` for web/desktop).
///
/// **Implementor contract:** every guarded method MUST (1) evaluate
/// `HealthSyncBinding.canWrite` with [HealthGuardFacts.profile] /
/// `signedInUserId` / `ownerUserId` and the adapter's
/// `minorBindingAllowed` *first*, returning `refused(check)` without any
/// channel invocation on a deny, and (2) forward the same facts so the
/// native handler re-evaluates the mirrored predicate against its own
/// natively-stored binding before touching any health API. `isAvailable`
/// is the one deliberately unguarded method: it is a static capability
/// probe (no health store access, no user data), and the Settings UI
/// needs it before any binding exists.
abstract interface class HealthPlatformStore {
  /// Whether this device has a health store at all (HealthKit present /
  /// Health Connect installed and available). Never touches user data.
  Future<bool> isAvailable();

  /// Records the native-side copy of the device-owner binding after the
  /// Dart-side `HealthSyncBinding.bind` succeeded — the value the
  /// native guard compares every write against, stored natively
  /// (UserDefaults / SharedPreferences) precisely so a Dart-side bug
  /// cannot rewrite it per call. Natively validates the same predicate
  /// `canBind` evaluates before storing; a refusal stores nothing.
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts);

  /// Clears the native-side binding copy (call alongside
  /// `HealthSyncBinding.unbind`).
  Future<void> unbindProfile();

  /// Prompts for write authorization for the types this port covers,
  /// behind the same guard (requesting HealthKit / Health Connect
  /// authorization is itself a health-API touch, so it is gated like a
  /// write). iOS's sheet has no programmatic denial answer — the OS
  /// reports completion, not the user's choice — so [allowed] there
  /// means "the prompt completed"; a denied permission surfaces on the
  /// first actual write as `permissionDenied`.
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  );

  /// Writes one day's menstrual flow sample for the bound profile.
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  );

  /// Writes one day's intermenstrual-bleeding record for the bound
  /// profile.
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  );
}
