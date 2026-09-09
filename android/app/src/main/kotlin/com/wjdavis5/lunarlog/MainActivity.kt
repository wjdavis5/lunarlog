package com.wjdavis5.lunarlog

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth's
// BiometricPrompt on Android; plain FlutterActivity throws at runtime when
// the device-credential prompt is shown.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // U7 snapshot suppression: sets FLAG_SECURE at window level so the
        // app-switcher snapshot and screenshots show only a blank surface.
        // The Dart side treats this as best effort (lib/app_lifecycle.dart);
        // the opaque lifecycle cover is the cross-platform baseline.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lunarlog/privacy"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFlagSecure" -> {
                    val enable = call.arguments as? Boolean ?: true
                    if (enable) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Issue #173: the Android half of the "lunarlog/health" channel —
        // the Health Connect adapter, mirroring AppDelegate.swift's iOS
        // registration of the same channel name. Constructed here (during
        // onCreate) so its permission launcher is registered before the
        // activity reaches STARTED; see HealthConnectAdapter.kt for the
        // native guard mirror every write passes through before any
        // Health Connect API is touched.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lunarlog/health"
        ).setMethodCallHandler(HealthConnectAdapter(this)::handle)
    }
}
