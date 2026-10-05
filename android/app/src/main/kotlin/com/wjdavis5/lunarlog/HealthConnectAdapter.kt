package com.wjdavis5.lunarlog

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
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
import androidx.health.connect.client.response.ChangesResponse
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64
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
        contextApp.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    // Issue #1478: the moment this copy of the app was first installed on
    // this device — what the "permission request was launched" marker
    // ([PERMISSION_REQUESTED_KEY]) is stamped with, so the marker counts
    // only for the install that made it. The Health Connect permissions are
    // per install: a reinstall, or a new phone, starts with none granted
    // and nothing asked. An uninstall clears these prefs, but Android's
    // device-to-device transfer can copy them to a new phone
    // (data_extraction_rules.xml keeps only the database out of it), and a
    // bare flag carried over would make that phone read "denied" before it
    // had ever been asked — the very thing the marker exists to prevent.
    // Zero when the package manager cannot answer; the marker then counts
    // whenever it is present.
    private val installStamp: Long = try {
        contextApp.packageManager
            .getPackageInfo(contextApp.packageName, 0)
            .firstInstallTime
    } catch (_: Exception) {
        0L
    }

    // Whether THIS install set the asked-marker under [key] (see
    // [installStamp]). A marker of any other type — no released build has
    // written one — reads as not asked rather than throwing.
    private fun markerSetByThisInstall(key: String): Boolean = try {
        prefs.contains(key) && prefs.getLong(key, 0L) == installStamp
    } catch (_: ClassCastException) {
        false
    }

    // Issue #1515: there are two requests, so there are two things to have
    // been asked. Whether this install has put the WRITE permissions in
    // front of the person: it launched the request that carries them
    // (requestWriteAuthorization), or `permissionStatus` has seen a write
    // granted. This alone decides "not yet asked" against "denied" for the
    // write status. The import's own request carries no write permission
    // and sets a marker of its own, so tapping Import can never make the
    // write status read "denied" for someone who was never asked for the
    // writes — which would stop the write pass before its own request.
    private fun writesEverRequested(): Boolean =
        markerSetByThisInstall(PERMISSION_REQUESTED_KEY)

    // Whether this install has launched a permission request at all —
    // either one. Both carry the reads (the write path's sheet has always
    // offered them beside the writes), so this is "asked" for the read
    // side: what `importPermissionStatus` tells "not yet asked" from
    // "denied" by.
    private fun permissionEverRequested(): Boolean =
        writesEverRequested() ||
            markerSetByThisInstall(IMPORT_REQUEST_LAUNCHED_KEY)

    init {
        // Issue #993: app start with a bound profile (re)arms the periodic
        // background-import job. KEEP policy — this never resets the
        // schedule's clock; the worker re-checks the binding mirror on
        // every tick, so an unbound device's tick is a no-op regardless.
        if (prefs.getString(BOUND_PROFILE_KEY, null) != null) {
            HealthBackgroundImportScheduler.schedule(contextApp)
        }
    }

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
    // Issue #992: READ_HEALTH_DATA_HISTORY lifts Health Connect's default
    // 30-day pre-grant read cap so the import can read the whole history.
    // It is a permission constant rather than a per-record permission, so
    // it rides this set as-is.
    // Issue #1211: READ_HEALTH_DATA_IN_BACKGROUND is a Health Connect
    // *runtime* permission like the record reads — the manifest declaration
    // #993 shipped is only the precondition, so it joins the requested set
    // too, but only where the platform actually offers the feature
    // ([backgroundReadPermissions] answers empty anywhere else, and there
    // this set is exactly the pre-#1211 shape). The permission is
    // deliberately NOT part of the check `permissionStatus` answers (no
    // read permission is — see [statusPermissions] below): a user who
    // declines background reads can still import by tap, and
    // HealthBackgroundImportWorker skips its own pass without it.
    //
    // Issue #1491: the reads the import itself performs — the two record
    // types [readSamples] reads, by time range (readRecords) and by change
    // token (getChanges). This is the whole set `importPermissionStatus`
    // requires, and so the gate of the Dart background import pass. The two
    // optional extras that ride the request sheet beside them are
    // deliberately NOT in it: READ_HEALTH_DATA_HISTORY only widens how far
    // back a read reaches (the pass still reads without it), and
    // READ_HEALTH_DATA_IN_BACKGROUND is what the worker's own tick checks
    // ([backgroundReadRefused]) before it wakes Dart at all.
    private val importReadPermissions = setOf(
        HealthPermission.getReadPermission(MenstruationFlowRecord::class),
        HealthPermission.getReadPermission(IntermenstrualBleedingRecord::class),
    )

    // Issue #1515: this is also the whole of what the IMPORT asks for
    // (requestImportAuthorization): the two record reads and the two
    // optional read extras, and no write permission. Someone who let
    // lunarlog read and not write used to get the write permissions put in
    // front of her again on every tap of Import, because the import asked
    // through the one request that carried everything.
    private val readPermissions = setOf(
        HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY,
    ) + importReadPermissions + backgroundReadPermissions()

    // What the WRITE path asks for (requestWriteAuthorization): the writes,
    // with the reads beside them on the same sheet. That request is raised
    // once, a moment after a profile is bound, so it stays the one place a
    // person can allow both directions in a single answer.
    private val allPermissions = writePermissions + readPermissions

    // The set `permissionStatus`'s "granted" answer requires: the WRITE
    // permissions and nothing else (issue #1478). `HealthPermissionStatus`
    // is defined on the Dart side as the OS consent for the types this app
    // writes, and the write pass re-checks it before every pass (#959), so
    // it must answer exactly the question "may lunarlog write?". Before
    // #1478 this was every requested permission except the background read
    // (#1211), which made each optional READ permission a precondition for
    // writing: a person who allowed the writes but left "Access past data"
    // off (READ_HEALTH_DATA_HISTORY, a switch Health Connect presents as an
    // optional extra) was reported as "denied" and had every write pass
    // blocked. The read permissions and the #1211 background read still ride
    // the request sheet (`allPermissions`, above) but never this check: a
    // missing read permission surfaces where it matters, as the import's own
    // "no data, or read access is off" result, and the background worker
    // gates its own tick (see the companion's [backgroundReadRefused]).
    // The background import pass has a status of its own for the same
    // reason in the other direction (issue #1491, `importPermissionStatus`
    // over [importReadPermissions]): gated on this write status, it never
    // ran for a person who allowed reading and not writing.
    private val statusPermissions = writePermissions

    // The background-read permission, only where it can actually be
    // granted. connect-client 1.1.0 has no `isFeatureAvailable` — the
    // availability check is the feature status (getFeatureStatus against
    // FEATURE_STATUS_AVAILABLE), which is also what the background-read
    // documentation requires before requesting. An unavailable Health
    // Connect or any probe failure answers empty: the failure mode is
    // deliberately fail-to-not-request, because asking for an
    // unrequestable permission string would poison the whole sheet.
    private fun backgroundReadPermissions(): Set<String> = try {
        val offered = isAvailable() &&
            HealthConnectClient.getOrCreate(contextApp).features
                .getFeatureStatus(
                    HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
                ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        if (offered) {
            setOf(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
        } else {
            emptySet()
        }
    } catch (_: Exception) {
        emptySet()
    }

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
                    // Issue #993: a first-ever bind during this session
                    // arms the periodic background-import job (KEEP policy,
                    // so re-binds never reset the clock).
                    HealthBackgroundImportScheduler.schedule(contextApp)
                    result.success("allowed")
                }
            }

            "unbind" -> {
                val editor = prefs.edit().remove(BOUND_PROFILE_KEY)
                // Drop the profile's incremental read anchor too, so a later
                // re-bind starts from a clean backfill (Issue #458).
                storedBoundProfileId?.let { editor.remove(changesTokenKey(it)) }
                editor.apply()
                // Issue #993: an unbound device stops being woken for
                // background imports. Best-effort; the Dart-side guard
                // refuses an unbound pass regardless.
                HealthBackgroundImportScheduler.cancel(contextApp)
                result.success(null)
            }

            "consumePendingBackgroundImportTrigger" -> {
                // Issue #993: the Dart coordinator's startup pull. Android
                // has no native-side latch to clear — its worker pushes only
                // into a live engine (a tick that lands on a restarted
                // process finds no engine and no-ops) — so the answer is
                // always false. Unguarded: it reads no health data and
                // touches no health API.
                result.success(false)
            }

            // The WRITE path's request: the writes, and the reads beside
            // them on the one sheet (Issue #458). Launching it is what
            // `permissionStatus` remembers as "asked" (Issue #1478).
            "requestWriteAuthorization" -> {
                if (!requestGuardAllows(call.method, args, result)) return
                launchPermissionRequest(
                    result,
                    askedMarker = PERMISSION_REQUESTED_KEY,
                    permissions = allPermissions,
                )
            }

            // Issue #1515: the IMPORT's request — what the import reads and
            // the two optional read extras, and no write permission. It
            // sets a marker of its own and never the write one: being asked
            // for the reads is not being asked for the writes.
            //
            // It asks only when the import cannot read
            // ([HealthPermissionState.importMustAsk]): with both record
            // reads granted there is nothing the import needs, so no sheet
            // is raised. Asking regardless put Health Connect's "access
            // past data" sheet in front of someone on every tap of Import
            // for as long as she had declined that one extra only once —
            // and, once an extra has been declined twice, Health Connect
            // drops the whole request and counts it as one more refusal of
            // whatever else in it is not granted.
            "requestImportAuthorization" -> {
                if (!requestGuardAllows(call.method, args, result)) return
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    // A query that fails says nothing about what is
                    // granted, so the request goes ahead as it would have.
                    val granted = try {
                        client.permissionController.getGrantedPermissions()
                    } catch (e: Exception) {
                        emptySet()
                    }
                    if (!HealthPermissionState.importMustAsk(granted, importReadPermissions)) {
                        result.success("allowed")
                        return@launch
                    }
                    // Off the channel's own call stack now, so a launch
                    // that throws is answered here rather than by the
                    // channel — as the failure it always was, not a crash.
                    try {
                        launchPermissionRequest(
                            result,
                            askedMarker = IMPORT_REQUEST_LAUNCHED_KEY,
                            permissions = readPermissions,
                        )
                    } catch (e: Exception) {
                        if (pendingAuthResult === result) pendingAuthResult = null
                        result.error("writeFailed", e.message, null)
                    }
                }
            }

            "importPermissionStatus" -> {
                // Issue #1491: the READ-side permission state, the gate of
                // the Dart background import pass (importInBackground). That
                // pass used to be gated on `permissionStatus` below, which
                // answers for the WRITE permissions — so a person who let
                // lunarlog read from Health Connect and not write to it had
                // a tap import that worked and a background import that
                // never ran. This answers for [importReadPermissions] alone:
                // no write permission, and neither optional extra.
                //
                // It only looks. It raises no permission request (a
                // background pass must never put a sheet in front of the
                // person), and it reads the asked-markers without ever
                // setting one — unlike `permissionStatus`, which remembers a
                // grant it sees — so asking this question never changes
                // what `permissionStatus` answers for the write path.
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    try {
                        val granted = client.permissionController.getGrantedPermissions()
                        result.success(
                            HealthPermissionState.importStatusFor(
                                granted = granted,
                                importReads = importReadPermissions,
                                requested = allPermissions,
                                everRequested = permissionEverRequested(),
                            ))
                    } catch (e: Exception) {
                        result.success("unavailable")
                    }
                }
            }

            "permissionStatus" -> {
                // Issue #959: the OS permission state for the status line on
                // the Health sync screen. The SDK-availability check runs
                // first (an unavailable Health Connect is "unavailable",
                // never "denied"), then the WRITE permission set
                // ([statusPermissions]) is compared against
                // getGrantedPermissions(). Neither a read permission nor the
                // #1211 background read is part of that comparison: declining
                // a read must not read as a denial of the writes (issue
                // #1478), nor declining background reads as a denial of the
                // tap import (#1211).
                //
                // Issue #1478: Android's runtime model cannot tell "never
                // asked" from "denied" by looking at the granted set, and
                // reporting every not-granted state as "denied" did two
                // things wrong. A fresh install read "denied" before the
                // person had been asked anything; and, because the Dart
                // write pass treats "denied" as a revocation and stops
                // before its own authorization request (#959), the write
                // path could never ask at all. So this install remembers
                // whether it has ever launched the request that carries
                // the writes ([PERMISSION_REQUESTED_KEY], set in
                // requestWriteAuthorization, read through
                // [writesEverRequested]) and
                // [HealthPermissionState.writeStatusFor] answers "notAsked"
                // until it has.
                //
                // Issue #1515: "asked" here means asked for the WRITES. The
                // import has a request of its own now, for the reads alone,
                // so neither its marker nor a granted read says anything
                // about the writes: someone who has only ever tapped Import
                // and allowed the reads still reads "notAsked" here, and the
                // write pass still asks her.
                // The client owns the PermissionController
                // (`client.permissionController`); getGrantedPermissions is
                // its suspend query, so it runs on a coroutine.
                val client = healthConnectClient()
                if (client == null) {
                    result.success("unavailable")
                    return
                }
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    try {
                        val granted = client.permissionController.getGrantedPermissions()
                        // Issue #1478's review: a grant seen here counts
                        // as having been asked, and is remembered as such.
                        // Access can be granted without this install's
                        // sheet — by an older build's, or in Health
                        // Connect's own settings — and if it is later
                        // removed altogether, nothing granted and no marker
                        // would read "not yet asked". With a forward-only
                        // cursor already in place the write pass never asks
                        // again, so every write would fail behind a screen
                        // that offers no way to Health Connect's settings.
                        // Remembered, the same revocation reads "denied".
                        // Issue #1515: the grant that counts is a WRITE
                        // grant. A read can now be granted on the import's
                        // own sheet, which never showed the writes.
                        if (HealthPermissionState.provesAsked(granted, writePermissions) &&
                            !writesEverRequested()) {
                            prefs.edit()
                                .putLong(PERMISSION_REQUESTED_KEY, installStamp)
                                .apply()
                        }
                        result.success(
                            HealthPermissionState.writeStatusFor(
                                granted = granted,
                                writes = statusPermissions,
                                writesEverRequested = writesEverRequested(),
                            ))
                    } catch (e: Exception) {
                        result.success("unavailable")
                    }
                }
            }

            "openPermissionSettings" -> {
                // Issue #959: Health Connect's own settings/permission
                // activity is where the operator changes this app's access.
                // Best effort, like the iOS Settings deep link.
                try {
                    val intent =
                        Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    contextApp.startActivity(intent)
                } catch (e: Exception) {
                    // No Health Connect settings UI to open — nothing to do.
                }
                result.success(null)
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
                // last instant of its last day (issue #1478: Health Connect
                // counts a period's days from its start date to its end date
                // inclusive, so the next-midnight end #202 used made every
                // period a day too long there) — both instants
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
                // Issue #920: BBT is a point/waking measurement (instantMs
                // resolves observedAt when present or 07:00 morning local time).
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
                    ?: GuardArgs.number(args, "startMs")
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

            "readMenstrualFlowPage" -> {
                // Issue #458 (#781's read decision), paged for full history
                // in Issue #992: the user-initiated import. Guarded
                // identically to a write (the device-binding decision is the
                // same), then one page over the two user-recorded menstrual
                // types. Success returns `{samples, nextCursor?}` primitive
                // maps (StandardMessageCodec), not a result string.
                val g = GuardArgs.parse(args)
                    ?: return result.error(
                        "bad_args", "readMenstrualFlowPage requires guard args", null)
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
                val pageSize = GuardArgs.number(args, "pageSize")?.toInt() ?: 0
                if (startMs == null || endMs == null || pageSize <= 0) {
                    return result.error(
                        "bad_args",
                        "readMenstrualFlowPage requires startMs/endMs/pageSize",
                        null)
                }
                val cursor = args?.get("cursor") as? String
                CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
                    try {
                        result.success(
                            readSamples(
                                client, g.profileId, startMs, endMs, pageSize,
                                cursor))
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

    // The guard in front of both permission requests — the same one as in
    // front of a write, since asking is itself a health-API touch. True
    // when the request may go ahead; otherwise [result] has already been
    // answered (bad arguments, the #153 guard's refusal, or no Health
    // Connect) and the caller must stop. One function for the write path's
    // request and the import's (issue #1515), so the two cannot drift.
    private fun requestGuardAllows(
        method: String,
        args: Map<*, *>?,
        result: MethodChannel.Result,
    ): Boolean {
        val g = GuardArgs.parse(args)
        if (g == null) {
            result.error("bad_args", "$method requires guard args", null)
            return false
        }
        val decision = guardDecision(storedBoundProfileId, g)
        if (decision != "allowed") {
            result.success(decision)
            return false
        }
        if (!isAvailable()) {
            result.success("unavailable")
            return false
        }
        return true
    }

    // Puts one Health Connect permission request in front of the person.
    // Shared by the write path's request and the import's (issue #1515) so
    // the two cannot drift on the one-prompt-at-a-time rule or on
    // remembering before launching; they differ only in which permissions
    // they ask for and which asked-marker they set. Call only after
    // [requestGuardAllows].
    private fun launchPermissionRequest(
        result: MethodChannel.Result,
        askedMarker: String,
        permissions: Set<String>,
    ) {
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
            // Issue #1478: remember that this install has put the
            // request in front of the person, BEFORE launching it —
            // the status reports "notAsked" only until this is set,
            // and a request that is interrupted (the process dies
            // behind the sheet) has still been asked.
            prefs.edit().putLong(askedMarker, installStamp).apply()
            launcher.launch(permissions)
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

    // Issue #458/#992: the read/import half. One call returns ONE page, then
    // an opaque cursor for the next. The first pass of a profile with no
    // stored change token is a full-range read from epoch, paged by Health
    // Connect's ReadRecordsResponse.pageToken; once that completes a change
    // token is minted so later passes are incremental through the Changes
    // API, itself paged by ChangesResponse.nextChangesToken. An expired
    // change token (connect-client 1.1.0 surfaces this as
    // ChangesResponse.changesTokenExpired, not a thrown exception) is
    // cleared and recovered with a fresh full-range read rather than failing
    // the pass. Records this app itself wrote are dropped by dataOrigin — the
    // mandatory loop-breaker. A malformed cursor starts over from the
    // beginning rather than failing (Dart's own repeated-cursor guard would
    // otherwise have nothing to compare).
    private suspend fun readSamples(
        client: HealthConnectClient,
        profileId: String,
        startMs: Long,
        endMs: Long,
        pageSize: Int,
        cursor: String?,
    ): Map<String, Any> {
        val decoded = cursor?.let { HealthImportCursor.decode(it) }
        // A stored change token means an incremental pass: the first page
        // (no cursor) uses it, and every later changes page carries its own
        // next token in the cursor.
        val changesMode = if (decoded != null) {
            HealthImportCursor.isChanges(decoded.mode)
        } else {
            prefs.getString(changesTokenKey(profileId), null) != null
        }
        if (changesMode) {
            val token = decoded?.token
                ?: prefs.getString(changesTokenKey(profileId), null)
            if (token != null) {
                val page = client.getChanges(token)
                if (page.changesTokenExpired) {
                    // Health Connect tokens expire after 30 days: clear the
                    // stale anchor and recover with the same full-range read
                    // a first import uses, rather than failing the pass.
                    prefs.edit().remove(changesTokenKey(profileId)).apply()
                    return readRangePage(
                        client, profileId, startMs, endMs, pageSize,
                        HealthImportCursor.FLOW, null)
                }
                return changesPage(client, profileId, page, startMs, endMs)
            }
        }
        val mode = decoded?.mode ?: HealthImportCursor.FLOW
        return readRangePage(
            client, profileId, startMs, endMs, pageSize, mode, decoded?.token)
    }

    // One page of the Changes API (an incremental pass), filtered to the
    // requested window and this app's own writes. A `hasMore` page carries
    // its next token; the final page stores that token (or mints one) as the
    // anchor for the NEXT pass.
    private suspend fun changesPage(
        client: HealthConnectClient,
        profileId: String,
        page: ChangesResponse,
        startMs: Long,
        endMs: Long,
    ): Map<String, Any> {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val records = LinkedHashMap<String, Record>()
        for (change in page.changes) {
            if (change is UpsertionChange) {
                records[change.record.metadata.id] = change.record
            }
        }
        val payload = mutableMapOf<String, Any>(
            "samples" to records.values.mapNotNull { sampleFor(it, start, end) },
        )
        val next = page.nextChangesToken
        if (page.hasMore && next.isNotEmpty()) {
            payload["nextCursor"] = HealthImportCursor.changes(next)
        } else if (next.isNotEmpty()) {
            // Last changes page: continue from the page's own next token on
            // the NEXT pass. Best-effort: a token-write failure must not fail
            // a pass that already read its data.
            prefs.edit().putString(changesTokenKey(profileId), next).apply()
        } else {
            // No next token at all: mint a fresh "now" anchor, best effort.
            mintChangesToken(client)?.let {
                prefs.edit().putString(changesTokenKey(profileId), it).apply()
            }
        }
        return payload
    }

    // One page of a full time-range read for one record type. The cursor's
    // mode says which type this page belongs to and carries that type's
    // pageToken; when the flow type is exhausted the next cursor starts the
    // intermenstrual-bleeding type, and when that is exhausted the page
    // carries no cursor at all (the Dart loop's termination condition) and a
    // fresh change token is minted for the next incremental pass.
    private suspend fun readRangePage(
        client: HealthConnectClient,
        profileId: String,
        startMs: Long,
        endMs: Long,
        pageSize: Int,
        mode: String,
        token: String?,
    ): Map<String, Any> {
        val start = Instant.ofEpochMilli(startMs)
        val end = Instant.ofEpochMilli(endMs)
        val filter = TimeRangeFilter.between(start, end)
        if (HealthImportCursor.isFlow(mode)) {
            val response = client.readRecords(
                ReadRecordsRequest(
                    MenstruationFlowRecord::class,
                    filter,
                    pageSize = pageSize,
                    pageToken = token,
                ))
            val payload = mutableMapOf<String, Any>(
                "samples" to response.records.mapNotNull {
                    sampleFor(it, start, end)
                },
            )
            // Flow exhausted -> start the intermenstrual-bleeding type with
            // no token rather than ending the pass.
            payload["nextCursor"] = response.pageToken
                ?.let { HealthImportCursor.flow(it) }
                ?: HealthImportCursor.intermenstrual(null)
            return payload
        }
        // Intermenstrual-bleeding page (the second and final type).
        val response = client.readRecords(
            ReadRecordsRequest(
                IntermenstrualBleedingRecord::class,
                filter,
                pageSize = pageSize,
                pageToken = token,
            ))
        val payload = mutableMapOf<String, Any>(
            "samples" to response.records.mapNotNull { sampleFor(it, start, end) },
        )
        if (response.pageToken != null) {
            payload["nextCursor"] = HealthImportCursor.intermenstrual(
                response.pageToken)
        } else {
            // Both types exhausted: this pass is done, and the next pass
            // should be incremental. Mint a "now" anchor, best effort.
            val next = mintChangesToken(client)
            if (next != null) {
                prefs.edit()
                    .putString(changesTokenKey(profileId), next)
                    .apply()
            }
        }
        return payload
    }

    private suspend fun mintChangesToken(
        client: HealthConnectClient,
    ): String? = try {
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

    // Issue #993: the companion is internal (not private) so the
    // background-import worker can name the same prefs file, binding key,
    // and channel rather than re-typing them — the mirror and the channel
    // are the two seams the worker reads and fires through. Issue #1211
    // adds the one Health Connect query the worker's tick needs to the
    // same seam, so the worker itself still holds no Health Connect types
    // (the guard test pins that).
    companion object {
        const val PREFS_FILE = "lunarlog_health"
        const val BOUND_PROFILE_KEY = "lunarlog.health.boundProfileId"
        const val CHANNEL_NAME = "lunarlog/health"

        // Issue #1478: set once this install has launched the Health
        // Connect permission request that carries the WRITE permissions,
        // or has seen a write granted (a read does not count since issue
        // #1515: the import's own sheet can grant one without ever showing
        // the writes). The value is the install's own
        // first-install time (see [installStamp]), so a copy of these prefs
        // on another install does not count and that install starts unasked,
        // exactly as Android's own permission state does. Lives in the same
        // device-local prefs file as the binding mirror. Not cleared on
        // unbind: it describes the OS permission for this install, not the
        // binding.
        const val PERMISSION_REQUESTED_KEY = "lunarlog.health.permissionRequested"

        // Issue #1515: set once this install has launched the import's own
        // request, which asks for the reads and no write permission.
        // Stamped like the marker above. It counts as "asked" for the read
        // side only — never for the writes, which that request does not
        // show.
        const val IMPORT_REQUEST_LAUNCHED_KEY = "lunarlog.health.importRequestLaunched"

        // Issue #1211: true exactly when a background pass would be
        // refused — the background-read feature is offered AND its
        // permission is not granted. Deliberately false (let the tick run
        // its usual path) in every can't-tell case: the feature absent
        // means background reads were never permission-gated, so the
        // pre-#1211 behavior stands; the SDK unavailable means Dart's own
        // probe (`importPermissionStatus`, issue #1491) answers
        // "unavailable" and no-ops anyway; and a query failure must not
        // invent a refusal. Kept here rather than in the worker so all
        // Health Connect access stays in the adapter.
        suspend fun backgroundReadRefused(context: Context): Boolean {
            return try {
                if (HealthConnectClient.getSdkStatus(context) !=
                    HealthConnectClient.SDK_AVAILABLE
                ) {
                    return false
                }
                val client = HealthConnectClient.getOrCreate(context)
                val featureOffered = client.features.getFeatureStatus(
                    HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
                ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
                featureOffered && !client.permissionController
                    .getGrantedPermissions()
                    .contains(
                        HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND,
                    )
            } catch (_: Exception) {
                false
            }
        }

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

/**
 * The permission-status decisions (Issue #959, reworked by Issues #1478 and
 * #1515), as pure functions of the facts the adapter gathers so they are
 * unit-testable on the JVM without a Health Connect client (the same reason
 * [HealthImportCursor] holds no Health Connect types).
 *
 * There is one decision, [statusFor], asked once for each direction over
 * that direction's own facts: [writeStatusFor] is `permissionStatus`, and
 * [importStatusFor] is `importPermissionStatus`.
 *
 * The wire strings are `HealthPermissionStatus`'s, defined in
 * `lib/domain/health/health_platform.dart`:
 *
 *  * `granted`  — every permission in `required` is granted;
 *  * `denied`   — something in `required` is missing AND the person has
 *                 been asked for it: either this install launched a request
 *                 that carries it (`everRequested`), or at least one
 *                 permission in `requested` is granted right now, which can
 *                 only follow a decision the person made on a screen that
 *                 offered `required` too;
 *  * `notAsked` — neither. The Dart write pass asks in exactly this state;
 *                 the screen says "not yet asked" rather than "denied".
 *
 * "Unavailable" is decided before this is reached (no Health Connect, or
 * the granted-permissions query failed).
 */
internal object HealthPermissionState {
    const val GRANTED = "granted"
    const val NOT_ASKED = "notAsked"
    const val DENIED = "denied"

    fun statusFor(
        granted: Set<String>,
        required: Set<String>,
        requested: Set<String>,
        everRequested: Boolean,
    ): String = when {
        granted.containsAll(required) -> GRANTED
        everRequested || provesAsked(granted, requested) -> DENIED
        else -> NOT_ASKED
    }

    /**
     * Whether what is granted shows the person has been asked: at least one
     * permission in `requested` is granted. The adapter remembers this as
     * soon as it sees it (the review of Issue #1478), so that access which
     * is later removed altogether still reads `denied`, never `notAsked`.
     */
    fun provesAsked(granted: Set<String>, requested: Set<String>): Boolean =
        granted.any { it in requested }

    /**
     * The `permissionStatus` decision: may lunarlog write?
     *
     * Everything about it is decided on the WRITE permissions (Issue #1515).
     * `granted` needs every one of them and no read (Issue #1478). And
     * "asked" means asked for the writes: `writesEverRequested` is the
     * marker of the request that carries them, and the only grant that
     * proves the question was put is a write grant.
     *
     * A granted read used to prove it too, which was true while one request
     * carried everything. It is not now that the import asks for the reads
     * alone: someone who tapped Import and allowed the reads has never been
     * shown a write permission. Answering `denied` for her would stop the
     * Dart write pass before its own request, so the write path could never
     * ask — the same trap `notAsked` was introduced to close.
     */
    fun writeStatusFor(
        granted: Set<String>,
        writes: Set<String>,
        writesEverRequested: Boolean,
    ): String = statusFor(
        granted = granted,
        required = writes,
        requested = writes,
        everRequested = writesEverRequested,
    )

    /**
     * The `importPermissionStatus` decision (Issue #1491): may the import
     * read? It is the gate of the Dart background import pass, which stops
     * silently on anything but `granted`.
     *
     *  * `granted`  — every permission in `importReads` is granted: the two
     *                 record reads the import performs (menstruation and
     *                 intermenstrual bleeding). No write permission counts
     *                 either way, and neither does "access past data" nor
     *                 the background read — the adapter passes neither in.
     *  * `denied` / `notAsked` — a read is missing; told apart by the same
     *                 rule [statusFor] applies to the writes, over the read
     *                 side's own facts. Every request carries the reads, so
     *                 here `requested` is everything the app requests and
     *                 `everRequested` is "either request was launched"
     *                 (Issue #1515). The two statuses can therefore differ
     *                 in one direction only: asked for the reads and not
     *                 yet for the writes, never the reverse.
     *
     * The adapter reads its asked-markers for `everRequested` here but never
     * sets one on this path: asking this question must not change what
     * `permissionStatus` answers for the write path.
     */
    fun importStatusFor(
        granted: Set<String>,
        importReads: Set<String>,
        requested: Set<String>,
        everRequested: Boolean,
    ): String = statusFor(
        granted = granted,
        required = importReads,
        requested = requested,
        everRequested = everRequested,
    )

    /**
     * Whether a tap of Import has anything to ask for (Issue #1515): only
     * when the import cannot read, that is when one of the record reads in
     * `importReads` is not granted. It is the complement of
     * [importStatusFor]'s `granted`.
     *
     * With both record reads granted the import needs nothing more, so
     * nothing is asked — not even the two optional extras ("access past
     * data", background access) that ride the import's sheet when it is
     * raised. Someone who left an extra off made that choice on the sheet
     * that offered it; putting it in front of her again on every tap of
     * Import is the same nagging this issue removed for the writes. The
     * extras stay on the sheet whenever a record read is being asked for,
     * and can be switched on in Health Connect at any time.
     */
    fun importMustAsk(granted: Set<String>, importReads: Set<String>): Boolean =
        !granted.containsAll(importReads)
}

/**
 * The opaque paging cursor codec for the #992 full-history read.
 *
 * A cursor is `<mode>:<base64url token>`, where the mode names which stage
 * of the read the token belongs to:
 *
 *  * `flow` — a full-range `readRecords` page for `MenstruationFlowRecord`;
 *  * `ib`   — a full-range `readRecords` page for
 *               `IntermenstrualBleedingRecord`;
 *  * `chg`  — a `getChanges` page (the incremental pass).
 *
 * The flow stage's final page emits an `ib:` cursor (empty token) so the
 * read moves on to the second record type; the ib stage's final page emits
 * no cursor at all, which is the Dart loop's termination condition. Dart
 * never parses this — it only compares cursors for equality to prove
 * progress — so the format is free to change here, but a repeated cursor or
 * a malformed one must never trap the loop. Deliberately free of Health
 * Connect types (only `Base64` and strings) so it is unit-testable on the
 * JVM, mirroring the Swift `cursorString`/`decodeCursorData` pair.
 */
internal object HealthImportCursor {
    const val FLOW = "flow"
    const val INTERMENSTRUAL = "ib"
    const val CHANGES = "chg"

    private const val SEPARATOR = ':'

    class Decoded(val mode: String, val token: String?)

    fun flow(token: String?): String = encode(FLOW, token)
    fun intermenstrual(token: String?): String = encode(INTERMENSTRUAL, token)
    fun changes(token: String): String = encode(CHANGES, token)

    fun isFlow(mode: String): Boolean = mode == FLOW
    fun isIntermenstrual(mode: String): Boolean = mode == INTERMENSTRUAL
    fun isChanges(mode: String): Boolean = mode == CHANGES

    private fun encode(mode: String, token: String?): String {
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString((token ?: "").toByteArray(Charsets.UTF_8))
        return mode + SEPARATOR + payload
    }

    /** Decodes a cursor; null for anything malformed or an unknown mode. */
    fun decode(cursor: String): Decoded? {
        val index = cursor.indexOf(SEPARATOR)
        if (index <= 0) return null
        val mode = cursor.substring(0, index)
        if (!isFlow(mode) && !isIntermenstrual(mode) && !isChanges(mode)) {
            return null
        }
        val payload = cursor.substring(index + 1)
        if (payload.isEmpty()) return Decoded(mode, null)
        val token = try {
            String(Base64.getUrlDecoder().decode(payload), Charsets.UTF_8)
        } catch (e: IllegalArgumentException) {
            return null
        }
        return Decoded(mode, token.ifEmpty { null })
    }
}
