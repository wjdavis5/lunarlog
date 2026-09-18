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
    // from iCloud/device backup and marks them NSFileProtectionComplete.
    // See lib/startup/startup_native.dart's protectDatabaseFile() doc
    // comment for why Complete (not CompleteUntilFirstUserAuthentication)
    // is the right class here.
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
    // directory's NSFileProtectionComplete class, and
    // NSURLIsExcludedFromBackupKey on a directory excludes its current
    // *and future* contents — so a sqlite `-journal` sidecar created
    // after this method has already run once (this call only iterates
    // siblings that already exist below) is covered anyway.
    if fileManager.fileExists(atPath: directoryPath) {
      do {
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.complete],
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

      // NSFileProtectionComplete: unreadable while the device is locked.
      do {
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.complete],
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

  /// The native mirror of HealthSyncBinding._evaluate. Returns the same
  /// wire strings the Dart codec decodes ("allowed" or a HealthSyncCheck
  /// deny name). `boundProfileId` comes from UserDefaults for
  /// write/authorization calls, and from the *proposed* id for `bind`
  /// (mirroring canBind's proposed-binding semantics).
  static func guardDecision(boundProfileId: String?, _ g: GuardArgs) -> String {
    guard let boundProfileId else { return "noBinding" }
    if g.profileId != boundProfileId { return "profileNotBound" }

    let isOwner =
      g.signedInUserId != nil && g.ownerUserId != nil
      && g.signedInUserId == g.ownerUserId

    if isMinorNow(isMinor: g.isMinor, birthYear: g.birthYear) {
      // Issue #619, LLA-031: every leg of
      // HealthSyncBinding._minorTransferExceptionHolds — a transfer
      // happened, the caller is the resolved owner, AND it named exactly
      // the signed-in account — not merely "some transfer happened and
      // the caller happens to pass isOwner".
      let transferredToOwnAccount =
        g.transferredAtMs != nil && isOwner
        && g.transferredToUserId != nil
        && g.transferredToUserId == g.signedInUserId
      if !g.minorBindingAllowed || !transferredToOwnAccount {
        return "minorRequiresOwnershipTransfer"
      }
      return "allowed"
    }
    if !isOwner { return "notOwner" }
    return "allowed"
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
      let toShare: Set<HKSampleType> = [
        menstrualFlowType,
        intermenstrualBleedingType,
      ]
      // Issue #217: the read set is no longer empty. It carries only the
      // menstrual-flow type the user-initiated import reads; the four
      // Apple-computed cycle-deviation types are deliberately NOT requested
      // and are never read or written. The one system sheet now covers both
      // the write types and the read type.
      let toRead: Set<HKObjectType> = [menstrualFlowType]
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

    case "deleteRecords":
      // Issue #186 tombstone propagation: delete the samples whose
      // HKMetadataKeyExternalUUID is one of the supplied lunarlog record
      // ids. HealthKit can only delete samples the app itself saved, so we
      // first query the two types this app writes by their external-UUID
      // metadata, then delete exactly those — a record we never wrote (or a
      // per-type mismatch) is simply absent from the query result. Behind
      // the same guard as every write (a deletion is a health-API touch).
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
          // Query both types this app writes by their external-UUID
          // metadata, then delete exactly those samples. HealthKit's
          // delete(_:) can only remove samples the app itself saved, so a
          // record we never wrote is simply absent from the query result.
          // `HKHealthStore` has no `samples(ofType:predicate:limit:)` method
          // and no async `delete` overload, so both calls below go through
          // the standard callback-based APIs wrapped in continuations
          // (`HKSampleQuery` + `store.execute(_:)`, and
          // `store.delete(_:withCompletion:)`).
          let samples = try await querySamples(
            ofType: menstrualFlowType,
            predicate: predicate)
          let intermenstrual = try await querySamples(
            ofType: intermenstrualBleedingType,
            predicate: predicate)
          var toDelete = samples
          toDelete.append(contentsOf: intermenstrual)
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

    case "readMenstrualFlow":
      // Issue #217 (#781's read decision): the user-initiated menstrual-flow
      // import. Guarded identically to a write (the device-binding decision
      // is the same), then a bounded sample query. Success returns an array
      // of primitive maps (StandardMessageCodec), not a result string;
      // authorization opacity means a denied read arrives here as an empty
      // array, never an error.
      guard let g = args.flatMap(GuardArgs.init) else {
        badArgs(result, "readMenstrualFlow requires guard args")
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
        badArgs(result, "readMenstrualFlow requires startMs/endMs")
        return
      }
      Task {
        do {
          let payload = try await readMenstrualFlowSamples(
            start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
            end: Date(timeIntervalSince1970: Double(endMs) / 1000.0))
          result(payload)
        } catch {
          result(
            FlutterError(
              code: "readFailed",
              message: "readMenstrualFlow failed: \(error.localizedDescription)",
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

  /// Reads menstrual-flow samples in `[start, end]` (Issue #217) and flattens
  /// each into the primitive map `health_channel_codec.dart`'s
  /// `decodeHealthReadResult` parses.
  ///
  /// **Echo prevention is mandatory here.** A sample lunarlog itself wrote
  /// (#193) comes back with `sourceRevision.source.bundleIdentifier` equal to
  /// this app's bundle id; re-importing it would duplicate every entry and
  /// loop the write and read directions, so any such sample is dropped before
  /// it reaches Dart.
  ///
  /// The sample's own IANA zone rides `HKMetadataKeyTimeZone`; Dart resolves
  /// the civil date from it (day_boundary.dart's #180 contract) — never from
  /// the device's current zone. `HKMetadataKeyExternalUUID` is passed through
  /// for diagnostics. A sample whose value is not a known flow intensity is
  /// skipped rather than guessed.
  private static func readMenstrualFlowSamples(
    start: Date,
    end: Date
  ) async throws -> [[String: Any]] {
    let predicate = HKQuery.predicateForSamples(
      withStart: start, end: end, options: [])
    let samples = try await querySamples(
      ofType: menstrualFlowType, predicate: predicate)
    let ownBundleId = Bundle.main.bundleIdentifier
    var payload: [[String: Any]] = []
    for case let sample as HKCategorySample in samples {
      if let ownBundleId,
        sample.sourceRevision.source.bundleIdentifier == ownBundleId
      {
        continue
      }
      guard let flow = MenstrualFlowRawValue(rawValue: sample.value) else {
        continue
      }
      var entry: [String: Any] = [
        "recordId": sample.uuid.uuidString,
        "flow": flow.wire,
        "startMs": Int64(sample.startDate.timeIntervalSince1970 * 1000.0),
        "endMs": Int64(sample.endDate.timeIntervalSince1970 * 1000.0),
      ]
      if let tz = sample.metadata?[HKMetadataKeyTimeZone] as? String {
        entry["tzName"] = tz
      }
      if let external = sample.metadata?[HKMetadataKeyExternalUUID] as? String {
        entry["externalUuid"] = external
      }
      payload.append(entry)
    }
    return payload
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
