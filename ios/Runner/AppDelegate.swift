import Flutter
import HealthKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Issue #623 (LLA-029): explicitly install this delegate before the
    // base implementation (and GeneratedPluginRegistrant, in
    // didInitializeImplicitFlutterEngine below) run. FlutterAppDelegate's
    // superclass conforms to UNUserNotificationCenterDelegate --
    // forwarding foreground presentation and notification-response
    // callbacks to registered plugins, flutter_local_notifications
    // included -- but never assigns itself as the *current* delegate; that
    // single slot is otherwise left for this app's Firebase Messaging
    // plugin to claim first for its own remote-notification handling,
    // which does not forward local-notification callbacks on to Flutter.
    // Without this, no local reminder tap (Issue #136's action buttons
    // included) and no foreground presentation ever reaches the Dart side.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Issue #244: the iOS half of the "lunarlog/privacy" channel — mirrors
    // MainActivity.kt's Android FLAG_SECURE handler on the same channel
    // name, adding an iOS-only method Android doesn't have (Dart never
    // calls "setFlagSecure" on this platform, so there's nothing to
    // implement here for it). Excludes the local database file (and its
    // sqlite -wal/-shm/-journal siblings, whichever exist at call time)
    // from iCloud/device backup and marks them
    // NSFileProtectionCompleteUntilFirstUserAuthentication (Issue #906).
    // See lib/startup/startup_native.dart's protectDatabaseFile() doc
    // comment for why CompleteUntilFirstUserAuthentication is the right class.
    FlutterMethodChannel(
      name: "lunarlog/privacy",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "protectDatabaseFile":
        guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(
            FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        AppDelegate.protectDatabaseFile(atPath: path)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Issue #173: the iOS half of the "lunarlog/health" channel — the
    // first-party HealthKit adapter (see HealthKitChannelHandler below,
    // and lib/domain/health/health_platform.dart's library doc for the
    // (a)-vs-(b) design decision). Registered exactly like the privacy
    // channel above; the Kotlin half lives in HealthConnectAdapter.kt.
    HealthKitChannelHandler.register(
      with: engineBridge.applicationRegistrar.messenger())
  }

  /// Best effort, matching the Dart caller's own best-effort contract
  /// (`protectDatabaseFile` in `lib/startup/startup_native.dart`): every
  /// step below is independent and a failure in one never stops the others
  /// or throws back across the channel.
  private static func protectDatabaseFile(atPath path: String) {
    let fileManager = FileManager.default
    let directoryPath = (path as NSString).deletingLastPathComponent

    // Round 2: protect the containing directory itself, not just the
    // files that exist at call time. A child inherits its parent
    // directory's NSFileProtectionCompleteUntilFirstUserAuthentication class,
    // and NSURLIsExcludedFromBackupKey on a directory excludes its current
    // *and future* contents — so a sqlite `-journal` sidecar created
    // after this method has already run once (this call only iterates
    // siblings that already exist below) is covered anyway.
    if fileManager.fileExists(atPath: directoryPath) {
      do {
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: directoryPath
        )
      } catch {
        // Best effort only — see the Dart-side doc comment.
      }

      var directoryUrl = URL(fileURLWithPath: directoryPath, isDirectory: true)
      var directoryResourceValues = URLResourceValues()
      directoryResourceValues.isExcludedFromBackup = true
      do {
        try directoryUrl.setResourceValues(directoryResourceValues)
      } catch {
        // Best effort only — see the Dart-side doc comment.
      }
    }

    let suffixes = ["", "-wal", "-shm", "-journal"]
    for suffix in suffixes {
      let siblingPath = path + suffix
      guard fileManager.fileExists(atPath: siblingPath) else { continue }

      // NSFileProtectionCompleteUntilFirstUserAuthentication: readable after
      // first unlock (Issue #906: avoids SIGBUS in SQLite WAL index when
      // background sync or push arrivals touch the database while the device
      // is locked).
      do {
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: siblingPath
        )
      } catch {
        // Best effort only — see the Dart-side doc comment.
      }

      // NSURLIsExcludedFromBackupKey: Application Support (where the
      // database now lives, issue #244) *is* included in iOS device/iCloud
      // backup by default — only tmp/ and Library/Caches/ are excluded
      // automatically — so this flag is doing real work here, not just
      // redundant hardening on top of the directory move.
      var url = URL(fileURLWithPath: siblingPath)
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      do {
        try url.setResourceValues(resourceValues)
      } catch {
        // Best effort only — see the Dart-side doc comment.
      }
    }
  }
}

// MARK: - Issue #173: the "lunarlog/health" channel's HealthKit half
//
// A first-party adapter over `HKHealthStore`, chosen over the pub.dev
// `health` package (which covers MENSTRUATION_FLOW only) — the full
// decision is recorded in lib/domain/health/health_platform.dart's
// library doc so it is not re-litigated; the wire protocol both sides
// speak is defined in lib/data/health/health_channel_codec.dart (keys,
// method names, and result strings there are the single source of
// truth — keep this file in sync with it, and with the Kotlin half in
// HealthConnectAdapter.kt).
//
// The load-bearing property: **the #153 guard (profile↔device-owner
// binding + owner-not-guardian) is re-evaluated HERE, from this
// device's own UserDefaults copy of the binding, before ANY health API
// is touched** — not merely trusted from the Dart side. The predicate
// below is a deliberate native mirror of HealthSyncBinding._evaluate
// (lib/domain/health/health_sync_binding.dart): the two sides cannot
// share code, and the duplication is the safety property issue #173
// demands — a Dart-side ordering bug can at most cause a redundant
// native allow-path to be *reached*, never a guard bypass, because this
// copy denies (and never constructs an HKCategorySample) on its own.
// Fail-closed on disagreement: a write only proceeds when BOTH the
// Dart-side settings store and this UserDefaults copy name the written
// profile.
//
// Issue #882: the shared rule was reworked and this mirror MUST match it
// exactly (a drift here re-closes the gate on a real device even though
// Dart allows it). A minor profile is no longer a special deny when
// `minorBindingAllowed` is true (the production value): it passes the
// same owner check as any adult, and the device-only case — nobody
// signed in AND no owner resolved — is allowed. When
// `minorBindingAllowed` is false the pre-#882 categorical
// `minorRequiresOwnershipTransfer` deny is preserved. The Kotlin half in
// HealthConnectAdapter.kt (Android) carries the same mirror.
//
// App Review guideline 5.1.3 (issue #254): this handler saves only
// user-logged or imported data — a flow level, a spotting marker, and
// the cycle-start metadata flag derived from that same logged bleed
// history. It must never write a predicted or derived cycle value (no
// next-period prediction, no fertile-window or ovulation estimate);
// the written rule lives in lib/data/health/health_channel.dart's
// library doc and both halves of the channel are bound by it.
//
// Keeping this handler inside AppDelegate.swift (rather than its own
// file) is deliberate: a new .swift file requires an Xcode project-file
// edit that cannot be safely hand-written without a Mac, and the
// privacy channel above already established in-file channel handlers as
// this app's registration pattern.
enum HealthKitChannelHandler {
  static let channelName = "lunarlog/health"
  static let boundProfileKey = "lunarlog.health.boundProfileId"

  /// One HKHealthStore for the process (Apple recommends sharing an
  /// instance; creating it is safe even where HealthKit is unavailable,
  /// which is what the `unavailable` early-returns below are for).
  static let store = HKHealthStore()

  /// HKCategoryValueVaginalBleeding's raw values, which are identical
  /// to the deprecated-in-iOS-18 HKCategoryValueMenstrualFlow's
  /// (`unspecified` = 1, `light` = 2, `medium` = 3, `heavy` = 4 — issue
  /// #619, LLA-021: independently verified against the Apple SDK
  /// constants — see the PR description — after this file previously
  /// carried an off-by-one table (`unspecified` = 0 etc., which is
  /// actually `HKCategoryValue.notApplicable`'s value, shared by types
  /// with no intensity like intermenstrualBleeding below). The pre-fix
  /// table silently understated every written sample by one grade: a
  /// `heavy` write landed as `medium`, `medium` as `light`, and `light`
  /// as `unspecified`. Declared as bare raw values, not the SDK symbols,
  /// so this compiles against both older and newer SDKs with no
  /// availability branch and no deprecation warning; swapping to
  /// `HKCategoryValueVaginalBleeding.light.rawValue` (iOS 18+ symbol)
  /// yields the same integers.
  enum MenstrualFlowRawValue: Int {
    case unspecified = 1
    case light = 2
    case medium = 3
    case heavy = 4

    init?(wire: String) {
      switch wire {
      case "unspecified": self = .unspecified
      case "light": self = .light
      case "medium": self = .medium
      case "heavy": self = .heavy
      default: return nil
      }
    }

    /// The wire string for the read direction (Issue #217), mirroring
    /// `HealthFlowValue.toWire()` in `health_channel_codec.dart`. Only the
    /// three real intensities are ever read back intentionally; a stored
    /// `unspecified` is still mapped so the Dart codec can recognise and
    /// count it rather than treat the sample as malformed.
    var wire: String {
      switch self {
      case .unspecified: return "unspecified"
      case .light: return "light"
      case .medium: return "medium"
      case .heavy: return "heavy"
      }
    }
  }

  /// HKCategoryValueSeverity's raw values (Issue #238, corrected in #917):
  /// Apple defines (HKCategoryValues.h:209-215):
  ///   HKCategoryValueSeverityUnspecified = 0
  ///   HKCategoryValueSeverityNotPresent  = 1
  ///   HKCategoryValueSeverityMild        = 2
  ///   HKCategoryValueSeverityModerate    = 3
  ///   HKCategoryValueSeveritySevere      = 4
  ///
  /// lunarlog writes: `unspecified` = 0, `mild` = 2, `moderate` = 3, `severe` = 4.
  /// Identical values to `kHealthSymptomSeverityAppleRawValue` in
  /// lib/data/health/health_channel_codec.dart (the single source of
  /// truth). `notPresent` = 1 is deliberately never written — lunarlog only
  /// writes symptoms when present.
  static func severity(forWire wire: String) -> HKCategoryValueSeverity? {
    switch wire {
    case "unspecified": return .unspecified
    case "mild": return .mild
    case "moderate": return .moderate
    case "severe": return .severe
    default: return nil
    }
  }

  /// Maps wire symptom type names (from `health_symptom_mapping.dart`) to
  /// typed `HKCategoryTypeIdentifier` enum cases (Issue #238, corrected in #916).
  /// Accepting both the Dart camelCase case name and the full SDK rawValue
  /// guarantees no nil-lookups in `HKObjectType.categoryType(forIdentifier:)`.
  static let symptomCategoryTypeIdentifiers: [String: HKCategoryTypeIdentifier] = [
    "abdominalCramps": .abdominalCramps,
    "headache": .headache,
    "lowerBackPain": .lowerBackPain,
    "breastPain": .breastPain,
    "bloating": .bloating,
    "acne": .acne,
    "nausea": .nausea,
    "fatigue": .fatigue,
    "dizziness": .dizziness,
    "moodChanges": .moodChanges,
    "sleepChanges": .sleepChanges,
    "appetiteChanges": .appetiteChanges,
    // Also accept canonical HKCategoryTypeIdentifier.rawValue strings:
    HKCategoryTypeIdentifier.abdominalCramps.rawValue: .abdominalCramps,
    HKCategoryTypeIdentifier.headache.rawValue: .headache,
    HKCategoryTypeIdentifier.lowerBackPain.rawValue: .lowerBackPain,
    HKCategoryTypeIdentifier.breastPain.rawValue: .breastPain,
    HKCategoryTypeIdentifier.bloating.rawValue: .bloating,
    HKCategoryTypeIdentifier.acne.rawValue: .acne,
    HKCategoryTypeIdentifier.nausea.rawValue: .nausea,
    HKCategoryTypeIdentifier.fatigue.rawValue: .fatigue,
    HKCategoryTypeIdentifier.dizziness.rawValue: .dizziness,
    HKCategoryTypeIdentifier.moodChanges.rawValue: .moodChanges,
    HKCategoryTypeIdentifier.sleepChanges.rawValue: .sleepChanges,
    HKCategoryTypeIdentifier.appetiteChanges.rawValue: .appetiteChanges,
  ]

  /// Apple's four computed cycle-deviation category types (Issue #799,
  /// deferred from #217), resolved by their canonical
  /// `HKCategoryTypeIdentifier` **raw-value** strings rather than the enum
  /// cases: the types are iOS 16-only while this target deploys to iOS 15,
  /// and `init(rawValue:)` is available at the older floor.
  ///
  /// **These are read-only, permanently.** They are Apple-computed from the
  /// user's own logged data, and App Review 5.1.3 forbids writing derived
  /// data into HealthKit. This table is consumed only by the read path
  /// (`readCycleDeviations`) and the read authorization set
  /// (`deviationReadTypes`); it is deliberately absent from
  /// `writtenCategoryTypeIdentifiers`, so no write or delete path can reach
  /// it. The Dart side sends the same raw-value strings
  /// (`HealthDeviationKind.healthKitIdentifier`), and
  /// `test/release/health_deviation_read_types_test.dart` parses this table
  /// and pins the two together.
  static let deviationKinds: [(wire: String, identifier: String)] = [
    (
      wire: "irregularMenstrualCycles",
      identifier: "HKCategoryTypeIdentifierIrregularMenstrualCycles"
    ),
    (
      wire: "infrequentMenstrualCycles",
      identifier: "HKCategoryTypeIdentifierInfrequentMenstrualCycles"
    ),
    (
      wire: "prolongedMenstrualPeriods",
      identifier: "HKCategoryTypeIdentifierProlongedMenstrualPeriods"
    ),
    (
      wire: "persistentIntermenstrualBleeding",
      identifier: "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding"
    ),
  ]

  /// The four deviation types as `HKCategoryType`s for the read
  /// authorization set. The iOS 16-only identifiers resolve to nil (and are
  /// dropped by `compactMap`) on an older OS, so the requested set is simply
  /// smaller there. Never added to the write/share set.
  static var deviationReadTypes: [HKCategoryType] {
    deviationKinds.compactMap { entry in
      HKObjectType.categoryType(
        forIdentifier: HKCategoryTypeIdentifier(rawValue: entry.identifier))
    }
  }

  /// Resolves a wire name (or a canonical raw-value string) to its
  /// `HKCategoryType`, or nil when the caller asked for something outside
  /// the closed set — a protocol error the handler reports rather than
  /// silently ignoring.
  static func deviationCategoryType(forWire wire: String) -> HKCategoryType? {
    guard
      let entry = deviationKinds.first(where: {
        $0.wire == wire || $0.identifier == wire
      })
    else { return nil }
    return HKObjectType.categoryType(
      forIdentifier: HKCategoryTypeIdentifier(rawValue: entry.identifier))
  }

  /// Every HealthKit **category** type this app's write path can produce,
  /// as the `HKCategoryTypeIdentifier` case names the `write*` handlers
  /// resolve: #193' flow types, #238's symptom categories, and #228's
  /// fertility types. This is the single list the authorization sheet and
  /// `deleteRecords` both consume, so a new write type cannot be added
  /// without also being requested AND deleted.
  ///
  /// Issue #924: before this list existed, `deleteRecords` queried only the
  /// two flow types #186 knew about, so every sample #238/#228 added was
  /// written but never removed — a privacy gap, not just a feature gap.
  /// Keep in sync with `kHealthKitWrittenCategoryTypeCaseNames` in
  /// `lib/data/health/health_written_types.dart`; the guard test
  /// `test/release/health_deletion_types_test.dart` parses THIS array and
  /// fails if it drifts.
  private static let writtenCategoryTypeIdentifiers: [HKCategoryTypeIdentifier] = [
    // #193: menstrual flow and the spotting-outside-an-episode marker.
    .menstrualFlow,
    .intermenstrualBleeding,
    // #238: the symptom categories the tag table maps to.
    .abdominalCramps,
    .headache,
    .lowerBackPain,
    .breastPain,
    .bloating,
    .acne,
    .nausea,
    .fatigue,
    .dizziness,
    .moodChanges,
    .sleepChanges,
    .appetiteChanges,
    // #228: the fertility types.
    .cervicalMucusQuality,
    .ovulationTestResult,
  ]

  /// The HealthKit **quantity** types this app writes — a different
  /// `HKSampleType` path from every category type above (BBT is resolved
  /// with `HKObjectType.quantityType(forIdentifier:)`, not
  /// `categoryType`). Issue #228; today exactly one. Keep in sync with
  /// `kHealthKitWrittenQuantityTypeCaseNames` and the same guard test.
  private static let writtenQuantityTypeIdentifiers: [HKQuantityTypeIdentifier] = [
    .basalBodyTemperature,
  ]

  /// [writtenCategoryTypeIdentifiers] and [writtenQuantityTypeIdentifiers]
  /// resolved into one `HKSampleType` list — category and quantity types
  /// are both `HKSampleType`, so a single loop drives both the
  /// authorization request and the delete query. Deliberately derived from
  /// the two identifier lists rather than hand-written a second time.
  private static var writtenSampleTypes: [HKSampleType] {
    var types: [HKSampleType] = writtenCategoryTypeIdentifiers.compactMap {
      HKObjectType.categoryType(forIdentifier: $0)
    }.map { $0 as HKSampleType }
    types.append(contentsOf: writtenQuantityTypeIdentifiers.compactMap {
      HKObjectType.quantityType(forIdentifier: $0)
    }.map { $0 as HKSampleType })
    return types
  }

  /// The guard-args half of every guarded call (mirrors
  /// `encodeGuardArgs` in health_channel_codec.dart).
  struct GuardArgs {
    let profileId: String
    let signedInUserId: String?
    let ownerUserId: String?
    let isMinor: Bool
    let birthYear: Int?
    let transferredAtMs: NSNumber?
    // Issue #619, LLA-031: the server-stamped transfer target, mirroring
    // HealthSyncBinding._minorTransferExceptionHolds's `target ==
    // signedInUserId` leg — without this, guardDecision could only see
    // THAT a transfer happened, never WHOM it named.
    let transferredToUserId: String?
    let minorBindingAllowed: Bool

    init?(_ args: [String: Any]) {
      guard let profileId = args["profileId"] as? String else { return nil }
      guard let isMinorNumber = args["isMinor"] as? NSNumber else { return nil }
      guard
        let minorAllowedNumber = args["minorBindingAllowed"] as? NSNumber
      else { return nil }
      self.profileId = profileId
      self.signedInUserId = args["signedInUserId"] as? String
      self.ownerUserId = args["ownerUserId"] as? String
      self.isMinor = isMinorNumber.boolValue
      self.birthYear = (args["birthYear"] as? NSNumber)?.intValue
      self.transferredAtMs = args["transferredAtMs"] as? NSNumber
      self.transferredToUserId = args["transferredToUserId"] as? String
      self.minorBindingAllowed = minorAllowedNumber.boolValue
    }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        handle(call, result: result)
      }
  }

  private static func badArgs(_ result: @escaping FlutterResult, _ what: String) {
    result(FlutterError(code: "bad_args", message: what, details: nil))
  }

  /// The native mirror of HealthSyncBinding._evaluate (Issue #882 keeps
  /// this in lockstep with the Dart predicate; the Kotlin half is in
  /// HealthConnectAdapter.kt). Returns the same wire strings the Dart
  /// codec decodes ("allowed" or a HealthSyncCheck deny name).
  /// `boundProfileId` comes from UserDefaults for write/authorization
  /// calls, and from the *proposed* id for `bind` (mirroring canBind's
  /// proposed-binding semantics).
  static func guardDecision(boundProfileId: String?, _ g: GuardArgs) -> String {
    guard let boundProfileId else { return "noBinding" }
    if g.profileId != boundProfileId { return "profileNotBound" }

    let isOwner =
      g.signedInUserId != nil && g.ownerUserId != nil
      && g.signedInUserId == g.ownerUserId

    // Issue #882: the switch's off position keeps the pre-#882
    // categorical minor deny. With `minorBindingAllowed` true a minor is
    // NOT special — it falls through to the same owner gate as an adult.
    if isMinorNow(isMinor: g.isMinor, birthYear: g.birthYear)
      && !g.minorBindingAllowed
    {
      return "minorRequiresOwnershipTransfer"
    }

    // Issue #619, LLA-031: every leg of
    // HealthSyncBinding._minorTransferExceptionHolds — the flag is on, a
    // transfer happened, the caller is the resolved owner, AND it named
    // exactly the signed-in account — not merely "some transfer happened
    // and the caller happens to pass isOwner". Preserved by #882; the
    // owner gate below would allow every case this holds for.
    let minorTransferExceptionHolds =
      g.minorBindingAllowed && g.transferredAtMs != nil && isOwner
      && g.transferredToUserId != nil
      && g.transferredToUserId == g.signedInUserId
    if minorTransferExceptionHolds {
      return "allowed"
    }

    // Issue #882: no resolved owner at all means allowed — nobody else
    // claims the profile, so the local operator is treated as its owner
    // (this is the common case for a locally created, never-synced
    // profile). notOwner is returned only when an owner actually exists
    // and does not match the signed-in account.
    if !ownerCheckAllows(ownerUserId: g.ownerUserId, isOwner: isOwner) {
      return "notOwner"
    }
    return "allowed"
  }

  /// Native mirror of HealthSyncBinding._ownerCheckAllows (Issue #882):
  /// `ownerUserId == nil` (no accepted primary_guardian row resolved, even
  /// while signed in) passes, and so does a resolved owner. It fails
  /// closed only when an owner exists and is not the signed-in account.
  static func ownerCheckAllows(
    ownerUserId: String?,
    isOwner: Bool
  ) -> Bool {
    return isOwner || ownerUserId == nil
  }

  /// Native mirror of HealthSyncBinding._isMinorNow: flagged directly, or
  /// AT MOST 18 whole years since birthYear (issue #619, LLA-031: `<=`,
  /// not `<` — matching the Dart side's Issue #296 tightening, where a
  /// year-only birthYear can't see the birthday so the whole calendar
  /// year someone turns 18 still fails closed. The pre-fix `< 18` here
  /// let a birth year exactly 18 years back read as an adult while Dart
  /// still denied it — a defense-in-depth gap, not a live bypass, since
  /// the Dart guard already covered it.
  static func isMinorNow(isMinor: Bool, birthYear: Int?) -> Bool {
    if isMinor { return true }
    guard let birthYear else { return false }
    let nowYear = Calendar(identifier: .gregorian).component(.year, from: Date())
    return nowYear - birthYear <= 18
  }

  /// The stored native binding copy — the value every write is checked
  /// against. Stored in UserDefaults (a random profile ULID, not health
  /// data) so a Dart-side bug cannot rewrite it per call.
  static var storedBoundProfileId: String? {
    UserDefaults.standard.string(forKey: boundProfileKey)
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "isAvailable":
      // The one deliberately unguarded method: a static capability
      // probe — no health store access, no user data (the Dart port
      // documents this too).
      result(HKHealthStore.isHealthDataAvailable())

    case "bind":
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "bind requires guard args")
        return
      }
      // Proposed-binding semantics (mirrors canBind): evaluate against
      // the id being bound, store only if every other check passes.
      let decision = guardDecision(boundProfileId: g.profileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      UserDefaults.standard.set(g.profileId, forKey: boundProfileKey)
      result("allowed")

    case "unbind":
      UserDefaults.standard.removeObject(forKey: boundProfileKey)
      result(nil)

    case "requestWriteAuthorization":
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "requestWriteAuthorization requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      // Issue #924: the single written-type list drives the permission
      // sheet, so authorization, the writes, and deleteRecords can never
      // drift apart. Apple's permission sheet is per-type; an existing
      // install is prompted for a newly added type on the next sync pass.
      // The read set below is deliberately unchanged (issue #766 governs
      // reads).
      let toShare = Set(writtenSampleTypes)
      // Issue #217: the read set is no longer empty. It carries the
      // menstrual-flow type the user-initiated import reads, plus (Issue
      // #799) the four Apple-computed cycle-deviation types the overview
      // insight reads. The deviation types are read-only, permanently:
      // they are joined to `toRead` only and never to `toShare`, and no
      // write/delete path resolves them. `deviationReadTypes` drops the
      // iOS 16-only identifiers on an older OS, so the requested set is
      // simply smaller there. The one system sheet covers both the write
      // types and the read types.
      let toRead: Set<HKObjectType> = Set(
        [menstrualFlowType as HKObjectType]
          + deviationReadTypes.map { $0 as HKObjectType })
      Task {
        do {
          // iOS's sheet reports completion, not the user's choice —
          // denial only surfaces on the first actual write/read.
          _ = try await store.requestAuthorization(
            toShare: toShare, read: toRead)
          result("allowed")
        } catch {
          result(
            FlutterError(
              code: "writeFailed",
              message: "requestAuthorization failed: \(error.localizedDescription)",
              details: nil))
        }
      }

    case "permissionStatus":
      // Issue #959: the OS write (share) permission state for the status
      // line on the Health sync screen. Deliberately consults ONLY the
      // write sample types (`writtenSampleTypes`, the same list the
      // authorization sheet and deleteRecords use): HealthKit's read
      // authorization is opaque by Apple's design, so a denied read must
      // never be reported as a refusal here. `.sharingDenied` is the only
      // denial that maps to "denied"; a partial grant (some types denied)
      // reports denied, because writes to those types will fail.
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      var denied = false
      var notAsked = false
      for type in writtenSampleTypes {
        switch store.authorizationStatus(for: type) {
        case .sharingDenied:
          denied = true
        case .notDetermined:
          notAsked = true
        case .sharingAuthorized:
          break
        @unknown default:
          break
        }
      }
      if denied {
        result("denied")
      } else if notAsked {
        result("notAsked")
      } else {
        result("granted")
      }

    case "openPermissionSettings":
      // Issue #959: the settings deep link offered when the status line is
      // denied. iOS only lets an app open its OWN Settings page, which is
      // exactly where the Apple Health permission for lunarlog lives.
      DispatchQueue.main.async {
        guard let url = URL(string: UIApplication.openSettingsURLString)
        else {
          result(nil)
          return
        }
        UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
      }

    case "writeMenstrualFlow":
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeMenstrualFlow requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let flowWire = args?["flow"] as? String,
        let flow = MenstrualFlowRawValue(wire: flowWire),
        let cycleStartNumber = args?["cycleStart"] as? NSNumber,
        let recordId = args?["recordId"] as? String,
        let recordVersionMs = args?["recordVersionMs"] as? NSNumber
      else {
        badArgs(
          result,
          "writeMenstrualFlow requires startMs/endMs/flow/cycleStart/recordId/recordVersionMs")
        return
      }
      // #193: HKMetadataKeyMenstrualCycleStart is required on every
      // menstrualFlow sample — true on the first day of a cycle, false
      // otherwise (sourced on the Dart side from episodes.dart).
      // #186: HKMetadataKeyExternalUUID carries lunarlog's own record id
      // (the day_entry ULID) so a future re-import can recognise this
      // sample as our own write (the backup loop-breaker) and a tombstone
      // can locate and delete exactly it (deleteRecords below queries by
      // this key).
      // Issue #619, LLA-022: HKMetadataKeySyncIdentifier +
      // HKMetadataKeySyncVersion are HealthKit's own documented upsert
      // mechanism (Apple's WWDC20 "Synchronize health data with
      // HealthKit") — saving with the SAME sync identifier and a HIGHER
      // sync version REPLACES the existing sample in place instead of
      // creating a duplicate. `recordVersionMs` (the source row's
      // `updatedAt`) was previously accepted on the wire but never read
      // here, so a re-export of an edited day always duplicated rather
      // than updated.
      let sample = HKCategorySample(
        type: menstrualFlowType,
        value: flow.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [
          HKMetadataKeyMenstrualCycleStart: cycleStartNumber,
          HKMetadataKeyExternalUUID: recordId,
          HKMetadataKeySyncIdentifier: recordId,
          HKMetadataKeySyncVersion: recordVersionMs,
        ]
      )
      save([sample], result: result)

    case "writeIntermenstrualBleeding":
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeIntermenstrualBleeding requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let recordId = args?["recordId"] as? String,
        let recordVersionMs = args?["recordVersionMs"] as? NSNumber
      else {
        badArgs(
          result, "writeIntermenstrualBleeding requires startMs/endMs/recordId/recordVersionMs")
        return
      }
      // No intensity on this type: HKCategoryValueNotApplicable — the
      // sample's existence is the datum (#193/A3-4).
      // #186: HKMetadataKeyExternalUUID, as for writeMenstrualFlow.
      // Issue #619, LLA-022: HKMetadataKeySyncIdentifier/SyncVersion, as
      // for writeMenstrualFlow — see that case's comment.
      let sample = HKCategorySample(
        type: intermenstrualBleedingType,
        value: HKCategoryValue.notApplicable.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [
          HKMetadataKeyExternalUUID: recordId,
          HKMetadataKeySyncIdentifier: recordId,
          HKMetadataKeySyncVersion: recordVersionMs,
        ]
      )
      save([sample], result: result)

    case "writeSymptomSamples":
      // Issue #238: one logged day's symptom samples. The tag table and
      // every mapping/severity decision live in Dart
      // (lib/data/health/health_symptom_mapping.dart); this case only
      // resolves the already-decided wire values into HKCategorySamples.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeSymptomSamples requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let samples = args?["samples"] as? [[String: Any]],
        !samples.isEmpty
      else {
        badArgs(result, "writeSymptomSamples requires startMs/endMs/samples")
        return
      }
      let start = Date(timeIntervalSince1970: Double(startMs) / 1000.0)
      let end = Date(timeIntervalSince1970: Double(endMs) / 1000.0)
      var toSave: [HKSample] = []
      for sample in samples {
        guard
          let typeWire = sample["typeIdentifier"] as? String,
          let severityWire = sample["severity"] as? String,
          let severity = HealthKitChannelHandler.severity(forWire: severityWire),
          let recordId = sample["recordId"] as? String,
          let recordVersionMs = sample["recordVersionMs"] as? NSNumber
        else {
          badArgs(result, "writeSymptomSamples requires fully-resolved samples")
          return
        }
        guard
          let typeIdentifier = HealthKitChannelHandler.symptomCategoryTypeIdentifiers[typeWire],
          let categoryType = HKObjectType.categoryType(forIdentifier: typeIdentifier)
        else {
          badArgs(result, "unknown symptom type: \(typeWire)")
          return
        }
        // #186 sync mechanics, as for writeMenstrualFlow:
        // HKMetadataKeyExternalUUID/Identifier/Version make the write
        // idempotent and addressable by record id. No cycle-start flag —
        // that is a menstrual-flow concept.
        toSave.append(
          HKCategorySample(
            type: categoryType,
            value: severity.rawValue,
            start: start,
            end: end,
            metadata: [
              HKMetadataKeyExternalUUID: recordId,
              HKMetadataKeySyncIdentifier: recordId,
              HKMetadataKeySyncVersion: recordVersionMs,
            ]
          )
        )
      }
      save(toSave, result: result)

    case "writeCervicalMucus":
      // Issue #228: the appearance decision lives in Dart
      // (health_fertility_mapping.dart); this case only resolves the
      // already-decided value into an HKCategorySample. Health Connect's
      // required `sensation` field has no HealthKit concept and is not sent.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeCervicalMucus requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let valueWire = args?["healthKitValue"] as? String,
        let recordId = args?["recordId"] as? String,
        let recordVersionMs = args?["recordVersionMs"] as? NSNumber
      else {
        badArgs(
          result,
          "writeCervicalMucus requires startMs/endMs/healthKitValue/recordId/recordVersionMs")
        return
      }
      let cervicalValue: HKCategoryValueCervicalMucusQuality
      switch valueWire {
      case "dry": cervicalValue = .dry
      case "sticky": cervicalValue = .sticky
      case "creamy": cervicalValue = .creamy
      case "watery": cervicalValue = .watery
      case "eggWhite": cervicalValue = .eggWhite
      default:
        badArgs(result, "unknown cervical-mucus value: \(valueWire)")
        return
      }
      let mucusSample = HKCategorySample(
        type: cervicalMucusType,
        value: cervicalValue.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [
          HKMetadataKeyExternalUUID: recordId,
          HKMetadataKeySyncIdentifier: recordId,
          HKMetadataKeySyncVersion: recordVersionMs,
        ]
      )
      save([mucusSample], result: result)

    case "writeOvulationTest":
      // Issue #228: the result decision (including positive/peak collapse
      // and the luteinizingHormoneSurge naming) lives in Dart; this case
      // only translates the resolved case name.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeOvulationTest requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let resultWire = args?["healthKitResult"] as? String,
        let recordId = args?["recordId"] as? String,
        let recordVersionMs = args?["recordVersionMs"] as? NSNumber
      else {
        badArgs(
          result,
          "writeOvulationTest requires startMs/endMs/healthKitResult/recordId/recordVersionMs")
        return
      }
      let ovulationResult: HKCategoryValueOvulationTestResult
      switch resultWire {
      case "negative": ovulationResult = .negative
      case "luteinizingHormoneSurge": ovulationResult = .luteinizingHormoneSurge
      case "indeterminate": ovulationResult = .indeterminate
      default:
        badArgs(result, "unknown ovulation-test result: \(resultWire)")
        return
      }
      let ovulationSample = HKCategorySample(
        type: ovulationTestType,
        value: ovulationResult.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [
          HKMetadataKeyExternalUUID: recordId,
          HKMetadataKeySyncIdentifier: recordId,
          HKMetadataKeySyncVersion: recordVersionMs,
        ]
      )
      save([ovulationSample], result: result)

    case "writeBasalBodyTemperature":
      // Issue #228: the value is already in Celsius (Dart converts via
      // #255's convertTemperature); this case only builds the HKQuantity.
      // A platform/wearable-sourced value never reaches here — the Dart
      // resolver filters by source before the write is built.
      // Issue #920: BBT is a point/waking measurement (start == end),
      // never a whole-day envelope ending at 23:59:59.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "writeBasalBodyTemperature requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value
          ?? (args?["instantMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value
          ?? (args?["instantMs"] as? NSNumber)?.int64Value,
        let celsius = args?["celsius"] as? NSNumber,
        let recordId = args?["recordId"] as? String,
        let recordVersionMs = args?["recordVersionMs"] as? NSNumber
      else {
        badArgs(
          result,
          "writeBasalBodyTemperature requires startMs/endMs/celsius/recordId/recordVersionMs")
        return
      }
      let temperatureSample = buildBasalBodyTemperatureSample(
        celsius: celsius.doubleValue,
        startMs: startMs,
        endMs: endMs,
        recordId: recordId,
        recordVersionMs: recordVersionMs
      )
      save([temperatureSample], result: result)

    case "deleteRecords":
      // Issue #186 tombstone propagation: delete the samples whose
      // HKMetadataKeyExternalUUID is one of the supplied lunarlog record
      // ids. HealthKit can only delete samples the app itself saved, so we
      // first query every type this app writes by their external-UUID
      // metadata, then delete exactly those — a record we never wrote (or a
      // per-type mismatch) is simply absent from the query result. Behind
      // the same guard as every write (a deletion is a health-API touch).
      //
      // Issue #924: "every type this app writes" is
      // `writtenSampleTypes`, the SAME list the authorization sheet uses —
      // not the two flow types this case queried before, which left every
      // #238/#228 sample (symptoms, cervical mucus, ovulation, BBT)
      // orphaned forever. A record the app never wrote is never requested
      // and matches nothing if it is. BBT rides the same loop: it is a
      // quantity `HKSampleType`, resolved in `writtenSampleTypes`.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "deleteRecords requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard let recordIds = args?["recordIds"] as? [String], !recordIds.isEmpty else {
        badArgs(result, "deleteRecords requires recordIds")
        return
      }
      Task {
        do {
          let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: recordIds)
          // Query EVERY written type by its external-UUID metadata, then
          // delete exactly those samples. HealthKit's delete(_:) can only
          // remove samples the app itself saved, so a record we never wrote
          // is simply absent from the query result. `HKHealthStore` has no
          // `samples(ofType:predicate:limit:)` method and no async `delete`
          // overload, so both calls below go through the standard
          // callback-based APIs wrapped in continuations (`HKSampleQuery` +
          // `store.execute(_:)`, and `store.delete(_:withCompletion:)`).
          var toDelete: [HKSample] = []
          for sampleType in writtenSampleTypes {
            toDelete.append(
              contentsOf: try await querySamples(
                ofType: sampleType,
                predicate: predicate))
          }
          if !toDelete.isEmpty {
            try await delete(toDelete)
          }
          result("allowed")
        } catch {
          result(
            FlutterError(
              code: "writeFailed",
              message: "deleteRecords failed: \(error.localizedDescription)",
              details: nil))
        }
      }

    case "readMenstrualFlowPage":
      // Issue #217 (#781's read decision), paged for full history in Issue
      // #992. Guarded identically to a write (the device-binding decision is
      // the same), then one page of an `HKAnchoredObjectQuery`. Success
      // returns a Map of `{samples, nextCursor?}` (StandardMessageCodec),
      // not a result string; authorization opacity means a denied read
      // arrives here as a page with an empty samples list, never an error.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "readMenstrualFlowPage requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value,
        let pageSize = (args?["pageSize"] as? NSNumber)?.intValue,
        pageSize > 0
      else {
        badArgs(result, "readMenstrualFlowPage requires startMs/endMs/pageSize")
        return
      }
      let cursor = args?["cursor"] as? String
      Task {
        do {
          let payload = try await readMenstrualFlowPage(
            start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
            end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
            cursor: cursor,
            pageSize: pageSize)
          result(payload)
        } catch {
          result(
            FlutterError(
              code: "readFailed",
              message: "readMenstrualFlowPage failed: \(error.localizedDescription)",
              details: nil))
        }
      }

    case "readCycleDeviations":
      // Issue #799 (deferred from #217): Apple's four computed cycle-deviation
      // types, read-only. Guarded identically to every other read/write (the
      // device-binding decision is the same); the caller sends its closed kind
      // list, resolved here against `deviationKinds` so an unknown wire name
      // is a bad-args protocol error rather than a silent skip. Success
      // returns an array of primitive maps (StandardMessageCodec), never a
      // result string; authorization opacity means a denied read arrives as an
      // empty array. Nothing here can write a deviation type.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "readCycleDeviations requires guard args")
        return
      }
      let decision = guardDecision(boundProfileId: storedBoundProfileId, g)
      guard decision == "allowed" else {
        result(decision)
        return
      }
      guard HKHealthStore.isHealthDataAvailable() else {
        result("unavailable")
        return
      }
      guard
        let startMs = (args?["startMs"] as? NSNumber)?.int64Value,
        let endMs = (args?["endMs"] as? NSNumber)?.int64Value
      else {
        badArgs(result, "readCycleDeviations requires startMs/endMs")
        return
      }
      let requested = (args?["kinds"] as? [String]) ?? []
      var requestedPairs: [(wire: String, type: HKCategoryType)] = []
      for wire in requested {
        guard
          let entry = deviationKinds.first(where: {
            $0.wire == wire || $0.identifier == wire
          }),
          let type = deviationCategoryType(forWire: wire)
        else {
          badArgs(result, "readCycleDeviations unknown kind: \(wire)")
          return
        }
        requestedPairs.append((wire: entry.wire, type: type))
      }
      Task {
        do {
          let payload = try await readCycleDeviationSamples(
            types: requestedPairs,
            start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
            end: Date(timeIntervalSince1970: Double(endMs) / 1000.0))
          result(payload)
        } catch {
          result(
            FlutterError(
              code: "readFailed",
              message:
                "readCycleDeviations failed: \(error.localizedDescription)",
              details: nil))
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var menstrualFlowType: HKCategoryType {
    HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
  }

  private static var intermenstrualBleedingType: HKCategoryType {
    HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding)!
  }

  /// Issue #228: the fertility/measurement write types. `cervicalMucusQuality`
  /// and `ovulationTestResult` are category types; `basalBodyTemperature` is
  /// a quantity type (a different native code path — see
  /// `writeBasalBodyTemperature`).
  private static var cervicalMucusType: HKCategoryType {
    HKObjectType.categoryType(forIdentifier: .cervicalMucusQuality)!
  }

  private static var ovulationTestType: HKCategoryType {
    HKObjectType.categoryType(forIdentifier: .ovulationTestResult)!
  }

  private static var basalBodyTemperatureType: HKQuantityType {
    HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)!
  }

  /// Builds an HKQuantitySample for Basal Body Temperature (Issue #228, #920).
  /// BBT is a point/waking measurement: start and end dates are identical.
  static func buildBasalBodyTemperatureSample(
    celsius: Double,
    startMs: Int64,
    endMs: Int64,
    recordId: String,
    recordVersionMs: NSNumber
  ) -> HKQuantitySample {
    HKQuantitySample(
      type: basalBodyTemperatureType,
      quantity: HKQuantity(
        unit: HKUnit.degreeCelsius(), doubleValue: celsius),
      start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
      end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
      metadata: [
        HKMetadataKeyExternalUUID: recordId,
        HKMetadataKeySyncIdentifier: recordId,
        HKMetadataKeySyncVersion: recordVersionMs,
      ]
    )
  }

  /// Reads ONE page of menstrual-flow samples in `[start, end]` (Issues
  /// #217/#992) and returns the `{samples, nextCursor?}` map Dart's
  /// `decodeHealthReadResult` parses.
  ///
  /// **Paging.** An `HKAnchoredObjectQuery` seeded with the opaque `cursor`
  /// anchor returns at most `pageSize` samples and a new anchor. A full page
  /// means there may be more, so the new anchor is serialized into
  /// `nextCursor`; a short (or empty) page means the query is exhausted and
  /// no cursor is sent — the property the Dart loop relies on to terminate.
  /// Because the anchor advances HealthKit's own cursor, re-running the same
  /// request can never return the same page.
  ///
  /// **Echo prevention is mandatory here.** A sample lunarlog itself wrote
  /// (#193) comes back with `sourceRevision.source.bundleIdentifier` equal to
  /// this app's bundle id; re-importing it would duplicate every entry and
  /// loop the write and read directions, so any such sample is dropped before
  /// it reaches Dart. A page whose samples are ALL our own writes still
  /// carries its `nextCursor` (the page itself advanced), so Dart does not
  /// mistake it for exhaustion.
  ///
  /// The sample's own IANA zone rides `HKMetadataKeyTimeZone`; Dart resolves
  /// the civil date from it (day_boundary.dart's #180 contract) — never from
  /// the device's current zone. `HKMetadataKeyExternalUUID` is passed through
  /// for diagnostics. A sample whose value is not a known flow intensity is
  /// skipped rather than guessed.
  ///
  /// Issue #902: a sample with no `HKMetadataKeyTimeZone` (which is every
  /// menstruation sample logged by hand in Apple's own Health app) is not
  /// dropped. The device's UTC offset at the sample's instant is sent as
  /// `zoneOffsetSeconds` and flagged `zoneOffsetInferred`, so Dart places the
  /// row and reports it honestly as inferred from this phone's zone.
  static func readMenstrualFlowPage(
    start: Date,
    end: Date,
    cursor: String?,
    pageSize: Int
  ) async throws -> [String: Any] {
    let predicate = HKQuery.predicateForSamples(
      withStart: start, end: end, options: [])
    let page = try await anchoredQuery(
      ofType: menstrualFlowType,
      predicate: predicate,
      anchor: decodeAnchor(cursor),
      limit: pageSize)
    let ownBundleId = Bundle.main.bundleIdentifier
    var samples: [[String: Any]] = []
    for case let sample as HKCategorySample in page.samples {
      if let entry = samplePayload(sample, ownBundleId: ownBundleId) {
        samples.append(entry)
      }
    }
    var payload: [String: Any] = ["samples": samples]
    // A full page means HealthKit may have more waiting behind the new
    // anchor; a short page means the anchored query is exhausted.
    if page.samples.count >= pageSize,
      let next = cursorString(for: page.newAnchor)
    {
      payload["nextCursor"] = next
    }
    return payload
  }

  /// Reads Apple's computed cycle-deviation samples (Issue #799, read-only)
  /// in `[start, end]` for each requested `(wire, type)` pair and flattens
  /// each into the primitive map `health_channel_codec.dart`'s
  /// `decodeHealthDeviationReadResult` parses.
  ///
  /// **No echo prevention is needed here.** lunarlog never writes these
  /// types (App Review 5.1.3 — they are Apple's own derived data), so no
  /// sample can be this app's own. Apple's computed samples carry no
  /// `HKMetadataKeyTimeZone`, so each sample's zone is this device's UTC
  /// offset at the sample's instant, flagged `zoneOffsetInferred` — the
  /// same #902 contract the flow read uses, so Dart resolves and reports the
  /// civil date honestly.
  private static func readCycleDeviationSamples(
    types: [(wire: String, type: HKCategoryType)],
    start: Date,
    end: Date
  ) async throws -> [[String: Any]] {
    let predicate = HKQuery.predicateForSamples(
      withStart: start, end: end, options: [])
    var payload: [[String: Any]] = []
    for pair in types {
      let samples = try await querySamples(
        ofType: pair.type, predicate: predicate)
      for case let sample as HKCategorySample in samples {
        var entry: [String: Any] = [
          "kind": pair.wire,
          "recordId": sample.uuid.uuidString,
          "startMs": Int64(sample.startDate.timeIntervalSince1970 * 1000.0),
          "endMs": Int64(sample.endDate.timeIntervalSince1970 * 1000.0),
        ]
        if let tz = sample.metadata?[HKMetadataKeyTimeZone] as? String {
          entry["tzName"] = tz
        } else {
          entry["zoneOffsetSeconds"] =
            TimeZone.current.secondsFromGMT(for: sample.startDate)
          entry["zoneOffsetInferred"] = true
        }
        payload.append(entry)
      }
    }
    return payload
  }

  /// One `HKCategorySample`'s primitive map, or nil when it is this app's
  /// own write or carries no known flow intensity.
  private static func samplePayload(
    _ sample: HKCategorySample,
    ownBundleId: String?
  ) -> [String: Any]? {
    if let ownBundleId,
      sample.sourceRevision.source.bundleIdentifier == ownBundleId
    {
      return nil
    }
    guard let flow = MenstrualFlowRawValue(rawValue: sample.value) else {
      return nil
    }
    var entry: [String: Any] = [
      "recordId": sample.uuid.uuidString,
      "flow": flow.wire,
      "startMs": Int64(sample.startDate.timeIntervalSince1970 * 1000.0),
      "endMs": Int64(sample.endDate.timeIntervalSince1970 * 1000.0),
    ]
    if let tz = sample.metadata?[HKMetadataKeyTimeZone] as? String {
      entry["tzName"] = tz
    } else {
      // Issue #902: a menstruation sample entered by hand in Apple's own
      // Health app (Browse > Cycle Tracking > Menstruation > +) carries no
      // HKMetadataKeyTimeZone. Without a zone the Dart importer used to
      // drop every such sample, which made the feature useless for the
      // exact data it exists to bring over. Fall back to this device's UTC
      // offset at the sample's instant — the zone the phone was in at that
      // moment is the best available proxy — and flag it so Dart reports
      // the row as inferred (placed using this phone's time zone) rather
      // than as the sample's own recorded zone. Menstrual flow is a
      // whole-day category sample, so a wrong offset can only shift the
      // civil date by at most one day.
      entry["zoneOffsetSeconds"] =
        TimeZone.current.secondsFromGMT(for: sample.startDate)
      entry["zoneOffsetInferred"] = true
    }
    if let external = sample.metadata?[HKMetadataKeyExternalUUID] as? String {
      entry["externalUuid"] = external
    }
    return entry
  }

  /// Serializes an anchored query's anchor for the wire — the opaque
  /// `nextCursor` Dart passes back on the next page. `HKQueryAnchor`
  /// conforms to `NSSecureCoding`; the base64 string is opaque to Dart.
  static func cursorString(for anchor: HKQueryAnchor?) -> String? {
    guard let anchor else { return nil }
    guard
      let data = try? NSKeyedArchiver.archivedData(
        withRootObject: anchor, requiringSecureCoding: true)
    else { return nil }
    return encodeCursorData(data)
  }

  /// Base64 without line wrapping — separated from the anchor archive so the
  /// codec's round-trip is unit-testable without an `HKQueryAnchor`, which
  /// has no public initializer.
  static func encodeCursorData(_ data: Data) -> String {
    data.base64EncodedString()
  }

  /// The inverse of [encodeCursorData]; nil for nil/empty/malformed input.
  static func decodeCursorData(_ cursor: String?) -> Data? {
    guard let cursor, !cursor.isEmpty else { return nil }
    return Data(base64Encoded: cursor)
  }

  /// Decodes an opaque cursor back into the anchor the anchored query wants,
  /// or nil (start from the beginning) when the cursor is absent, empty, or
  /// not an archived anchor this build understands.
  static func decodeAnchor(_ cursor: String?) -> HKQueryAnchor? {
    guard let data = decodeCursorData(cursor) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: HKQueryAnchor.self, from: data)
  }

  /// Runs one `HKAnchoredObjectQuery` over `store` and awaits its page.
  /// HealthKit has no async overload, so the callback-based query is bridged
  /// through a `withCheckedThrowingContinuation`.
  private static func anchoredQuery(
    ofType sampleType: HKSampleType,
    predicate: NSPredicate?,
    anchor: HKQueryAnchor?,
    limit: Int
  ) async throws -> (samples: [HKSample], newAnchor: HKQueryAnchor?) {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Error>) in
      let query = HKAnchoredObjectQuery(
        type: sampleType,
        predicate: predicate,
        anchor: anchor,
        limit: limit
      ) { _, samples, _, newAnchor, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: (samples ?? [], newAnchor))
        }
      }
      store.execute(query)
    }
  }

  /// Runs an `HKSampleQuery` over `store` and awaits its results. HealthKit
  /// has no `HKHealthStore.samples(ofType:predicate:limit:)` async method, so
  /// the callback-based query is bridged through a
  /// `withCheckedThrowingContinuation`.
  private static func querySamples(
    ofType sampleType: HKSampleType,
    predicate: NSPredicate?
  ) async throws -> [HKSample] {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
      let query = HKSampleQuery(
        sampleType: sampleType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { _, samples, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: samples ?? [])
        }
      }
      store.execute(query)
    }
  }

  /// Deletes samples from `store` and awaits completion. HealthKit has no
  /// async `HKHealthStore.delete(_:)` overload, so the callback-based
  /// `delete(_:withCompletion:)` is bridged through a
  /// `withCheckedThrowingContinuation`.
  private static func delete(_ samples: [HKSample]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      store.delete(samples) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private static func save(_ samples: [HKSample], result: @escaping FlutterResult) {
    Task {
      do {
        _ = try await store.save(samples)
        result("allowed")
      } catch {
        result(
          FlutterError(
            code: "writeFailed",
            message: "save failed: \(error.localizedDescription)",
            details: nil))
      }
    }
  }
}
