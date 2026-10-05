package com.wjdavis5.lunarlog

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Issue #993: the Android half of the background import — a periodic
 * WorkManager job whose only job is to wake the *running* app's Dart side
 * so the [HealthBackgroundImportCoordinator] (lib/data/health/
 * health_background_import_service.dart) can run one prompt-free pass of
 * the same import the Settings tap runs.
 *
 * **The worker never touches health data.** It reads no Health Connect
 * record and performs no merge — the changes-API pull, the #153
 * device-binding guard, the read-side permission probe (#1491; it was the
 * #959 write-side one before), and the
 * never-overwrite merge all live in the Dart pipeline, unchanged. The
 * worker's whole decision surface is: is a profile bound (the same
 * SharedPreferences mirror `HealthConnectAdapter` stores), is the
 * background-read permission usable where the platform gates background
 * reads on it (issue #1211, asked through
 * [HealthConnectAdapter.backgroundReadRefused] so the worker itself still
 * holds no Health Connect types), and is the main Flutter engine alive
 * (see [HealthBackgroundImportBridge])?
 *
 * **Why "engine alive" is the honest contract.** A WorkManager tick that
 * lands while the activity is merely backgrounded finds the engine (and
 * the Dart isolate) still running — that is the dominant case, and the
 * pull is cheap because the adapter's changes token makes every pass
 * incremental. After the process has been killed, WorkManager restarts it
 * *without* an activity or engine; there is no Dart side to hand the pass
 * to, so the tick reports success and does nothing — the next app start
 * runs the catch-up import, exactly as the pre-#993 behavior did. Spinning
 * up a headless FlutterEngine with a full repository bootstrap to cover
 * that case was deliberately out of scope for this issue.
 */
class HealthBackgroundImportWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val prefs: SharedPreferences =
            applicationContext.getSharedPreferences(
                HealthConnectAdapter.PREFS_FILE, Context.MODE_PRIVATE)
        // The same binding mirror every write and read is checked against.
        // No bound profile → nothing to import; a future unbind also cancels
        // the schedule, so this is the belt to the cancel's suspenders.
        if (prefs.getString(HealthConnectAdapter.BOUND_PROFILE_KEY, null) == null) {
            return Result.success()
        }
        // Issue #1211: where Health Connect offers the background-read
        // feature but READ_HEALTH_DATA_IN_BACKGROUND is not granted (never
        // asked, declined, or revoked), Health Connect refuses every read
        // this trigger could wake — so the tick ends here, before Dart is
        // woken for a pass that cannot read. Every can't-tell case (feature
        // absent, SDK gone, query failure) answers false inside the helper
        // and the tick runs on: the Dart side's own probe still gates each
        // pass on the read permissions it needs (issue #1491 — the record
        // reads, where this check is the background-read permission).
        if (HealthConnectAdapter.backgroundReadRefused(applicationContext)) {
            return Result.success()
        }
        val messenger = HealthBackgroundImportBridge.mainEngineMessenger
            ?: return Result.success()
        // Post to the main thread (a MethodChannel invocation is not
        // thread-safe from a worker's IO thread) and wait at most [ACK_TIMEOUT_MS]
        // for the Dart coordinator's ack. The Dart side acks immediately and
        // runs the pass on its own, so this is bounded by a round trip, never
        // by a full import; a timeout or a not-implemented reply is still a
        // success — the next tick (and the next app start) retries by
        // construction.
        withTimeoutOrNull(ACK_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                Handler(Looper.getMainLooper()).post {
                    try {
                        MethodChannel(messenger, HealthConnectAdapter.CHANNEL_NAME)
                            .invokeMethod(
                                TRIGGER_METHOD, null,
                                object : MethodChannel.Result {
                                    override fun success(result: Any?) =
                                        continuation.resume(Unit)

                                    override fun error(
                                        errorCode: String,
                                        errorMessage: String?,
                                        errorDetails: Any?,
                                    ) = continuation.resume(Unit)

                                    override fun notImplemented() =
                                        continuation.resume(Unit)
                                })
                    } catch (_: Exception) {
                        // The engine may be mid-teardown; treat as no-op.
                        continuation.resume(Unit)
                    }
                }
            }
        }
        return Result.success()
    }

    companion object {
        /** The native→Dart push the Dart coordinator's listener answers. */
        const val TRIGGER_METHOD = "onBackgroundImportTriggered"

        /** How long the worker waits for Dart's ack before giving up. */
        const val ACK_TIMEOUT_MS = 10_000L

        /** The WorkManager unique-work name (one periodic schedule per app). */
        const val UNIQUE_WORK_NAME = "lunarlog-health-background-import"

        /** The periodic cadence. WorkManager's floor is 15 minutes; an hour
         * keeps background passes rare (each is incremental) while a device
         * sitting on a backgrounded-but-alive app stays current. The OS
         * batches periodic work anyway — this is an upper bound, not a
         * promise. */
        val PERIOD: Long = 1
        val PERIOD_UNIT: TimeUnit = TimeUnit.HOURS
    }
}

/**
 * Scheduling and the live-engine bridge for [HealthBackgroundImportWorker].
 * All entry points are best-effort: a WorkManager failure never fails the
 * call that scheduled (or cancelled) it.
 */
object HealthBackgroundImportScheduler {

    /**
     * Enqueues the unique periodic work. `KEEP` policy: a re-schedule (every
     * adapter construction and every successful bind) never resets the
     * period's clock; only the first enqueue starts it.
     */
    fun schedule(context: Context) {
        try {
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    HealthBackgroundImportWorker.UNIQUE_WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    PeriodicWorkRequestBuilder<HealthBackgroundImportWorker>(
                            HealthBackgroundImportWorker.PERIOD,
                            HealthBackgroundImportWorker.PERIOD_UNIT)
                        .build())
        } catch (_: Exception) {
            // WorkManager unavailable (instrumentation test harness, exotic
            // OEM build): background passes simply never fire on this device.
        }
    }

    /** Cancels the schedule (the adapter's `unbind`). */
    fun cancel(context: Context) {
        try {
            WorkManager.getInstance(context)
                .cancelUniqueWork(HealthBackgroundImportWorker.UNIQUE_WORK_NAME)
        } catch (_: Exception) {
            // Same best-effort contract as [schedule].
        }
    }
}

/**
 * The worker→engine bridge: the messenger of the *main* Flutter engine,
 * captured in `MainActivity.configureFlutterEngine` and cleared in
 * `MainActivity.onDestroy`. Nullable by design — a WorkManager tick that
 * restarts the process without an activity finds null and no-ops (see the
 * worker's class doc).
 */
object HealthBackgroundImportBridge {
    @Volatile var mainEngineMessenger: BinaryMessenger? = null

    /** Wired from MainActivity; kept as an explicit function so the capture
     * site reads as a decision, not an assignment to someone else's field. */
    fun attach(flutterEngine: FlutterEngine) {
        mainEngineMessenger = flutterEngine.dartExecutor.binaryMessenger
    }

    fun detach() {
        mainEngineMessenger = null
    }
}
