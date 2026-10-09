package com.wjdavis5.lunarlog

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import org.json.JSONException
import org.json.JSONObject

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
 * across days when the app hasn't run). What makes it draw on those days
 * (issue #1548) is an alarm it sets for just after the next local
 * midnight, and a redraw when the clock or the time zone is changed. The
 * daily `updatePeriodMillis` is only the backstop: it runs every 24 hours
 * from whenever the widget was placed, so on its own the widget showed
 * yesterday's number until that time of day came round. None of this
 * touches the network or reads anything beyond the store.
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
        // Every draw asks for the next one: the number changes at midnight.
        scheduleMidnightRefresh(context)
    }

    override fun onEnabled(context: Context) {
        scheduleMidnightRefresh(context)
    }

    override fun onDisabled(context: Context) {
        cancelMidnightRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // Midnight has passed, or the clock or the zone moved under
            // the count: draw again from the stored as-of date.
            ACTION_MIDNIGHT_REFRESH,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> redrawAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    /** Draws every placed widget again. With none placed, nothing is left
     * to keep fresh, so the alarm is dropped. */
    private fun redrawAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, LunarLogWidgetProvider::class.java),
        )
        if (ids.isEmpty()) {
            cancelMidnightRefresh(context)
            return
        }
        onUpdate(context, manager, ids)
    }

    private fun midnightRefreshIntent(context: Context): PendingIntent {
        val intent = Intent(context, LunarLogWidgetProvider::class.java)
            .setAction(ACTION_MIDNIGHT_REFRESH)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    /**
     * Asks for a redraw just after the next local midnight.
     *
     * `RTC`, not `RTC_WAKEUP`: the phone is not woken for it. An alarm
     * that comes due while the phone sleeps is delivered when it next
     * wakes, which is before anyone can look at a home screen. Inexact,
     * within a window, so it needs no exact-alarm permission.
     */
    private fun scheduleMidnightRefresh(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        alarms.setWindow(
            AlarmManager.RTC,
            WidgetMidnight.nextRefreshMillis(Instant.now(), ZoneId.systemDefault()),
            MIDNIGHT_WINDOW_MILLIS,
            midnightRefreshIntent(context),
        )
    }

    private fun cancelMidnightRefresh(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        alarms.cancel(midnightRefreshIntent(context))
    }

    /** The rolled-forward render values (see the class doc). */
    private data class Render(
        val title: String,
        val subtitle: String?,
        val showQuickLog: Boolean,
        val profileId: String?,
    )

    private fun render(prefs: SharedPreferences): Render {
        // Issue #1731: the app writes the whole payload as one JSON value
        // under the single envelope key, so this reads one entry — a
        // failed or interrupted app-side write can only leave the previous
        // payload, never half of a new one. A missing or malformed entry
        // (e.g. a container written by a build before this format) reads
        // as the neutral state.
        val payload = WidgetPayload.parse(
            prefs.getString(WidgetPayload.KEY, null),
        )
        val profileId = payload?.profileId
        val canQuickLog = (payload?.canQuickLog ?: "0") == "1" && profileId != null

        // Any state other than a live cycle renders as an em dash — the
        // three "nothing to show" reasons are deliberately indistinguishable
        // (why predictions are suppressed is itself health context).
        if (payload?.state != STATE_DAY) {
            return Render(EM_DASH, null, canQuickLog, profileId)
        }

        val baseDay = payload?.cycleDay?.toIntOrNull()
            ?: return Render(EM_DASH, null, canQuickLog, profileId)
        val baseUntilNext = payload?.daysUntilNext?.toIntOrNull()
        val asOf = payload?.asOf?.let { parseDate(it) }
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

        /** The provider's own "midnight has passed" broadcast (issue #1548). */
        private const val ACTION_MIDNIGHT_REFRESH =
            "com.wjdavis5.lunarlog.widget.MIDNIGHT_REFRESH"

        /** How late after midnight the system may deliver that broadcast. */
        private const val MIDNIGHT_WINDOW_MILLIS = 10 * 60 * 1000L

        // The payload's envelope key and field names live in WidgetPayload
        // below, pinned to lib/domain/widget/widget_cycle_state.dart's
        // WidgetCycleStatePayload constants.
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

/**
 * The widget payload (issue #141), parsed from the single JSON envelope the
 * app writes under [KEY] (issue #1731). Every field is nullable: a missing
 * or malformed entry reads as the neutral state, never an error.
 *
 * The field names are pinned to `lib/domain/widget/widget_cycle_state.dart`
 * (the documented boundary); [parse] is the only reader. Kept free of
 * Android types so the JVM unit tests can drive it directly.
 */
internal data class WidgetPayload(
    val state: String?,
    val cycleDay: String?,
    val daysUntilNext: String?,
    val canQuickLog: String?,
    val profileId: String?,
    val asOf: String?,
) {
    companion object {
        /** The single container entry the whole payload is written under. */
        const val KEY = "ll_widget_payload"

        const val FIELD_STATE = "ll_widget_state"
        const val FIELD_CYCLE_DAY = "ll_widget_cycle_day"
        const val FIELD_DAYS_UNTIL_NEXT = "ll_widget_days_until_next"
        const val FIELD_CAN_QUICK_LOG = "ll_widget_can_quick_log"
        const val FIELD_PROFILE_ID = "ll_widget_profile_id"
        const val FIELD_AS_OF = "ll_widget_as_of"

        /** Parses the envelope; null when it is absent or malformed. */
        fun parse(json: String?): WidgetPayload? {
            if (json.isNullOrBlank()) return null
            val payload = try {
                JSONObject(json)
            } catch (_: JSONException) {
                return null
            }
            return WidgetPayload(
                state = payload.fieldOrNull(FIELD_STATE),
                cycleDay = payload.fieldOrNull(FIELD_CYCLE_DAY),
                daysUntilNext = payload.fieldOrNull(FIELD_DAYS_UNTIL_NEXT),
                canQuickLog = payload.fieldOrNull(FIELD_CAN_QUICK_LOG),
                profileId = payload.fieldOrNull(FIELD_PROFILE_ID),
                asOf = payload.fieldOrNull(FIELD_AS_OF),
            )
        }

        /** A present field's string value; null when the field is absent. */
        private fun JSONObject.fieldOrNull(name: String): String? =
            if (has(name)) optString(name) else null
    }
}
