package com.wjdavis5.lunarlog

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Issue #166: the rationale screen Health Connect requires before (and
 * instead of) a plain runtime permission dialog. Health Connect can launch
 * this directly -- via [android.content.Intent] action
 * `androidx.health.connect.action.SHOW_PERMISSIONS_RATIONALE` from its own
 * permission-grant flow, or via the `.PermissionsRationaleActivityAlias`
 * declared in AndroidManifest.xml (action `VIEW_PERMISSION_USAGE`, category
 * `HEALTH_PERMISSIONS`) from the system Settings "why does this app have
 * access" surface on Android 14+ -- without first starting the Flutter
 * engine, so this is a plain [Activity], not `FlutterActivity`.
 *
 * Deliberately static and minimal: no health data is read here (nothing in
 * this repo calls Health Connect yet -- see AppConfig.hasHealthSync), no
 * network request is made, and the content below is a plain-text mirror of
 * the privacy summary already shown in-app by
 * `SettingsScreen._showPrivacyPolicy` plus the one-profile-at-a-time
 * statement product assumption #3 (issue #153) requires callers to surface.
 * If that in-app summary's wording changes, update this copy to match --
 * there is no shared source between the two today because one is Dart and
 * one is a platform activity Health Connect can invoke standalone.
 */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val padding = (24 * resources.displayMetrics.density).toInt()

        val title = TextView(this).apply {
            text = "LunarLog & Health Connect"
            textSize = 20f
            setTypeface(typeface, Typeface.BOLD)
        }

        val body = TextView(this).apply {
            textSize = 15f
            setPadding(0, padding, 0, padding)
            text = "LunarLog is a privacy-first, local-first cycle tracker.\n\n" +
                "• Health Connect data (menstruation dates and flow, and " +
                "spotting logged between periods) is only ever read or " +
                "written for the one profile explicitly bound as this " +
                "device's owner -- never for another family member's " +
                "profile, even one this device manages as a guardian.\n\n" +
                "• Local & Encrypted: all cycle data is protected on your " +
                "device by the operating system's own at-rest protection, " +
                "behind biometric or passcode authentication.\n\n" +
                "• Optional Sync: cloud accounts (Supabase) are optional. " +
                "No data is uploaded without your explicit consent, and " +
                "enabling Health Connect sync does not enable cloud sync or " +
                "vice versa.\n\n" +
                "• Zero Ads & Tracking: we do not track you, sell data, or " +
                "use ads. Crash reports strip all health and personal " +
                "details on-device before they ever leave it.\n\n" +
                "You can grant, deny, or later revoke any of these permissions " +
                "individually in Health Connect's own settings; LunarLog " +
                "disables only the affected feature when a permission is " +
                "denied or revoked."
        }

        val privacyPolicyButton = Button(this).apply {
            text = "View full privacy policy"
            setOnClickListener {
                startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse(
                            "https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md"
                        )
                    )
                )
            }
        }

        val closeButton = Button(this).apply {
            text = "Close"
            setOnClickListener { finish() }
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            addView(title)
            addView(body)
            addView(privacyPolicyButton)
            addView(closeButton)
        }

        val scroll = ScrollView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            addView(content)
        }

        setContentView(scroll)
    }
}
