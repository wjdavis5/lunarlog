package com.wjdavis5.lunarlog

import android.content.Context
import android.content.SharedPreferences
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BasalBodyTemperatureRecord
import androidx.health.connect.client.records.BodyTemperatureMeasurementLocation
import androidx.health.connect.client.records.CervicalMucusRecord
import androidx.health.connect.client.records.IntermenstrualBleedingRecord
import androidx.health.connect.client.records.MenstruationFlowRecord
import androidx.health.connect.client.records.MenstruationPeriodRecord
import androidx.health.connect.client.records.OvulationTestRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.units.Temperature
// Aliased because a plain `Metadata` import resolves to the compiler's
// own kotlin.Metadata annotation in constructor-argument position here.
import androidx.health.connect.client.records.metadata.Metadata as HcMetadata
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset
import java.util.Calendar
import kotlin.reflect.KClass

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
// Issue #458 adds the read half: getChangesToken/getChanges over the two
// user-recorded menstrual types, with dataOrigin filtering so this app's
// own writes are never re-imported (the Android counterpart of #217's
// sourceRevision filtering) and a change-token-expiry fallback (connect-
// client 1.1.0 reports expiry as ChangesPage.changesTokenExpired, not a
// thrown exception) so a token older than Health Connect's 30-day window
// recovers with a full time-range read instead of failing. The first import
// backfills the bound window directly, then stores a change token for later
// incremental passes. A record whose nullable `zoneOffset` is absent is
// passed through with no offset so the Dart side counts and skips it — never
// guessed from the device zone, matching #217's rule for a HealthKit sample
// with no HKMetadataKeyTimeZone.
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
    //
    // Issue #924: this is the single list of record types the adapter can
    // write. Both the permission request (below) and deleteRecords consume
    // it, so a new write type cannot be added without also being requested
    // and deleted. Before #924, deleteRecords removed only the two flow
    // types, leaving every #228 fertility/measurement record orphaned. Keep
    // in sync with kHealthConnectWrittenRecordTypes in
    // lib/data/health/health_written_types.dart; the guard test
    // test/release/health_deletion_types_test.dart parses this list.
    private val writtenRecordTypes: List<KClass<out Record>> = listOf(
        MenstruationFlowRecord::class,
        // #202: the interval MenstruationPeriodRecord is governed by the
        // same WRITE_MENSTRUATION permission as the flow record — declared
        // explicitly so the prompt covers the type; setOf dedupes the
        // underlying permission string.
        MenstruationPeriodRecord::class,
        IntermenstrualBleedingRecord::class,
        // Issue #228: the fertility/measurement write types. Each has its
        // own Health Connect permission, unlike the menstruation family.
        CervicalMucusRecord::class,
        OvulationTestRecord::class,
        BasalBodyTemperatureRecord::class,
    )

    private val writePermissions =
        writtenRecordTypes.map { HealthPermission.getWritePermission(it) }.toSet()

    // Issue #458 (the owner's #781 read decision, already applied to iOS in
    // #217): the read/import half. Only the two user-recorded menstrual
    // types are read; the request sheet carries both sets at once, the
    // Android counterpart of #217's single `requestAuthorization(toShare:,
    // read:)` call. Nothing derived or predicted is ever read or written.
    private val readPermissions = setOf(
        HealthPermission.getReadPermission(MenstruationFlowRecord::class),
        HealthPermission.getReadPermission(IntermenstrualBleedingRecord::class),
    )

    private val allPermissions = writePermissions + readPermissions

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
        // Issue #619, LLA-031: the server-stamped transfer target, mirroring
        // HealthSyncBinding._minorTransferExceptionHolds's `target ==
        // signedInUserId` leg — without this, guardDecision could only see
        // THAT a transfer happened, never WHOM it named.
        val transferredToUserId: String?,
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
                    transferredToUserId = args["transferredToUserId"] as? String,
                    minorBindingAllowed = minorBindingAllowed,
                )
            }

            fun number(args: Map<*, *>?, key: String): Long? =
                (args?.get(key) as? Number)?.toLong()
        }
    }

    private val storedBoundProfileId: String?
        get() = prefs.getString(BOUND_PROFILE_KEY, null)

    // Issue #228: `CervicalMucusRecord` is published by the Health Connect
    // client for app use but its source file carries a library-scoped
    // `@file:RestrictTo`, which Android Lint flags as RestrictedApi even
    // though the class is a normal part of the app-facing record API
    // (Google's own data-type samples construct it directly). Scoped to this
    // handler, the one place the adapter touches it.
    @Suppress("RestrictedApi")
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
                val editor = prefs.edit().remove(BOUND_PROFILE_KEY)
                // Drop the profile's incremental read anchor too, so a later
                // re-bind starts from a clean backfill (Issue #458).
                storedBoundProfileId?.let { editor.remove(changesTokenKey(it)) }
                editor.apply()
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
                    // The one sheet covers write and read types (Issue #458);
                    // a user who has only ever imported still sees the prompt.
                    launcher.launch(allPermissions)
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

            "writeMenstrualPeriod" -> {
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeMenstrualPeriod requires guard args", null)
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
                val startMs = GuardArgs.number(args, "startMs")
                val startZoneOffsetMs = GuardArgs.number(args, "startZoneOffsetMs")
                val endMs = GuardArgs.number(args, "endMs")
                val endZoneOffsetMs = GuardArgs.number(args, "endZoneOffsetMs")
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (startMs == null || startZoneOffsetMs == null || endMs == null ||
                    endZoneOffsetMs == null || recordId == null || recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeMenstrualPeriod requires startMs/startZoneOffsetMs/endMs/endZoneOffsetMs/recordId/recordVersionMs",
                        null)
                }
                // #202: the interval record for one period episode. startTime
                // at the episode's first-day local midnight; endTime at the
                // *exclusive* local midnight after its last day — both instants
                // and their offsets computed on the Dart side from the entry's
                // own tz (#180's timezone contract, never the device's current
                // zone; on a DST-transition day endZoneOffset differs from
                // startZoneOffset, which is exactly why they ride separately).
                // #186 sync mechanics: the episode's stable clientRecordId plus
                // an increasing clientRecordVersion make a re-write of an
                // extending episode an upsert (update), not a duplicate, and a
                // closed episode's final write carries the complete interval.
                val record = MenstruationPeriodRecord(
                    startTime = Instant.ofEpochMilli(startMs),
                    startZoneOffset = ZoneOffset.ofTotalSeconds((startZoneOffsetMs / 1000).toInt()),
                    endTime = Instant.ofEpochMilli(endMs),
                    endZoneOffset = ZoneOffset.ofTotalSeconds((endZoneOffsetMs / 1000).toInt()),
                    // User-logged cycle data (issue #254). The Metadata
                    // constructor is internal in connect-client 1.1.0, so the
                    // public companion factory is used, as for the flow record.
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                )
                insert(client, listOf(record), result)
            }

            "writeSymptomSamples" -> {
                // Issue #238: a permanent platform limitation, not a gap.
                // Health Connect has NO symptom category types — the exact
                // asymmetry against HealthKit (which has first-class
                // symptom types with severity) is documented in
                // lib/data/health/health_symptom_mapping.dart and stated in
                // the Settings health-sync copy. Symptoms are deliberately
                // never smuggled into a record's notes/metadata as a
                // workaround: that would be unreadable to other apps and
                // would misrepresent the data. Answering "unavailable" lets
                // the Dart write service skip symptom writes gracefully on
                // this platform while flow writes proceed normally.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeSymptomSamples requires guard args", null)
                val decision = guardDecision(storedBoundProfileId, g)
                if (decision != "allowed") {
                    result.success(decision)
                    return
                }
                check(SYMPTOM_TYPES_UNSUPPORTED.isNotEmpty()) {
                    "the unsupported symptom-type registry must name the types"
                }
                result.success("unavailable")
            }

            "writeCervicalMucus" -> {
                // Issue #228: the appearance decision lives in Dart
                // (health_fertility_mapping.dart); this handler only
                // translates the resolved appearance constant and supplies
                // the mandatory sensation as SENSATION_UNKNOWN. The domain
                // deliberately has no sensation concept (the issue's
                // instruction), so no value is invented.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeCervicalMucus requires guard args", null)
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
                val appearanceWire = args?.get("healthConnectAppearance") as? String
                val appearance = when (appearanceWire) {
                    "APPEARANCE_DRY" -> CervicalMucusRecord.APPEARANCE_DRY
                    "APPEARANCE_STICKY" -> CervicalMucusRecord.APPEARANCE_STICKY
                    "APPEARANCE_CREAMY" -> CervicalMucusRecord.APPEARANCE_CREAMY
                    "APPEARANCE_WATERY" -> CervicalMucusRecord.APPEARANCE_WATERY
                    "APPEARANCE_EGG_WHITE" -> CervicalMucusRecord.APPEARANCE_EGG_WHITE
                    else -> null
                }
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (instantMs == null || zoneOffsetMs == null || appearance == null ||
                    recordId == null || recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeCervicalMucus requires instantMs/zoneOffsetMs/healthConnectAppearance/recordId/recordVersionMs",
                        null)
                }
                val record = CervicalMucusRecord(
                    time = Instant.ofEpochMilli(instantMs),
                    zoneOffset = ZoneOffset.ofTotalSeconds((zoneOffsetMs / 1000).toInt()),
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                    appearance = appearance,
                    sensation = CervicalMucusRecord.SENSATION_UNKNOWN,
                )
                insert(client, listOf(record), result)
            }

            "writeOvulationTest" -> {
                // Issue #228: the result decision (including the positive/
                // peak collapse) lives in Dart; this handler only translates
                // the resolved result constant.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeOvulationTest requires guard args", null)
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
                val resultWire = args?.get("healthConnectResult") as? String
                val ovulationResult = when (resultWire) {
                    "RESULT_NEGATIVE" -> OvulationTestRecord.RESULT_NEGATIVE
                    "RESULT_POSITIVE" -> OvulationTestRecord.RESULT_POSITIVE
                    "RESULT_INCONCLUSIVE" -> OvulationTestRecord.RESULT_INCONCLUSIVE
                    "RESULT_HIGH" -> OvulationTestRecord.RESULT_HIGH
                    else -> null
                }
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (instantMs == null || zoneOffsetMs == null ||
                    ovulationResult == null || recordId == null ||
                    recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeOvulationTest requires instantMs/zoneOffsetMs/healthConnectResult/recordId/recordVersionMs",
                        null)
                }
                val record = OvulationTestRecord(
                    time = Instant.ofEpochMilli(instantMs),
                    zoneOffset = ZoneOffset.ofTotalSeconds((zoneOffsetMs / 1000).toInt()),
                    result = ovulationResult,
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                )
                insert(client, listOf(record), result)
            }

            "writeBasalBodyTemperature" -> {
                // Issue #228: the value arrives already in Celsius (Dart
                // converts via #255's convertTemperature). The measurement
                // location is the Dart-resolved constant; the domain has no
                // location field, so it is the honest unknown — never a
                // guessed site. A platform/wearable-sourced value never
                // reaches here (Dart filters by source).
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "writeBasalBodyTemperature requires guard args", null)
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
                val celsius = (args?.get("celsius") as? Number)?.toDouble()
                val locationWire =
                    args?.get("healthConnectMeasurementLocation") as? String
                val recordId = args?.get("recordId") as? String
                val recordVersionMs = GuardArgs.number(args, "recordVersionMs")
                if (instantMs == null || zoneOffsetMs == null || celsius == null ||
                    locationWire == null || recordId == null ||
                    recordVersionMs == null) {
                    return result.error(
                        "bad_args",
                        "writeBasalBodyTemperature requires instantMs/zoneOffsetMs/celsius/healthConnectMeasurementLocation/recordId/recordVersionMs",
                        null)
                }
                val measurementLocation = when (locationWire) {
                    "MEASUREMENT_LOCATION_UNKNOWN" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_UNKNOWN
                    "MEASUREMENT_LOCATION_ARMPIT" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_ARMPIT
                    "MEASUREMENT_LOCATION_FINGER" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_FINGER
                    "MEASUREMENT_LOCATION_FOREHEAD" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_FOREHEAD
                    "MEASUREMENT_LOCATION_MOUTH" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_MOUTH
                    "MEASUREMENT_LOCATION_RECTUM" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_RECTUM
                    "MEASUREMENT_LOCATION_TEMPORAL_ARTERY" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_TEMPORAL_ARTERY
                    "MEASUREMENT_LOCATION_TOE" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_TOE
                    "MEASUREMENT_LOCATION_EAR" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_EAR
                    "MEASUREMENT_LOCATION_WRIST" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_WRIST
                    "MEASUREMENT_LOCATION_VAGINA" ->
                        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_VAGINA
                    else -> null
                }
                if (measurementLocation == null) {
                    return result.error(
                        "bad_args",
                        "unknown measurement location: $locationWire",
                        null)
                }
                val record = BasalBodyTemperatureRecord(
                    time = Instant.ofEpochMilli(instantMs),
                    zoneOffset = ZoneOffset.ofTotalSeconds((zoneOffsetMs / 1000).toInt()),
                    metadata = HcMetadata.manualEntry(
                        clientRecordId = recordId,
                        clientRecordVersion = recordVersionMs,
                    ),
                    temperature = Temperature.celsius(celsius),
                    measurementLocation = measurementLocation,
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
                        //
                        // Issue #924: loop over EVERY record type this adapter
                        // writes — the two flow types (#186), the period
                        // interval (#619, LLA-030, which used to be missing
                        // here entirely), and #228's fertility/measurement
                        // records, whose samples were previously left
                        // orphaned. writtenRecordTypes is the same list the
                        // write-permission request uses, so a future type
                        // cannot be added to one without the other.
                        for (recordType in writtenRecordTypes) {
                            @Suppress("UNCHECKED_CAST")
                            val concreteType = recordType as KClass<Record>
                            client.deleteRecords(
                                concreteType,
                                recordIdsList = emptyList(),
                                clientRecordIdsList = ids)
                        }
                        result.success("allowed")
                    } catch (e: SecurityException) {
                        result.success("permissionDenied")
                    } catch (e: Exception) {
                        result.error("writeFailed", e.message, null)
                    }
                }
            }

            "readMenstrualFlow" -> {
                // Issue #458 (#781's read decision): the user-initiated
                // import. Guarded identically to a write (the device-binding
                // decision is the same), then a bounded read over the two
                // user-recorded menstrual types. Success returns an array of
                // primitive maps (StandardMessageCodec), not a result string.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "readMenstrualFlow requires guard args", null)
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
                val startMs = GuardArgs.number(args, "startMs")
                val endMs = GuardArgs.number(args, "endMs")
                if (startMs == null || endMs == null) {
                    return result.error(
                        "bad_args", "readMenstrualFlow requires startMs/endMs", null)
                }
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    try {
                        result.success(
                            readSamples(client, g.profileId, startMs, endMs))
                    } catch (e: SecurityException) {
                        // Read permission revoked or never granted on this
                        // install — distinct from a read failure. The Dart
                        // side deliberately coalesces this with "no data".
                        result.success("permissionDenied")
                    } catch (e: Exception) {
                        result.error("readFailed", e.message, null)
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

    // Issue #458: the read/import half. Reads the requested window through
    // the Changes API when a stored token exists (an incremental pass),
    // recovering from an expired token (connect-client 1.1.0 surfaces this
    // as ChangesPage.changesTokenExpired, not a thrown exception) with a
    // full window read, and directly when no token exists (the first import
    // backfill). A fresh token for the next pass is stored either way.
    // Records this app itself wrote are dropped by dataOrigin — the
    // mandatory loop-breaker.
    private suspend fun readSamples(
        client: HealthConnectClient,
        profileId: String,
        startMs: Long,
        endMs: Long,
    ): List<Map<String, Any>> {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val tokenKey = changesTokenKey(profileId)
        val storedToken = prefs.getString(tokenKey, null)
        val records = LinkedHashMap<String, Record>()
        if (storedToken == null) {
            records.putAll(readWindow(client, start, end))
        } else {
            val page = client.getChanges(storedToken)
            if (page.changesTokenExpired) {
                // Health Connect tokens expire after 30 days: clear the
                // stale anchor and recover with the same full window read a
                // first import uses, rather than failing the pass.
                prefs.edit().remove(tokenKey).apply()
                records.putAll(readWindow(client, start, end))
            } else {
                for (change in page.changes) {
                    if (change is UpsertionChange) {
                        records[change.record.metadata.id] = change.record
                    }
                }
            }
        }
        // Mint the next incremental anchor. Best-effort: a token failure
        // must not fail a pass that already read its data.
        storeChangesToken(client, tokenKey)
        return records.values.mapNotNull { sampleFor(it, start, end) }
    }

    // A full time-range read over the two user-recorded menstrual types.
    private suspend fun readWindow(
        client: HealthConnectClient,
        start: Instant,
        end: Instant,
    ): Map<String, Record> {
        val records = LinkedHashMap<String, Record>()
        val filter = TimeRangeFilter.between(start, end)
        for (record in client.readRecords(
            ReadRecordsRequest(MenstruationFlowRecord::class, filter)
        ).records) {
            records[record.metadata.id] = record
        }
        for (record in client.readRecords(
            ReadRecordsRequest(IntermenstrualBleedingRecord::class, filter)
        ).records) {
            records[record.metadata.id] = record
        }
        return records
    }

    // Stores a token representing "now" for the next incremental pass.
    private suspend fun storeChangesToken(
        client: HealthConnectClient,
        tokenKey: String,
    ) {
        val token = try {
            client.getChangesToken(
                ChangesTokenRequest(
                    setOf(
                        MenstruationFlowRecord::class,
                        IntermenstrualBleedingRecord::class,
                    ),
                ),
            )
        } catch (e: Exception) {
            null
        }
        if (token != null) prefs.edit().putString(tokenKey, token).apply()
    }

    // One record's primitive sample map, or null when it is our own write,
    // outside the requested window, or not a supported type.
    private fun sampleFor(
        record: Record,
        start: Instant,
        end: Instant,
    ): Map<String, Any>? {
        // Mandatory echo prevention: a record this app wrote comes back
        // with our own package as dataOrigin. Re-importing it would
        // duplicate every entry and loop the write/read directions.
        if (record.metadata.dataOrigin.packageName == contextApp.packageName) {
            return null
        }
        return when (record) {
            is MenstruationFlowRecord ->
                if (inWindow(record.time, start, end)) {
                    sampleMap(record.metadata.id, "menstrualFlow", record.time,
                        record.zoneOffset) + ("flow" to flowWire(record.flow))
                } else {
                    null
                }
            is IntermenstrualBleedingRecord ->
                if (inWindow(record.time, start, end)) {
                    sampleMap(record.metadata.id, "intermenstrualBleeding",
                        record.time, record.zoneOffset)
                } else {
                    null
                }
            else -> null
        }
    }

    private fun inWindow(time: Instant, start: Instant, end: Instant): Boolean =
        !time.isBefore(start) && !time.isAfter(end)

    private fun flowWire(flow: Int): String = when (flow) {
        MenstruationFlowRecord.FLOW_LIGHT -> "light"
        MenstruationFlowRecord.FLOW_MEDIUM -> "medium"
        MenstruationFlowRecord.FLOW_HEAVY -> "heavy"
        else -> "unspecified"
    }

    // [zoneOffset] is deliberately nullable: connect-client 1.1.0 types it
    // `ZoneOffset?`, and a record that does not know its own offset must not
    // be resolved against the device's current zone. Omitting the key makes
    // the Dart codec report it as samplesWithoutZone and skip it — the same
    // rule #217 applies to a HealthKit sample with no HKMetadataKeyTimeZone.
    // Note the deliberate difference from the iOS half after Issue #902: a
    // Health Connect record's `zoneOffset` is the record's OWN, so this map
    // never sets the `zoneOffsetInferred` flag the Swift read sets when it
    // has to synthesize an offset from the device zone. The flag defaults to
    // false in health_channel_codec.dart, so Android rows are always counted
    // as recorded-zone rows.
    private fun sampleMap(
        id: String,
        kind: String,
        time: Instant,
        zoneOffset: ZoneOffset?,
    ): MutableMap<String, Any> {
        val map = mutableMapOf<String, Any>(
            "recordId" to id,
            "kind" to kind,
            // These records are instantaneous; the codec needs one bound.
            "startMs" to time.toEpochMilli(),
            "endMs" to time.toEpochMilli(),
        )
        if (zoneOffset != null) {
            // A Health Connect record carries a raw offset, not an IANA
            // name; the Dart side resolves the civil date from it (#180).
            map["zoneOffsetSeconds"] = zoneOffset.totalSeconds
        }
        return map
    }

    private fun changesTokenKey(profileId: String): String =
        "lunarlog.health.changesToken.$profileId"

    // The native mirror of HealthSyncBinding._evaluate — same wire
    // strings the Dart codec decodes. `boundProfileId` comes from
    // SharedPreferences for write/authorization calls, and from the
    // *proposed* id for `bind`. Issue #882 keeps this in lockstep with
    // the Dart predicate and with the iOS half in AppDelegate.swift: a
    // minor is no longer a special deny when `minorBindingAllowed` is
    // true, and a device-only profile is treated as locally owned.
    private fun guardDecision(boundProfileId: String?, g: GuardArgs): String {
        val bound = boundProfileId ?: return "noBinding"
        if (g.profileId != bound) return "profileNotBound"

        val isOwner = g.signedInUserId != null && g.ownerUserId != null &&
            g.signedInUserId == g.ownerUserId

        // Issue #882: the switch's off position keeps the pre-#882
        // categorical minor deny. With `minorBindingAllowed` true a minor
        // is NOT special — it falls through to the same owner gate as an
        // adult.
        if (isMinorNow(g.isMinor, g.birthYear) && !g.minorBindingAllowed) {
            return "minorRequiresOwnershipTransfer"
        }

        // Issue #619, LLA-031: every leg of
        // HealthSyncBinding._minorTransferExceptionHolds — the flag is on,
        // a transfer happened, the caller is the resolved owner, AND it
        // named exactly the signed-in account — not merely "some transfer
        // happened and the caller happens to pass isOwner". Preserved by
        // #882; the owner gate below would allow every case this holds for.
        val minorTransferExceptionHolds = g.minorBindingAllowed &&
            g.transferredAtMs != null && isOwner &&
            g.transferredToUserId != null &&
            g.transferredToUserId == g.signedInUserId
        if (minorTransferExceptionHolds) return "allowed"

        // Issue #882: no resolved owner at all means allowed — nobody else
        // claims the profile, so the local operator is treated as its
        // owner (the common case for a locally created, never-synced
        // profile). notOwner is returned only when an owner actually
        // exists and does not match the signed-in account.
        return if (!ownerCheckAllows(g.ownerUserId, isOwner)) {
            "notOwner"
        } else {
            "allowed"
        }
    }

    // Native mirror of HealthSyncBinding._ownerCheckAllows (Issue #882):
    // ownerUserId == null (no accepted primary_guardian row resolved, even
    // while signed in) passes, and so does a resolved owner. It fails
    // closed only when an owner exists and is not the signed-in account.
    private fun ownerCheckAllows(
        ownerUserId: String?,
        isOwner: Boolean,
    ): Boolean =
        isOwner || ownerUserId == null

    // Native mirror of HealthSyncBinding._isMinorNow: flagged directly, or
    // AT MOST 18 whole years since birthYear (issue #619, LLA-031: `<=`,
    // not `<` — matching the Dart side's Issue #296 tightening, where a
    // year-only birthYear can't see the birthday so the whole calendar
    // year someone turns 18 still fails closed. The pre-fix `< 18` here
    // let a birth year exactly 18 years back read as an adult while Dart
    // still denied it — a defense-in-depth gap, not a live bypass, since
    // the Dart guard already covered it.
    private fun isMinorNow(isMinor: Boolean, birthYear: Int?): Boolean {
        if (isMinor) return true
        val year = birthYear ?: return false
        return Calendar.getInstance().get(Calendar.YEAR) - year <= 18
    }

    private fun isAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(contextApp) ==
            HealthConnectClient.SDK_AVAILABLE

    private fun healthConnectClient(): HealthConnectClient? =
        if (isAvailable()) HealthConnectClient.getOrCreate(contextApp) else null

    private companion object {
        const val BOUND_PROFILE_KEY = "lunarlog.health.boundProfileId"

        // Issue #238: the permanent platform limitation, registered
        // explicitly here (the adapter's type registry). Health Connect
        // exposes no record class for any of HealthKit's symptom category
        // types, so there is nothing to add to the write-permission set and
        // nothing to insert. Naming them lets a future reader diff this
        // adapter against the Dart mapping table
        // (lib/data/health/health_symptom_mapping.dart) and see that the
        // absence is a decision, never a silent omission. The
        // writeSymptomSamples handler answers "unavailable" accordingly.
        val SYMPTOM_TYPES_UNSUPPORTED = listOf(
            "abdominalCramps",
            "headache",
            "lowerBackPain",
            "breastPain",
            "bloating",
            "acne",
            "nausea",
            "fatigue",
            "dizziness",
            "moodChanges",
            "sleepChanges",
            "appetiteChanges",
        )
    }
}
