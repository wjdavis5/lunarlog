package com.wjdavis5.lunarlog

import android.content.Context
import android.content.SharedPreferences
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.IntermenstrualBleedingRecord
import androidx.health.connect.client.records.MenstruationFlowRecord
import androidx.health.connect.client.records.Record
// Aliased because a plain `Metadata` import resolves to the compiler's
// own kotlin.Metadata annotation in constructor-argument position here.
import androidx.health.connect.client.records.metadata.Metadata as HcMetadata
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset
import java.util.Calendar

// Issue #173: the Android half of the "lunarlog/health" channel — a
// first-party adapter over HealthConnectClient, chosen over the pub.dev
// `health` package (which covers MENSTRUATION_FLOW only). The full
// (a)-vs-(b) decision is recorded in
// lib/domain/health/health_platform.dart's library doc; the wire
// protocol both sides speak is defined in
// lib/data/health/health_channel_codec.dart (keys, method names, and
// result strings there are the single source of truth — keep this file
// in sync with it, and with the Swift half in AppDelegate.swift's
// HealthKitChannelHandler).
//
// The load-bearing property: **the #153 guard (profile↔device-owner
// binding + owner-not-guardian) is re-evaluated HERE, from this
// device's own SharedPreferences copy of the binding, before ANY health
// API is touched** — not merely trusted from the Dart side. The
// predicate below is a deliberate native mirror of
// HealthSyncBinding._evaluate (lib/domain/health/
// health_sync_binding.dart): the two sides cannot share code, and the
// duplication is the safety property issue #173 demands. Fail-closed on
// disagreement: a write only proceeds when BOTH the Dart-side settings
// store and this SharedPreferences copy name the written profile.
//
// Store-compliance rule (issue #254, mirroring Apple's 5.1.3 and Play's
// inaccurate-data prohibition alike): this adapter writes only
// user-logged or imported data — a flow level, a spotting marker, and
// the period-record boundaries derived from that same logged bleed
// history — never a predicted or derived cycle value (no next-period
// prediction, no fertile-window or ovulation estimate). The written
// rule lives in lib/data/health/health_channel.dart's library doc and
// both halves of the channel are bound by it.
//
// The stored value is a random profile ULID, not health data.
class HealthConnectAdapter(context: Context) {

    private val contextApp: Context = context.applicationContext

    private val prefs: SharedPreferences =
        contextApp.getSharedPreferences("lunarlog_health", Context.MODE_PRIVATE)

    // Health Connect's permission sheet is an ActivityResult contract, so
    // the launcher must be registered before the activity reaches STARTED
    // — constructing this adapter from configureFlutterEngine (which runs
    // during onCreate) satisfies that. The sheet's callback completes
    // whichever channel result prompted it.
    private var pendingAuthResult: MethodChannel.Result? = null
    private val requestPermissions =
        (context as? ComponentActivity)?.registerForActivityResult(
            PermissionController.createRequestPermissionResultContract()
        ) { granted ->
            val pending = pendingAuthResult
            pendingAuthResult = null
            pending?.success(
                if (granted.isNotEmpty()) "allowed" else "permissionDenied"
            )
        }

    // connect-client 1.1.0's permission model: permissions are plain
    // strings (HealthPermission.getWritePermission(KClass)), and the
    // request contract takes Set<String> — the old alpha-era
    // createWritePermission(KClass)-returns-Permission API is gone.
    private val writePermissions = setOf(
        HealthPermission.getWritePermission(MenstruationFlowRecord::class),
        HealthPermission.getWritePermission(IntermenstrualBleedingRecord::class),
    )

    // The guard-args half of every guarded call (mirrors
    // encodeGuardArgs in health_channel_codec.dart). StandardMessageCodec
    // delivers integers as Int or Long by magnitude, so every numeric
    // field is read through [number] — never `as Int`/`as Long` alone.
    private class GuardArgs(
        val profileId: String,
        val signedInUserId: String?,
        val ownerUserId: String?,
        val isMinor: Boolean,
        val birthYear: Int?,
        val transferredAtMs: Long?,
        val minorBindingAllowed: Boolean,
    ) {
        companion object {
            fun parse(args: Map<*, *>?): GuardArgs? {
                val profileId = args?.get("profileId") as? String ?: return null
                val isMinor = args["isMinor"] as? Boolean ?: return null
                val minorBindingAllowed =
                    args["minorBindingAllowed"] as? Boolean ?: return null
                return GuardArgs(
                    profileId = profileId,
                    signedInUserId = args["signedInUserId"] as? String,
                    ownerUserId = args["ownerUserId"] as? String,
                    isMinor = isMinor,
                    birthYear = number(args, "birthYear")?.toInt(),
                    transferredAtMs = number(args, "transferredAtMs"),
                    minorBindingAllowed = minorBindingAllowed,
                )
            }

            fun number(args: Map<*, *>?, key: String): Long? =
                (args?.get(key) as? Number)?.toLong()
        }
    }

    private val storedBoundProfileId: String?
        get() = prefs.getString(BOUND_PROFILE_KEY, null)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            // The one deliberately unguarded method: a static capability
            // probe — no health store access, no user data.
            "isAvailable" -> {
                result.success(isAvailable())
            }

            "bind" -> {
                val g = GuardArgs.parse(args)
                    ?: return result.error("bad_args", "bind requires guard args", null)
                // Proposed-binding semantics (mirrors canBind): evaluate
                // against the id being bound, store only if every other
                // check passes.
                val decision = guardDecision(g.profileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                } else {
                    prefs.edit().putString(BOUND_PROFILE_KEY, g.profileId).apply()
                    result.success("allowed")
                }
            }

            "unbind" -> {
                prefs.edit().remove(BOUND_PROFILE_KEY).apply()
                result.success(null)
            }

            "requestWriteAuthorization" -> {
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "requestWriteAuthorization requires guard args", null)
                val decision = guardDecision(storedBoundProfileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                    return
                }
                if (!isAvailable()) {
                    result.success("unavailable")
                    return
                }
                // One prompt at a time: a second request while the sheet is
                // up fails the older result rather than letting two
                // callbacks race one pending slot.
                pendingAuthResult?.error(
                    "writeFailed", "another authorization prompt is in flight", null)
                pendingAuthResult = result
                val launcher = requestPermissions
                if (launcher == null) {
                    pendingAuthResult = null
                    result.error(
                        "writeFailed", "no activity to host the permission prompt", null)
                } else {
                    launcher.launch(writePermissions)
                }
            }

            "writeMenstrualFlow" -> {
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeMenstrualFlow requires guard args", null)
                val decision = guardDecision(storedBoundProfileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                    return
                }
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                val instantMs = GuardArgs.number(args, "instantMs")
                val zoneOffsetMs = GuardArgs.number(args, "zoneOffsetMs")
                val flowWire = args?.get("flow") as? String
                val flow = when (flowWire) {
                    "unspecified" -> MenstruationFlowRecord.FLOW_UNKNOWN
                    "light" -> MenstruationFlowRecord.FLOW_LIGHT
                    "medium" -> MenstruationFlowRecord.FLOW_MEDIUM
                    "heavy" -> MenstruationFlowRecord.FLOW_HEAVY
                    else -> null
                }
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (instantMs == null || zoneOffsetMs == null || flow == null ||
                    recordId == null || recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeMenstrualFlow requires instantMs/zoneOffsetMs/flow/recordId/recordVersionMs",
                        null)
                }
                // Health Connect's menstruation record is instantaneous:
                // `time` at local midnight plus the entry's own
                // zoneOffset (from the #180 contract -- never the device's
                // current zone).
                // #186 sync mechanics: the lunarlog record id becomes
                // clientRecordId and the row's updatedAt-ms becomes
                // clientRecordVersion -- a higher version replaces on
                // re-write (idempotent writes) and a tombstone can delete
                // by clientRecordId.
                val record = MenstruationFlowRecord(
                    time = Instant.ofEpochMilli(instantMs),
                    zoneOffset = ZoneOffset.ofTotalSeconds((zoneOffsetMs / 1000).toInt()),
                    flow = flow,
                    // User-logged cycle data (issue #254: never a derived
                    // value). Health Connect stamps dataOrigin itself from
                    // the calling package. The Metadata constructor is
                    // internal in connect-client 1.1.0, so the public
                    // companion factory is used instead — it supplies the
                    // manual-entry recording method itself; this app writes
                    // only manually-entered data.
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                )
                insert(client, listOf(record), result)
            }

            "writeIntermenstrualBleeding" -> {
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeIntermenstrualBleeding requires guard args", null)
                val decision = guardDecision(storedBoundProfileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                    return
                }
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                val instantMs = GuardArgs.number(args, "instantMs")
                val zoneOffsetMs = GuardArgs.number(args, "zoneOffsetMs")
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (instantMs == null || zoneOffsetMs == null ||
                    recordId == null || recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeIntermenstrualBleeding requires instantMs/zoneOffsetMs/recordId/recordVersionMs",
                        null)
                }
                // No value field at all -- the record's existence is the
                // datum (#193/A3-4, #202/A3-23).
                // #186 sync mechanics: clientRecordId/version, as for
                // writeMenstrualFlow.
                val record = IntermenstrualBleedingRecord(
                    time = Instant.ofEpochMilli(instantMs),
                    zoneOffset = ZoneOffset.ofTotalSeconds((zoneOffsetMs / 1000).toInt()),
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                )
                insert(client, listOf(record), result)
            }

            "deleteRecords" -> {
                // Issue #186 tombstone propagation: delete the records whose
                // clientRecordId is one of the supplied lunarlog record ids.
                // Behind the same guard as every write.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "deleteRecords requires guard args", null)
                val decision = guardDecision(storedBoundProfileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                    return
                }
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                val recordIds = args?.get("recordIds") as? List<*>
                    ?: return result.error(
                        "bad_args", "deleteRecords requires recordIds", null)
                val ids = recordIds.mapNotNull { it as? String }
                if (ids.isEmpty()) {
                    result.success("allowed")
                    return
                }
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    try {
                        // connect-client 1.1.0's delete-by-identifier overload
                        // takes (recordType, recordIdsList, clientRecordIdsList)
                        // — no dataOrigin argument in this version (deletion is
                        // automatically scoped to the calling app's own
                        // records). We delete purely by our lunarlog
                        // clientRecordIds, so the record-id list is empty.
                        client.deleteRecords(
                            MenstruationFlowRecord::class,
                            recordIdsList = emptyList(),
                            clientRecordIdsList = ids)
                        client.deleteRecords(
                            IntermenstrualBleedingRecord::class,
                            recordIdsList = emptyList(),
                            clientRecordIdsList = ids)
                        result.success("allowed")
                    } catch (e: SecurityException) {
                        result.success("permissionDenied")
                    } catch (e: Exception) {
                        result.error("writeFailed", e.message, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    // Health Connect writes are suspend calls; each channel call gets a
    // scope whose only job completes with the call, so there is no
    // lifecycle to manage (the scope is unreachable once its single job
    // finishes).
    private fun insert(
        client: HealthConnectClient,
        records: List<Record>,
        result: MethodChannel.Result,
    ) {
        CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
            try {
                client.insertRecords(records)
                result.success("allowed")
            } catch (e: SecurityException) {
                // The permission was revoked since the prompt (or never
                // granted on this install) — distinguish it from a write
                // failure so Settings copy can send the user back to the
                // prompt.
                result.success("permissionDenied")
            } catch (e: Exception) {
                result.error("writeFailed", e.message, null)
            }
        }
    }

    // The native mirror of HealthSyncBinding._evaluate — same wire
    // strings the Dart codec decodes. `boundProfileId` comes from
    // SharedPreferences for write/authorization calls, and from the
    // *proposed* id for `bind`.
    private fun guardDecision(boundProfileId: String?, g: GuardArgs): String {
        val bound = boundProfileId ?: return "noBinding"
        if (g.profileId != bound) return "profileNotBound"

        val isOwner = g.signedInUserId != null && g.ownerUserId != null &&
            g.signedInUserId == g.ownerUserId

        if (isMinorNow(g.isMinor, g.birthYear)) {
            val transferredToOwnAccount = g.transferredAtMs != null && isOwner
            if (!g.minorBindingAllowed || !transferredToOwnAccount) {
                return "minorRequiresOwnershipTransfer"
            }
            return "allowed"
        }
        return if (!isOwner) "notOwner" else "allowed"
    }

    // Native mirror of HealthSyncBinding._isMinorNow: flagged directly,
    // or under 18 by birth year (coarse same-calendar-year comparison —
    // birthYear carries no month/day).
    private fun isMinorNow(isMinor: Boolean, birthYear: Int?): Boolean {
        if (isMinor) return true
        val year = birthYear ?: return false
        return Calendar.getInstance().get(Calendar.YEAR) - year < 18
    }

    private fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(contextApp) ==
            HealthConnectClient.SDK_AVAILABLE

    private fun healthConnectClient(): HealthConnectClient? =
        if (isAvailable()) HealthConnectClient.getOrCreate(contextApp) else null

    private companion object {
        const val BOUND_PROFILE_KEY = "lunarlog.health.boundProfileId"
    }
}
