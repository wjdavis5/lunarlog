package com.wjdavis5.lunarlog

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit

/**
 * The home-screen widget provider (issue #141).
 *
 * Renders the DISCREET state the app wrote into the shared
 * `HomeWidgetPreferences` store (the `home_widget` plugin's
 * SharedPreferences file): a cycle-day count, an optional days-until-next
 * estimate, and whether the quick-log affordance is offered. No profile
 * name, no date, no flow/symptom detail is ever rendered — the payload
 * itself (written by `WidgetStatePublisher` in the app) is already the
 * minimal set documented in
 * `lib/domain/widget/widget_cycle_state.dart`, and this provider renders
 * nothing beyond it. A widget draws on the launcher's own surface, outside
 * the app's `FLAG_SECURE`-protected windows, so discretion here is the
 * privacy control (issue #141's design constraint).
 *
 * Data-change driven: the app rewrites the store and broadcasts
 * APPWIDGET_UPDATE on its own signals (entry writes, prediction changes,
 * profile switches). The provider additionally rolls the day count forward
 * by whole civil days since `ll_widget_as_of` (so "Day 14" stays honest
 * across days when the app hasn't run), and the daily
 * `updatePeriodMillis` re-render keeps that roll moving without ever
 * touching the network or reading anything beyond the store.
 *
 * The two strings below pin the `home_widget` 0.8.1 plugin's internals by
 * contract — the plugin's own `HomeWidgetLaunchIntent`/`HomeWidgetPlugin`
 * use exactly these, and the plugin is pinned exactly in pubspec.yaml
 * because of it:
 * - [PREFERENCES]: `HomeWidgetPreferences` (HomeWidgetPlugin.PREFERENCES)
 * - [LAUNCH_ACTION]: `es.antonborri.home_widget.action.LAUNCH`
 *   (HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) — the plugin's
 *   cold-start/warm-tap plumbing only recognizes intents with this action.
 */
class LunarLogWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val views = buildViews(context, render(prefs))
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /** The rolled-forward render values (see the class doc). */
    private data class Render(
        val title: String,
        val subtitle: String?,
        val showQuickLog: Boolean,
        val profileId: String?,
    )

    private fun render(prefs: SharedPreferences): Render {
        val state = prefs.getString(KEY_STATE, null)
        val profileId = prefs.getString(KEY_PROFILE_ID, null)
        val canQuickLog = prefs.getString(KEY_CAN_QUICK_LOG, "0") == "1" && profileId != null

        // Any state other than a live cycle renders as an em dash — the
        // three "nothing to show" reasons are deliberately indistinguishable
        // (why predictions are suppressed is itself health context).
        if (state != STATE_DAY) {
            return Render(EM_DASH, null, canQuickLog, profileId)
        }

        val baseDay = prefs.getString(KEY_CYCLE_DAY, null)?.toIntOrNull()
            ?: return Render(EM_DASH, null, canQuickLog, profileId)
        val baseUntilNext = prefs.getString(KEY_DAYS_UNTIL_NEXT, null)?.toIntOrNull()
        val asOf = prefs.getString(KEY_AS_OF, null)?.let { parseDate(it) }
        val elapsed = if (asOf != null) daysBetween(asOf, LocalDate.now()) else 0L
        // Defensive: a device clock rollback renders the stored values
        // unchanged rather than counting backwards. The elapsed count is
        // narrowed to Int here — everything it feeds is an Int (the stored
        // cycle day and days-until estimate), and a realistic elapsed day
        // count is nowhere near Int range.
        val rolled = if (elapsed > 0) elapsed.toInt() else 0
        val day = baseDay + rolled
        // The countdown stops rendering once it would cross zero: the app
        // is the only authority for a fresh estimate.
        val untilNext = baseUntilNext?.let { it - rolled }?.takeIf { it > 0 }
        return Render("Day $day", untilNext?.let { approxDaysLabel(it) }, canQuickLog, profileId)
    }

    private fun buildViews(context: Context, render: Render): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.lunarlog_widget)
        views.setTextViewText(R.id.widget_title, render.title)
        if (render.subtitle != null) {
            views.setTextViewText(R.id.widget_subtitle, render.subtitle)
            views.setViewVisibility(R.id.widget_subtitle, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_subtitle, View.GONE)
        }
        // Quick-log opens the app with the intent URI (issue #141: the
        // widget never writes; the app stages the write and applies it
        // after the device-credential gate — the same shape as the
        // notification actions). The pending intent carries only the
        // profile id, never a name or health detail.
        if (render.showQuickLog && render.profileId != null) {
            views.setViewVisibility(R.id.widget_quick_log, View.VISIBLE)
            views.setOnClickPendingIntent(
                R.id.widget_quick_log,
                launchPendingIntent(context, quickLogUri(render.profileId)),
            )
            // With the button present the body still opens the app plainly,
            // so the two surfaces never do the same thing by accident.
            views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent(context, openUri()))
        } else {
            views.setViewVisibility(R.id.widget_quick_log, View.GONE)
            views.setOnClickPendingIntent(R.id.widget_root, launchPendingIntent(context, openUri()))
        }
        return views
    }

    private fun launchPendingIntent(context: Context, uri: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(LAUNCH_ACTION)
            .setData(Uri.parse(uri))
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    companion object {
        private const val PREFERENCES = "HomeWidgetPreferences"
        private const val LAUNCH_ACTION = "es.antonborri.home_widget.action.LAUNCH"

        // The payload keys — pinned to lib/domain/widget/widget_cycle_state.dart's
        // WidgetCycleStatePayload constants.
        private const val KEY_STATE = "ll_widget_state"
        private const val KEY_CYCLE_DAY = "ll_widget_cycle_day"
        private const val KEY_DAYS_UNTIL_NEXT = "ll_widget_days_until_next"
        private const val KEY_CAN_QUICK_LOG = "ll_widget_can_quick_log"
        private const val KEY_PROFILE_ID = "ll_widget_profile_id"
        private const val KEY_AS_OF = "ll_widget_as_of"
        private const val STATE_DAY = "day"
        private const val EM_DASH = "—"

        /** `lunarlog://widget-quick-log?homeWidget=1&profile=<id>` — the
         * URI `parseWidgetQuickLogUri` (Dart side) accepts. */
        fun quickLogUri(profileId: String): String =
            "lunarlog://widget-quick-log?homeWidget=1&profile=$profileId"

        /** `lunarlog://widget-open?homeWidget=1` — plain open, no action. */
        fun openUri(): String = "lunarlog://widget-open?homeWidget=1"

        /** The "≈N d" countdown label — a number plus a neutral suffix,
         * never a date. */
        fun approxDaysLabel(days: Int): String = "≈$days d"

        private fun parseDate(value: String): LocalDate? = try {
            LocalDate.parse(value)
        } catch (_: DateTimeParseException) {
            null
        }

        private fun daysBetween(from: LocalDate, to: LocalDate): Long =
            ChronoUnit.DAYS.between(from, to)
    }
}
