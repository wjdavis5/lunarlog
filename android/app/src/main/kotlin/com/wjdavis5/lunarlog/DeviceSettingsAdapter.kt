package com.wjdavis5.lunarlog

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Issue #1939: the Android half of the "lunarlog/device_settings" channel
// (the "lunarlog/health"/"lunarlog/privacy" first-party-channel precedent,
// registered from MainActivity beside the health adapter). The lock
// screen's "Open device settings" affordance (issue #534, shown for
// GateDenialReason.noCredentialEnrolled) used to reach this through
// url_launcher with an `intent://#Intent;action=...;end` URI — a no-op on
// real Android, verified on a Pixel 8 Pro / Android 17 during the #600
// device-test pass (2026-11-20): url_launcher_android 6.3.33's
// `UrlLauncher.java` builds `new Intent(ACTION_VIEW).setData(Uri.parse(url))`
// — the intent URI becomes VIEW *data* (no `Intent.parseUri` anywhere in
// the plugin), and nothing on stock Android VIEW-handles `intent:`-scheme
// data ("unable to resolve"). The bare action resolves fine, so the fix is
// to startActivity() a real action intent, which only a first-party
// channel can do.
//
// One method: `openSecuritySettings` -> bool. `true` means something
// opened — Security settings directly, or (see below) the fallback.
// `false` means neither attempt found a handler. The Dart side treats
// `false` and a channel throw identically (breadcrumb + Sentry); the
// pre-#1939 bug was that a failed launch reported as a `false` *return*
// never reached any failure path at all.
class DeviceSettingsAdapter(private val activity: Activity) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_OPEN_SECURITY_SETTINGS -> {
                try {
                    openSecuritySettings(result)
                } catch (error: Exception) {
                    // Anything ActivityNotFoundException didn't already
                    // route below is a genuinely unexpected failure —
                    // surface it to Dart as a channel error so its throw
                    // path runs, never a crash on the platform thread.
                    result.error("device_settings_error", error.toString(), null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun openSecuritySettings(result: MethodChannel.Result) {
        try {
            activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            result.success(true)
        } catch (securitySettingsMissing: ActivityNotFoundException) {
            // Some OEM skins don't expose SECURITY_SETTINGS under this
            // exact action. ActivityNotFoundException is the *only*
            // fallback trigger — it means "no handler for the action",
            // which the App-info page always satisfies; anything else is
            // a real error and escapes to [handle]'s error path. The
            // fallback opens this app's own "App info" page, which always
            // exists and is one tap from Security settings on every skin.
            // The package comes from context.packageName (the Dart side
            // no longer builds this intent, so package_info_plus dropped
            // out of device_settings_launcher.dart entirely).
            openAppDetails(result)
        }
    }

    private fun openAppDetails(result: MethodChannel.Result) {
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", activity.packageName, null),
                )
            )
            result.success(true)
        } catch (appDetailsMissing: ActivityNotFoundException) {
            result.success(false)
        }
    }

    companion object {
        const val CHANNEL_NAME = "lunarlog/device_settings"
        const val METHOD_OPEN_SECURITY_SETTINGS = "openSecuritySettings"
    }
}
