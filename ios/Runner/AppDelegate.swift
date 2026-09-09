import Flutter
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
  }

  /// Best effort, matching the Dart caller's own best-effort contract
  /// (`protectDatabaseFile` in `lib/startup/startup_native.dart`): every
  /// step below is independent and a failure in one never stops the others
  /// or throws back across the channel.
  private static func protectDatabaseFile(atPath path: String) {
    let fileManager = FileManager.default
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
