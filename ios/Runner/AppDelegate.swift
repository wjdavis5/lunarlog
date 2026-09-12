import Flutter
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
  /// (`unspecified` = 0, `light` = 1, `medium` = 2, `heavy` = 3 — issue
  /// #193's A3-14). Declared as bare raw values, not the SDK symbols,
  /// so this compiles against both older and newer SDKs with no
  /// availability branch and no deprecation warning; swapping to
  /// `HKCategoryValueVaginalBleeding.light.rawValue` (iOS 18+ symbol)
  /// yields the same integers.
  enum MenstrualFlowRawValue: Int {
    case unspecified = 0
    case light = 1
    case medium = 2
    case heavy = 3

    init?(wire: String) {
      switch wire {
      case "unspecified": self = .unspecified
      case "light": self = .light
      case "medium": self = .medium
      case "heavy": self = .heavy
      default: return nil
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
      let transferredToOwnAccount = g.transferredAtMs != nil && isOwner
      if !g.minorBindingAllowed || !transferredToOwnAccount {
        return "minorRequiresOwnershipTransfer"
      }
      return "allowed"
    }
    if !isOwner { return "notOwner" }
    return "allowed"
  }

  /// Native mirror of HealthSyncBinding._isMinorNow: flagged directly,
  /// or under 18 by birth year (a coarse same-calendar-year comparison —
  /// birthYear carries no month/day).
  static func isMinorNow(isMinor: Bool, birthYear: Int?) -> Bool {
    if isMinor { return true }
    guard let birthYear else { return false }
    let nowYear = Calendar(identifier: .gregorian).component(.year, from: Date())
    return nowYear - birthYear < 18
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
      Task {
        do {
          // iOS's sheet reports completion, not the user's choice —
          // denial only surfaces on the first actual write.
          _ = try await store.requestAuthorization(
            toShare: toShare, read: [])  // async overload takes a non-optional Set; empty = read nothing
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
        let recordId = args?["recordId"] as? String
      else {
        badArgs(result, "writeMenstrualFlow requires startMs/endMs/flow/cycleStart/recordId")
        return
      }
      // #193: HKMetadataKeyMenstrualCycleStart is required on every
      // menstrualFlow sample — true on the first day of a cycle, false
      // otherwise (sourced on the Dart side from episodes.dart).
      // #186: HKMetadataKeyExternalUUID carries lunarlog's own record id
      // (the day_entry ULID) so a future re-import can recognise this
      // sample as our own write (the backup loop-breaker) and a tombstone
      // can locate and delete exactly it.
      let sample = HKCategorySample(
        type: menstrualFlowType,
        value: flow.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [
          HKMetadataKeyMenstrualCycleStart: cycleStartNumber,
          HKMetadataKeyExternalUUID: recordId,
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
        let recordId = args?["recordId"] as? String
      else {
        badArgs(result, "writeIntermenstrualBleeding requires startMs/endMs/recordId")
        return
      }
      // No intensity on this type: HKCategoryValueNotApplicable — the
      // sample's existence is the datum (#193/A3-4).
      // #186: HKMetadataKeyExternalUUID, as for writeMenstrualFlow.
      let sample = HKCategorySample(
        type: intermenstrualBleedingType,
        value: HKCategoryValue.notApplicable.rawValue,
        start: Date(timeIntervalSince1970: Double(startMs) / 1000.0),
        end: Date(timeIntervalSince1970: Double(endMs) / 1000.0),
        metadata: [HKMetadataKeyExternalUUID: recordId]
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

  /// Runs an `HKSampleQuery` over `store` and awaits its results. HealthKit
  /// has no `HKHealthStore.samples(ofType:predicate:limit:)` async method, so
  /// the callback-based query is bridged through a
  /// `withCheckedThrowingContinuation`.
  private static func querySamples(
    ofType sampleType: HKSampleType,
    predicate: NSPredicate?
  ) async throws -> [HKSample] {
    try await withCheckedThrowingContinuation { continuation in
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
    try await withCheckedThrowingContinuation { continuation in
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
