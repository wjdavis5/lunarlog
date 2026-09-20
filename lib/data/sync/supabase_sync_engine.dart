/// The sync loop, trigger gating and transport coordination (U5; KTD1,
/// KTD2, KTD4, KTD10, KTD11): pushes dirty rows through `sync_push` in
/// batches, pulls remote pages per table by `server_version`, reconciles
/// fully on bind / daily, and enforces the device binding guard with a
/// non-destructive mismatch state.
///
/// Issue #42: the *scheduled* daily reconcile probes the server's
/// per-table `max(server_version)` first ([_serverUnchangedSinceCursors])
/// and skips the full re-pull when nothing changed since the incremental
/// cursors; forced and bind-time reconciles always re-pull, and any probe
/// failure falls back to the full re-pull.
///
/// Issue #525: a push batch's `resolved` rows are no longer, on their own,
/// a reason to run a full reconcile — [SupabaseSyncApply.applyPushResult]
/// already applies every resolved row as the correct per-row response
/// (atomically, since issue #523), so forcing an 8-table-plus reconcile on
/// top of that was pure overhead with no correctness benefit.
///
/// The apply half of the same cycle — recording rejections, clearing
/// `dirty` on accepted rows, storing the server's `resolved` copies and
/// applying reconcile pages — lives in `supabase_sync_apply.dart`
/// ([SupabaseSyncApply], split out verbatim under issue #435); this file
/// keeps the loop, the triggers and every transport call.
///
/// Triggers (AS8): the gate `Listenable` (edge-detected unlock), auth state
/// transitions, app resume, a debounced local-write signal (drift table
/// updates on the two synced tables) and a periodic timer. Every trigger
/// funnels into [requestSync], which coalesces while a cycle runs (at most
/// one queued re-run).
///
/// Gating (KTD10): a cycle runs only while the gate is unlocked, the session
/// is `signedIn` and the database is bound to that session's account. A
/// lock between batches or pages parks the engine in `paused`; unlock
/// requests a sync. `expired` yields `error(auth)` and never blocks local
/// use (AE9).
///
/// Collaborators are injected (transport, auth, gate signal, clock, timer
/// factories, backoff) so the engine is testable against fakes with no
/// real time and no Supabase. The gate arrives as a bare `Listenable` plus
/// an `unlocked` probe, which keeps `lib/data` free of `app_lifecycle.dart`.
///
/// Nothing logged or emitted here carries health content: ids, counts,
/// phases and error *kinds* only (R18).
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery, Value;
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

import '../../domain/auth/auth_service.dart';
import '../../domain/sync/sync_engine.dart';
import '../db/db.dart';
import '../db/storage.dart';
import '../db/ulid.dart';
import 'row_codec.dart';
import 'supabase_sync_apply.dart';
import 'sync_transport.dart';

/// Builds a one-shot timer; the default is `Timer(delay, callback)`.
typedef SyncTimerFactory = Timer Function(
    Duration delay, void Function() callback);

/// Delay before the next attempt after [consecutiveFailures] network
/// failures in a row.
typedef SyncBackoff = Duration Function(int consecutiveFailures);

Timer defaultSyncTimerFactory(Duration delay, void Function() callback) =>
    Timer(delay, callback);

Timer defaultSyncPeriodicTimerFactory(
        Duration period, void Function() callback) =>
    Timer.periodic(period, (_) => callback());

const Duration kSyncPeriodicInterval = Duration(minutes: 15);
const Duration kSyncBackoffBase = Duration(seconds: 30);
const Duration kSyncBackoffCap = Duration(minutes: 10);

/// How stale the last full reconciliation may be before another is due
/// (KTD2).
const Duration kSyncFullPullInterval = Duration(hours: 24);

/// Issue #842: the minimum age of the last successful cycle for a
/// *lifecycle-triggered* sync (app resume, gate unlock) to be skipped. A
/// resume that lands within this window, with nothing dirty locally and
/// Realtime actually subscribed, is almost always redundant — Realtime
/// already delivers the "something changed" signal, and a cycle costs 13+
/// HTTP requests even when every page comes back empty. The skip never
/// applies to a user-initiated [SyncEngine.requestSync], to a cycle with
/// dirty rows, or when Realtime is down (then the pull is the only signal).
const Duration kLifecycleSyncMinInterval = Duration(seconds: 60);

/// Maximum consecutive sync cycles that may retry reconciliation due to
/// un-appliable remote rows before advancing lastFullPullAt to avoid an
/// unbounded reconcile loop. Also bounds [_consecutiveGuardianPullRetries]
/// (finding #4), a separate un-appliable-row loop with the same shape in
/// [SupabaseSyncEngine._pullIncremental].
const int kMaxConsecutiveReconcileRetries = 3;

/// Issue #521: the incremental pull cursor is a value from the global
/// `sync_version_seq`, assigned to a row *before* it commits — so `nextval`
/// order is not commit order. Two writers (two guardians sharing a profile
/// hold different advisory locks; several server-side paths take none at
/// all) can commit out of that order, and the naive `cursor =
/// max(page.server_version)` then skips whichever commit lands second: the
/// device advances its cursor past a version another transaction is still
/// in the middle of writing, and that row is never seen again until the
/// next full reconcile (up to [kSyncFullPullInterval] later).
///
/// [SupabaseSyncEngine._pullTable] prefers a server-computed commit-safe
/// watermark ([SyncTransport.fetchWatermark]) to clamp the new cursor.
/// When that RPC is not available yet (a server predating its migration),
/// this constant is the fallback instead: the new cursor is
/// `max(page.server_version) - kCursorLookback`, never advancing past a
/// point this many versions behind the page's own maximum. Fifty is a
/// generous margin for the concurrency this app actually has (at most a
/// handful of guardians writing one profile at once) while staying cheap —
/// every remote apply is LWW-idempotent (an already-applied row re-arrives
/// on the next page and re-applies as a no-op, or correctly overwrites, but
/// is never applied wrongly), so re-fetching a small band of already-seen
/// versions costs a little duplicate work, never correctness.
const int kCursorLookback = 50;

/// Issue #566: the weight a fresh clock-offset sample carries against the
/// previously smoothed value (a simple exponential moving average — `next =
/// previous + alpha * (sample - previous)`). `serverNow - deviceNow` is
/// measured once per push batch (see [SupabaseSyncEngine._pushBatch]'s
/// `sentAt`), and a single sample can be noisy — a slow or congested
/// request inflates the apparent one-way trip, and `serverNow` is the
/// transaction-start instant of a batch that may still be writing up to
/// [PushBatch.maxRows] rows per table when it stamps that instant. `0.2`
/// reacts within a handful of pushes (a real clock skew shows up quickly)
/// while damping any one sample's noise rather than snapping the whole
/// storage clock to it. `1.0` would disable smoothing entirely (every
/// sample replaces the previous one outright, the pre-#566 behavior).
const double kClockOffsetSmoothingAlpha = 0.2;

/// The pull table order [SupabaseSyncEngine._pullIncremental],
/// [SupabaseSyncEngine._reconcile], and (issue #42) the pre-reconcile
/// version probe all share. Profiles first (everything else references
/// one); day entries, then observations (an observation references a day
/// entry, which references a profile — both must already be applied for
/// the referential check to succeed without a retry); the two mode tables
/// and two care tables after every content table (both reference only a
/// profile); merge events after the care tables (issue #130: a row
/// references only a profile, already applied by the time its turn
/// comes); the tag registry after merge events (issue #257: same —
/// references only a profile, and nothing references it; a day entry's
/// tag referencing a registry code that has not arrived yet degrades to
/// raw-text rendering by design, so there is no ordering requirement
/// either); deletedProfiles last (issue #522: it only ever tombstones a
/// profile — and cascades the wipe — that this same cycle may have just
/// pulled fresh content for above; running it last means the deletion
/// always wins).
const List<SyncTable> _pullTableOrder = [
  SyncTable.profiles,
  SyncTable.profileGuardians,
  SyncTable.dayEntries,
  SyncTable.observations,
  SyncTable.profileModes,
  SyncTable.cycleOverrides,
  SyncTable.careNotes,
  SyncTable.visitPrepItems,
  // Issue #801: guardian notes follow the care tables (a row references
  // only a profile, already applied by the time its turn comes). This
  // table pages via the per-table select fallback (it is deliberately not
  // in [_pullRpcTables]), exactly like deletedProfiles.
  SyncTable.guardianNotes,
  // Issue #130: merge events follow the care tables — a row references
  // only a profile (already applied by the time its turn comes).
  SyncTable.dayEntryMergeEvents,
  // Issue #257: the tag registry follows merge events — a row references
  // only a profile, and nothing references the registry (unknown codes
  // never drop).
  SyncTable.profileTagRegistry,
  // Issue #170: the change-history feed follows the registry — a row
  // references only a profile (the entry_id reference is deliberately not
  // an FK locally, see the domain model), and rows are immutable, so no
  // ordering requirement exists.
  SyncTable.dayEntryHistory,
  SyncTable.deletedProfiles,
];

final Random _jitter = Random();

/// Exponential backoff with up to 25% jitter, capped at ten minutes:
/// 30s, 60s, 2m, 4m, 8m, 10m, 10m, ... (before jitter).
Duration defaultSyncBackoff(int consecutiveFailures) {
  final exponent = max(0, consecutiveFailures - 1).clamp(0, 16);
  final baseMs = kSyncBackoffBase.inMilliseconds * (1 << exponent);
  final cappedMs = min(baseMs, kSyncBackoffCap.inMilliseconds);
  final jittered = cappedMs + (cappedMs * 0.25 * _jitter.nextDouble()).round();
  return Duration(milliseconds: min(jittered, kSyncBackoffCap.inMilliseconds));
}

/// Thrown inside a cycle when the gate locked between two batches or pages.
class _SyncPaused implements Exception {
  const _SyncPaused();
}

/// Thrown inside a cycle when the session changed under it or the engine
/// was disposed; the cycle ends quietly.
class _SyncAborted implements Exception {
  const _SyncAborted();
}

/// Keyset cursor state for one [SupabaseSyncEngine._push] call, split out
/// so [SupabaseSyncEngine._readPushRound] stays small. `readProfilePage`
/// is always a live read with no cached "done" flag (finding #1) —
/// `entriesDone` only latches for day entries, whose own read is gated by
/// the caller once a page comes back short.
class _PushCursor {
  _PushCursor(this._storage, this.batchSize);

  final LunarLogStorage _storage;
  final int batchSize;

  String? _profileCursor;
  String? _entryCursor;
  String? _observationCursor;
  String? _profileModeCursor;
  String? _cycleOverrideCursor;
  String? _careNoteCursor;
  String? _guardianNoteCursor;
  String? _visitPrepItemCursor;
  String? _mergeEventCursor;
  String? _tagRegistryCursor;
  bool entriesDone = false;
  bool observationsDone = false;
  bool profileModesDone = false;
  bool cycleOverridesDone = false;
  bool careNotesDone = false;
  bool guardianNotesDone = false;
  bool visitPrepItemsDone = false;
  bool mergeEventsDone = false;
  bool tagRegistryDone = false;

  Future<List<Profile>> readProfilePage() async {
    final page = await _storage.readDirtyProfiles(
        limit: batchSize, afterId: _profileCursor);
    if (page.isNotEmpty) _profileCursor = page.last.id;
    return page;
  }

  Future<List<DayEntry>> readEntryPage() async {
    final page = await _storage.readDirtyDayEntries(
        limit: batchSize, afterId: _entryCursor);
    entriesDone = page.length < batchSize;
    if (page.isNotEmpty) _entryCursor = page.last.id;
    return page;
  }

  /// Issue #240: same keyset-paging contract as [readEntryPage].
  Future<List<Observation>> readObservationPage() async {
    final page = await _storage.readDirtyObservations(
        limit: batchSize, afterId: _observationCursor);
    observationsDone = page.length < batchSize;
    if (page.isNotEmpty) _observationCursor = page.last.id;
    return page;
  }

  /// Issue #188: same keyset-paging contract as [readEntryPage], keyed by
  /// profile id (the table's primary key).
  Future<List<ProfileModeData>> readProfileModePage() async {
    final page = await _storage.readDirtyProfileModes(
        limit: batchSize, afterId: _profileModeCursor);
    profileModesDone = page.length < batchSize;
    if (page.isNotEmpty) _profileModeCursor = page.last.profileId;
    return page;
  }

  /// Issue #188: same keyset-paging contract as [readEntryPage].
  Future<List<CycleOverrideData>> readCycleOverridePage() async {
    final page = await _storage.readDirtyCycleOverrides(
        limit: batchSize, afterId: _cycleOverrideCursor);
    cycleOverridesDone = page.length < batchSize;
    if (page.isNotEmpty) _cycleOverrideCursor = page.last.id;
    return page;
  }

  /// Issue #128: same keyset-paging contract as [readEntryPage].
  Future<List<CareNoteData>> readCareNotePage() async {
    final page = await _storage.readDirtyCareNotes(
        limit: batchSize, afterId: _careNoteCursor);
    careNotesDone = page.length < batchSize;
    if (page.isNotEmpty) _careNoteCursor = page.last.id;
    return page;
  }

  /// Issue #128: same keyset-paging contract as [readEntryPage].
  Future<List<VisitPrepItemData>> readVisitPrepItemPage() async {
    final page = await _storage.readDirtyVisitPrepItems(
        limit: batchSize, afterId: _visitPrepItemCursor);
    visitPrepItemsDone = page.length < batchSize;
    if (page.isNotEmpty) _visitPrepItemCursor = page.last.id;
    return page;
  }

  /// Issue #801: same keyset-paging contract as [readEntryPage].
  Future<List<GuardianNoteData>> readGuardianNotePage() async {
    final page = await _storage.readDirtyGuardianNotes(
        limit: batchSize, afterId: _guardianNoteCursor);
    guardianNotesDone = page.length < batchSize;
    if (page.isNotEmpty) _guardianNoteCursor = page.last.id;
    return page;
  }

  /// Issue #130: same keyset-paging contract as [readEntryPage].
  Future<List<DayEntryMergeEventData>> readMergeEventPage() async {
    final page = await _storage.readDirtyDayEntryMergeEvents(
        limit: batchSize, afterId: _mergeEventCursor);
    mergeEventsDone = page.length < batchSize;
    if (page.isNotEmpty) _mergeEventCursor = page.last.id;
    return page;
  }

  /// Issue #257: same keyset-paging contract as [readEntryPage].
  Future<List<ProfileTagRegistryEntry>> readTagRegistryPage() async {
    final page = await _storage.readDirtyProfileTagRegistry(
        limit: batchSize, afterId: _tagRegistryCursor);
    tagRegistryDone = page.length < batchSize;
    if (page.isNotEmpty) _tagRegistryCursor = page.last.id;
    return page;
  }

  /// Whether every child table's keyset scan is exhausted (the `done` half
  /// of [_readPushRound]'s contract, split out so that method's branch
  /// count stays under the CRAP gate as tables are added).
  bool get allTablesDone =>
      entriesDone &&
      observationsDone &&
      profileModesDone &&
      cycleOverridesDone &&
      careNotesDone &&
      guardianNotesDone &&
      visitPrepItemsDone &&
      mergeEventsDone &&
      tagRegistryDone;
}

class SupabaseSyncEngine with WidgetsBindingObserver implements SyncEngine {
  SupabaseSyncEngine({
    required LunarLogStorage storage,
    required SyncTransport transport,
    required AuthService auth,
    required Listenable gate,
    required bool Function() gateUnlocked,
    DateTime Function()? clock,
    SyncTimerFactory timerFactory = defaultSyncTimerFactory,
    SyncTimerFactory periodicTimerFactory = defaultSyncPeriodicTimerFactory,
    Duration periodicInterval = kSyncPeriodicInterval,
    SyncBackoff backoff = defaultSyncBackoff,
    int batchSize = PushBatch.maxRows,
    int pageSize = 500,
    this.writeDebounce = const Duration(milliseconds: 250),
    UlidGenerator? ulid,
    SupabaseSyncApply? apply,
    bool Function()? realtimeSubscribed,
  })  : _storage = storage,
        _transport = transport,
        _auth = auth,
        _gate = gate,
        _gateUnlocked = gateUnlocked,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _timerFactory = timerFactory,
        _periodicTimerFactory = periodicTimerFactory,
        _periodicInterval = periodicInterval,
        _backoff = backoff,
        _batchSize = batchSize,
        _pageSize = pageSize,
        _apply = apply ?? SupabaseSyncApply(storage),
        // Issue #842: nullable Realtime liveness probe. A null probe reports
        // "not subscribed", which is the safe default — it disables the
        // lifecycle skip entirely so a build that never wires one behaves
        // exactly as before. (The file-level ignore covers the named
        // parameter.)
        _realtimeSubscribed = realtimeSubscribed,
        _ulid = ulid ?? UlidGenerator() {
    if (batchSize < 1 || batchSize > PushBatch.maxRows) {
      throw ArgumentError.value(
          batchSize, 'batchSize', 'must be 1..${PushBatch.maxRows}');
    }
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be at least 1');
    }
  }

  final LunarLogStorage _storage;
  final SyncTransport _transport;
  final AuthService _auth;
  final Listenable _gate;
  final bool Function() _gateUnlocked;
  final DateTime Function() _clock;
  final SyncTimerFactory _timerFactory;
  final SyncTimerFactory _periodicTimerFactory;
  final Duration _periodicInterval;
  final SyncBackoff _backoff;
  final int _batchSize;
  final int _pageSize;
  final SupabaseSyncApply _apply;
  final UlidGenerator _ulid;

  /// Issue #842: whether Realtime currently has a live subscription that can
  /// deliver remote-change signals. Null means "not subscribed" (see the
  /// constructor comment), so the lifecycle skip is off unless a probe is
  /// wired. The realtime coordinator is built *after* the engine (it needs
  /// the engine), so production wires this through
  /// [attachRealtimeSubscribedProbe] rather than the constructor.
  bool Function()? _realtimeSubscribed;

  /// Issue #842: attaches (or replaces) the Realtime liveness probe. The
  /// composition root calls this right after building the coordinator, with
  /// `() => coordinator.isSubscribed`.
  void attachRealtimeSubscribedProbe(bool Function() probe) {
    _realtimeSubscribed = probe;
  }

  /// Quiet time after the last local write before a sync is requested.
  @visibleForTesting
  final Duration writeDebounce;

  final StreamController<SyncSnapshot> _snapshots =
      StreamController<SyncSnapshot>.broadcast();
  SyncSnapshot _snapshot = SyncSnapshot.initial;

  bool _started = false;
  bool _disposed = false;
  bool _running = false;
  bool _queued = false;
  Completer<void>? _loopDone;
  bool _lastGateUnlocked = true;
  bool _offsetRestored = false;
  bool _restoring = false;
  bool _writeDuringCycle = false;
  int _consecutiveNetworkFailures = 0;
  int _consecutiveReconcileRetries = 0;

  /// Issue #566: the EMA-smoothed clock offset, seeded from the persisted
  /// value on the first cycle ([_restoreOffset]) so smoothing continues
  /// across app restarts instead of re-learning from a single fresh sample
  /// every launch. `null` only before any sample has ever been taken (a
  /// brand-new device, never yet synced) or restored.
  Duration? _smoothedOffset;

  /// Consecutive cycles in a row where a profileGuardians page hit a
  /// [RetryableSyncApplyError] (finding #4): bounds the `cursorProfiles`
  /// rewind in [_pullIncremental] the same way [_consecutiveReconcileRetries]
  /// bounds the reconcile path, so one permanently unresolvable row (an
  /// accepted membership whose profile never arrives — the only case left
  /// after finding #8) cannot force a full profile re-pull every cycle
  /// forever.
  int _consecutiveGuardianPullRetries = 0;

  StreamSubscription<AuthSessionState>? _authSub;
  StreamSubscription<Set<TableUpdate>>? _writeSub;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  Timer? _backoffTimer;

  @override
  SyncSnapshot get snapshot => _snapshot;

  @override
  Stream<SyncSnapshot> get snapshots => _snapshots.stream;

  @override
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _lastGateUnlocked = _gateUnlocked();
    _gate.addListener(_onGateChanged);
    _authSub = _auth.states.listen((_) => requestSync());
    final db = _storage.db;
    _writeSub = db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.profiles,
          db.dayEntries,
          db.observations,
          db.profileModes,
          db.cycleOverrides,
          db.careNotes,
          db.guardianNotes,
          db.visitPrepItems,
          db.dayEntryMergeEvents,
          db.profileTagRegistry,
        ]))
        .listen((_) => _onLocalWrite());
    _periodicTimer = _periodicTimerFactory(_periodicInterval, () {
      _apply.clearRejected();
      requestSync();
    });
    requestSync();
  }

  /// Issue #842: (re)starts the 15-minute periodic sync timer. Idempotent —
  /// a resume while the timer is already armed does nothing, and a resume
  /// before [start]/after [dispose] never creates one.
  void _startPeriodicTimer() {
    if (_disposed || !_started || _periodicTimer != null) return;
    _periodicTimer = _periodicTimerFactory(_periodicInterval, () {
      _apply.clearRejected();
      requestSync();
    });
  }

  /// Issue #842: cancels the periodic sync timer while backgrounded. The
  /// engine keeps its local-write/realtime triggers; only the timer stops.
  void _stopPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  bool _forceFullReconcile = false;

  @override
  void requestSync() {
    if (_disposed || !_started) return;
    if (_running) {
      _queued = true;
      return;
    }
    _loopDone = Completer<void>();
    unawaited(_runLoop());
  }

  @override
  void triggerFullReconcile() {
    _forceFullReconcile = true;
    requestSync();
  }

  /// Completes when no cycle is running (test seam; also handy for a
  /// "Sync now" control that wants to await the outcome).
  @visibleForTesting
  Future<void> flush() async {
    while (_running) {
      await _loopDone!.future;
    }
  }

  @override
  Future<void> confirmUpload() async {
    if (_disposed || _snapshot.phase != SyncPhase.awaitingUploadConsent) {
      return;
    }
    final uid = _confirmedUid();
    if (uid == null) return;
    final state = await _storage.readSyncState();
    if (state.boundUserId != null) return;
    await _storage.markAllDirty();
    await _bind(state, uid);
    requestSync();
  }

  @override
  Future<void> retryRejected() async {
    if (_disposed) return;
    await _apply.retryRejected();
    _emit(_snapshot.copyWith(rejectedCount: _apply.rejectedCount));
    requestSync();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    _backoffTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer = null;
    _backoffTimer = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _gate.removeListener(_onGateChanged);
    }
    await _authSub?.cancel();
    await _writeSub?.cancel();
    _authSub = null;
    _writeSub = null;
    if (_running) await _loopDone?.future;
    await _snapshots.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Issue #842: restore the periodic timer, then request a sync
        // through the lifecycle gate (which may skip it).
        _startPeriodicTimer();
        _requestLifecycleSync();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Issue #842: the screen is off / the app is in the background; stop
        // the 15-minute timer so a backgrounded Android process does not
        // keep waking the radio. `inactive` is deliberately ignored — it is
        // a transient pre-`paused` state (a system dialog, the app switcher)
        // and cancelling the timer on it would churn on every notification.
        _stopPeriodicTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Issue #842: a sync requested by a lifecycle edge (resume or gate
  /// unlock). It is skipped only when all three hold: Realtime is
  /// subscribed, the last completed cycle was under
  /// [kLifecycleSyncMinInterval] ago, and nothing is dirty. Any one of them
  /// failing runs the sync. When no Realtime probe is wired (the default)
  /// the check is synchronous and falls straight through to
  /// [requestSync] — no behavior change.
  void _requestLifecycleSync() {
    if (_disposed || !_started) return;
    if (!(_realtimeSubscribed?.call() ?? false)) {
      requestSync();
      return;
    }
    unawaited(_skipOrRequestLifecycleSync());
  }

  Future<void> _skipOrRequestLifecycleSync() async {
    if (await _shouldSkipLifecycleSync()) return;
    requestSync();
  }

  /// The three-part skip predicate; see [_requestLifecycleSync].
  Future<bool> _shouldSkipLifecycleSync() async {
    final lastSyncAt = _snapshot.lastSyncAt;
    if (lastSyncAt == null) return false;
    if (_clock().toUtc().difference(lastSyncAt) >= kLifecycleSyncMinInterval) {
      return false;
    }
    // A rejected row counts as dirty here: erring toward syncing can only
    // cost a redundant cycle, never a lost write.
    return await _storage.dirtyCount() == 0;
  }

  // ---------------------------------------------------------------- triggers

  void _onGateChanged() {
    final unlocked = _gateUnlocked();
    if (unlocked == _lastGateUnlocked) return;
    _lastGateUnlocked = unlocked;
    if (unlocked) {
      // Issue #842: a gate unlock is a lifecycle edge like resume, so it
      // goes through the same skip predicate (and, when no Realtime probe is
      // wired, synchronously calls requestSync exactly as before).
      _requestLifecycleSync();
    } else if (!_running) {
      _emit(_snapshot.copyWith(phase: SyncPhase.paused));
    }
  }

  void _onLocalWrite() {
    if (_disposed) return;
    if (_running) {
      // The engine's own applies fire this too; the cycle end decides
      // whether anything pushable is left.
      _writeDuringCycle = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = _timerFactory(writeDebounce, () {
      _debounceTimer = null;
      unawaited(_afterWriteDebounce());
    });
  }

  Future<void> _afterWriteDebounce() async {
    if (_disposed) return;
    if (await _hasPushableDirty()) requestSync();
  }

  @visibleForTesting
  Future<bool> hasPushableDirtyForTest() => _hasPushableDirty();

  Future<bool> _hasPushable<T>({
    required Future<List<T>> Function({int? limit, String? afterId}) readPage,
    required String Function(T) id,
    required int Function(T) localRev,
  }) async {
    String? afterId;
    while (!_disposed) {
      final page = await readPage(limit: 1, afterId: afterId);
      if (page.isEmpty) return false;
      final row = page.first;
      if (_apply.pushable([row], id, localRev).isNotEmpty) {
        return true;
      }
      afterId = id(row);
    }
    return false;
  }

  /// Issue #257: the eleventh SyncTable pushed the old chain of nine
  /// identical `if (await _hasPushable(...)) return true;` blocks past
  /// the CRAP gate's complexity ceiling (each block's `return true`
  /// arm needed its own seeding test to cover), so the walk is now over
  /// this list — one closure per table, the same growth rationale as
  /// storage_local_writes' `_pushedTableTargets` and this file's own
  /// `_startingCursors`: a lookup stays flat as tables are added.
  late final List<Future<bool> Function()> _pushableDirtyReaders = [
    () => _hasPushable(
          readPage: _storage.readDirtyProfiles,
          id: (p) => p.id,
          localRev: (p) => p.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyDayEntries,
          id: (e) => e.id,
          localRev: (e) => e.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyObservations,
          id: (o) => o.id,
          localRev: (o) => o.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyProfileModes,
          id: (m) => m.profileId,
          localRev: (m) => m.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyCycleOverrides,
          id: (o) => o.id,
          localRev: (o) => o.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyCareNotes,
          id: (n) => n.id,
          localRev: (n) => n.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyVisitPrepItems,
          id: (i) => i.id,
          localRev: (i) => i.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyDayEntryMergeEvents,
          id: (e) => e.id,
          localRev: (e) => e.localRev,
        ),
    () => _hasPushable(
          readPage: _storage.readDirtyProfileTagRegistry,
          id: (e) => e.id,
          localRev: (e) => e.localRev,
        ),
  ];

  /// Whether any dirty row across every pushed table is currently
  /// pushable (not held out as rejected at its captured local_rev) —
  /// the re-queue decision at the end of a cycle.
  Future<bool> _hasPushableDirty() async {
    for (final reader in _pushableDirtyReaders) {
      if (await reader()) return true;
    }
    return false;
  }

  // ------------------------------------------------------------------- loop

  Future<void> _runLoop() async {
    _running = true;
    try {
      do {
        _queued = false;
        _writeDuringCycle = false;
        final completed = await _cycle();
        if (_disposed) break;
        if (completed && _writeDuringCycle && await _hasPushableDirty()) {
          _queued = true;
        }
      } while (_queued && !_disposed);
    } finally {
      _running = false;
      _loopDone?.complete();
    }
  }

  /// One cycle. Returns true when it ran to completion (idle), false when
  /// it was gated, paused, aborted or failed.
  ///
  /// Split into this orchestrator plus `_passesGateAndAuthChecks`/
  /// `_resolveBinding`/`_reconcileDueBeforePush`/`_reconcileIfDue`/
  /// `_logRetryIfNeeded`/`_syncErrorKindForTransportError` — same
  /// sequencing, same conditions, no behavior change; the try/catch shape
  /// (and its own decision points) stays here since that's the
  /// error-handling architecture, not extractable work.
  Future<bool> _cycle() async {
    try {
      if (!await _passesGateAndAuthChecks()) return false;

      final uid = _confirmedUid();
      var state = await _storage.readSyncState();
      _restoreOffset(state);
      if (uid == null) {
        _emit(_snapshot.copyWith(
            phase: SyncPhase.idle, boundUserId: state.boundUserId));
        return false;
      }

      final binding = await _resolveBinding(state, uid);
      if (binding == null) return false;
      state = binding.state;
      final bindNow = binding.bindNow;

      _emit(_snapshot.copyWith(
          phase: _phase(SyncPhase.pushing), boundUserId: uid));

      // Computed (and, when due, acted on by clearing the apply-side
      // rejections) before the
      // push so a previously-rejected row is retried once the reconcile
      // that follows re-evaluates it.
      final reconcileDue = _reconcileDueBeforePush(bindNow, state);

      await _push(uid);
      final pullRetry = await _pullIncremental(uid);
      state = await _storage.readSyncState();
      final reconcileRetry = await _reconcileIfDue(
        uid: uid,
        reconcileDueBeforePush: reconcileDue.due,
        scheduledOnly: reconcileDue.scheduledOnly,
      );
      _logRetryIfNeeded(pullRetry: pullRetry, reconcileRetry: reconcileRetry);

      final finishedAt = _clock().toUtc();
      await _updateState((s) => s.copyWith(
          lastSyncAt: Value(finishedAt), lastError: const Value(null)));
      _consecutiveNetworkFailures = 0;
      _backoffTimer?.cancel();
      _backoffTimer = null;
      _restoring = false;
      _emit(_snapshot.copyWith(
        phase: SyncPhase.idle,
        dirtyCount: await _storage.dirtyCount(),
        rejectedCount: _apply.rejectedCount,
        lastSyncAt: finishedAt,
        lastError: SyncErrorKind.none,
        boundUserId: uid,
      ));
      return true;
    } on _SyncPaused {
      _emit(_snapshot.copyWith(
          phase: SyncPhase.paused, dirtyCount: await _safeDirtyCount()));
      return false;
    } on _SyncAborted {
      if (!_disposed) {
        _emit(_snapshot.copyWith(
            phase: SyncPhase.idle, dirtyCount: await _safeDirtyCount()));
      }
      return false;
    } on SyncTransportError catch (error) {
      await _fail(_syncErrorKindForTransportError(error));
      return false;
    } catch (error) {
      debugPrint('lunarlog sync: cycle failed (${error.runtimeType})');
      await _fail(SyncErrorKind.other);
      return false;
    } finally {
      _restoring = false;
    }
  }

  /// The two early-out checks at the top of [_cycle]: the gate must be
  /// unlocked and the session must not be expired. Split out of [_cycle]
  /// verbatim.
  Future<bool> _passesGateAndAuthChecks() async {
    if (!_gateUnlocked()) {
      _emit(_snapshot.copyWith(phase: SyncPhase.paused));
      return false;
    }
    if (_auth.state == AuthSessionState.expired) {
      await _fail(SyncErrorKind.auth);
      return false;
    }
    return true;
  }

  /// [_cycle]'s bind/mismatch decision, split out verbatim. Returns the
  /// (possibly bound) state and whether binding happened just
  /// now, or `null` when [_cycle] should emit-and-return-false (already
  /// emitted by this method before returning null).
  Future<({SyncStateRow state, bool bindNow})?> _resolveBinding(
    SyncStateRow state,
    String uid,
  ) async {
    if (state.boundUserId == null) {
      if (await _storage.isEmpty()) {
        // The session may have vanished during the awaits above (a device
        // reset signs out while the fresh database opens): never bind an
        // empty database to an account that is no longer confirmed.
        _checkpoint(uid);
        final bound = await _bind(state, uid);
        _restoring = true;
        return (state: bound, bindNow: true);
      }
      _emit(_snapshot.copyWith(
          phase: SyncPhase.awaitingUploadConsent, boundUserId: null));
      return null;
    }
    if (state.boundUserId != uid) {
      _emit(_snapshot.copyWith(
          phase: SyncPhase.accountMismatch, boundUserId: state.boundUserId));
      return null;
    }
    return (state: state, bindNow: false);
  }

  /// Whether a full reconcile is due, based on state from *before* this
  /// cycle's push: a fresh bind, no prior full pull, or the last one is
  /// stale (KTD2). When due, also clears the apply-side rejections (a
  /// previously-rejected
  /// row is retried once the reconcile that follows re-evaluates it) —
  /// this must run before the push, so it lives here rather than in
  /// [_reconcileIfDue], which only sees post-push state.
  ///
  /// Issue #42: also reports whether the reconcile is due *only* by the
  /// 24h staleness window — the "scheduled daily reconcile" — as opposed
  /// to a forced reconcile, a fresh bind, or a first-ever pull. Only the
  /// scheduled kind may be skipped by [_serverUnchangedSinceCursors]'s
  /// version probe: the others are explicit repair requests whose whole
  /// point is to re-page everything regardless.
  ({bool due, bool scheduledOnly}) _reconcileDueBeforePush(
    bool bindNow,
    SyncStateRow state,
  ) {
    final now = _clock().toUtc();
    final lastFull = state.lastFullPullAt?.toUtc();
    final forced = _forceFullReconcile;
    _forceFullReconcile = false;
    final due = forced ||
        bindNow ||
        lastFull == null ||
        now.difference(lastFull) > kSyncFullPullInterval;
    if (due) _apply.clearRejected();
    return (due: due, scheduledOnly: !forced && !bindNow && lastFull != null);
  }

  /// [_cycle]'s reconcile dispatch, split out verbatim. Due exactly when
  /// [_reconcileDueBeforePush] already said so (bind, forced, or the daily
  /// staleness window) — issue #525 dropped a push batch's `resolved` rows
  /// as an independent trigger here: [SupabaseSyncApply.applyPushResult]
  /// already applies every one of them as the correct per-row response, so
  /// this method no longer needs to know whether the push saw any. Returns
  /// whether the reconcile (if it ran) hit a retryable apply failure.
  ///
  /// Issue #42: a due *scheduled* reconcile first probes the server
  /// ([_serverUnchangedSinceCursors]); when nothing changed server-side
  /// since the incremental pull's persisted cursors, the network re-pull
  /// and re-apply of every row is skipped — every remote apply is
  /// LWW-idempotent, so re-paging unchanged rows could only ever be a
  /// no-op — while everything local that rides a clean reconcile still
  /// runs (the `lastFullPullAt` advance and the issue #203 maintenance
  /// sweep, so the tombstone-retention cadence is preserved). Any probe
  /// failure answers "changed" and the full re-pull runs; sync is never
  /// silently skipped.
  Future<bool> _reconcileIfDue({
    required String uid,
    required bool reconcileDueBeforePush,
    required bool scheduledOnly,
  }) async {
    if (!reconcileDueBeforePush) return false;
    var reconcileRetry = false;
    if (!scheduledOnly || !await _serverUnchangedSinceCursors()) {
      reconcileRetry = await _reconcile(uid);
    }
    if (!reconcileRetry) {
      _consecutiveReconcileRetries = 0;
      await _updateState(
          (s) => s.copyWith(lastFullPullAt: Value(_clock().toUtc())));
      // Issue #203: periodic maintenance (bounded tombstone sweep + VACUUM)
      // runs after a clean full reconciliation, not unconditionally on every launch.
      await _storage.sweepTombstones();
      await _storage.db.vacuum();
    } else {
      _consecutiveReconcileRetries++;
      if (_consecutiveReconcileRetries >= kMaxConsecutiveReconcileRetries) {
        _consecutiveReconcileRetries = 0;
        await _updateState(
            (s) => s.copyWith(lastFullPullAt: Value(_clock().toUtc())));
      }
    }
    return reconcileRetry;
  }

  /// Issue #42: the scheduled reconcile's version probe — `max =
  /// fetchMaxVersion(table) <= startingCursor(table)` for *every* pull
  /// table, read from the persisted post-incremental-pull state. Every
  /// synced table stamps `server_version` from a trigger on every write
  /// (including the RPCs `sync_push` never touches — see
  /// [SyncTransport.fetchMaxVersion]), so a maximum at or below the cursor
  /// proves the incremental pull already saw everything; anything else —
  /// a higher maximum, an unknown probe, or a transport that throws
  /// instead of answering `null` — reports "changed" so the caller runs
  /// the full re-pull.
  Future<bool> _serverUnchangedSinceCursors() async {
    final state = await _storage.readSyncState();
    for (final table in _pullTableOrder) {
      final max = await _probeMaxVersion(table);
      if (max == null || max > _startingCursor(table, state)) return false;
    }
    return true;
  }

  /// [_serverUnchangedSinceCursors]'s per-table probe, wrapped so a
  /// transport that forgets [SyncTransport.fetchMaxVersion]'s own
  /// never-throws contract still degrades to "unknown" (full re-pull)
  /// instead of failing the whole cycle — the probe is an optimization,
  /// never a correctness requirement.
  Future<int?> _probeMaxVersion(SyncTable table) async {
    try {
      return await _transport.fetchMaxVersion(table);
    } catch (_) {
      return null;
    }
  }

  void _logRetryIfNeeded({
    required bool pullRetry,
    required bool reconcileRetry,
  }) {
    if (pullRetry || reconcileRetry) {
      debugPrint('lunarlog sync: a remote row waits for its profile; '
          'retrying next cycle');
    }
  }

  /// [_cycle]'s transport-error mapping, split out verbatim — same
  /// mapping, no behavior change.
  SyncErrorKind _syncErrorKindForTransportError(SyncTransportError error) =>
      switch (error) {
        SyncTransportAuthError() => SyncErrorKind.auth,
        SyncTransportNetworkError() => SyncErrorKind.network,
        SyncTransportRejectedError() => SyncErrorKind.other,
        SyncTransportOtherError() => SyncErrorKind.other,
      };

  String? _confirmedUid() => _auth.confirmedUserId;

  SyncPhase _phase(SyncPhase active) =>
      _restoring ? SyncPhase.restoring : active;

  /// Between batches and pages: the gate, the session and disposal are
  /// re-checked so a lock pauses and a sign-out or dispose aborts.
  void _checkpoint(String uid) {
    if (_disposed) throw const _SyncAborted();
    if (!_gateUnlocked()) throw const _SyncPaused();
    if (_confirmedUid() != uid) throw const _SyncAborted();
  }

  Future<void> _fail(SyncErrorKind kind) async {
    if (_disposed) return;
    try {
      await _updateState((s) => s.copyWith(lastError: Value(kind.name)));
    } catch (e, s) {
      // The status is still surfaced in memory. Issue #547: recorded, not
      // silenced — a persistently failing state write is worth seeing.
      unawaited(Sentry.captureException(e, stackTrace: s));
    }
    if (kind == SyncErrorKind.network) {
      _consecutiveNetworkFailures++;
      _backoffTimer?.cancel();
      _backoffTimer = _timerFactory(
        _backoff(_consecutiveNetworkFailures),
        () {
          _backoffTimer = null;
          requestSync();
        },
      );
    }
    _emit(_snapshot.copyWith(
      phase: SyncPhase.error,
      lastError: kind,
      dirtyCount: await _safeDirtyCount(),
      rejectedCount: _apply.rejectedCount,
    ));
  }

  Future<int> _safeDirtyCount() async {
    try {
      return await _storage.dirtyCount();
    } catch (e, s) {
      // Issue #547: recorded, not silenced — the stale in-memory count is
      // still a reasonable fallback, but a persistently failing count
      // query is worth seeing.
      unawaited(Sentry.captureException(e, stackTrace: s));
      return _snapshot.dirtyCount;
    }
  }

  // ---------------------------------------------------------------- binding

  Future<SyncStateRow> _bind(SyncStateRow state, String uid) async {
    final deviceId = state.deviceId.isEmpty ? _ulid.next() : state.deviceId;
    final bound = state.copyWith(boundUserId: Value(uid), deviceId: deviceId);
    await _storage.writeSyncState(bound);
    return bound;
  }

  void _restoreOffset(SyncStateRow state) {
    if (_offsetRestored) return;
    _offsetRestored = true;
    final ms = state.serverClockOffsetMs;
    if (ms != null) {
      final restored = Duration(milliseconds: ms);
      _storage.setClockOffset(restored);
      // Issue #566: seed the EMA from the last persisted value rather than
      // starting fresh — otherwise every app restart would re-learn the
      // offset from a single, unsmoothed sample.
      _smoothedOffset = restored;
    }
  }

  /// Issue #566: folds [sample] into [_smoothedOffset] via a simple EMA
  /// ([kClockOffsetSmoothingAlpha]) and returns the new smoothed value. The
  /// very first sample (no prior smoothed value, and [_restoreOffset] found
  /// nothing persisted) is taken as-is — there is nothing to smooth against
  /// yet.
  Duration _smoothOffset(Duration sample) {
    final previous = _smoothedOffset;
    final smoothed = previous == null
        ? sample
        : Duration(
            milliseconds: (previous.inMilliseconds +
                    kClockOffsetSmoothingAlpha *
                        (sample.inMilliseconds - previous.inMilliseconds))
                .round());
    _smoothedOffset = smoothed;
    return smoothed;
  }

  Future<void> _updateState(SyncStateRow Function(SyncStateRow) change) async {
    final current = await _storage.readSyncState();
    await _storage.writeSyncState(change(current));
  }

  // ------------------------------------------------------------------- push

  /// Pushes every pushable dirty row, profiles first, streaming at most
  /// [_batchSize] rows per table from storage — and JSON-encoding only
  /// that page — one batch at a time, instead of materialising and
  /// encoding the full dirty set up front (which could be thousands of
  /// rows after a large import). Each round's items and termination
  /// signal come from [_readPushRound] (finding #1's fix lives there); this
  /// method stays a plain read-push-repeat loop so it scores well under
  /// the CRAP gate on its own.
  ///
  /// A [_SyncPaused] raised by [_checkpoint] inside [_pushBatch] between
  /// two batches propagates out of this loop and out of [_cycle]: every
  /// batch already sent already called `markPushed` and stays committed,
  /// so the next cycle's fresh keyset scan (this method starting over
  /// with a fresh [_PushCursor]) sees only the rows still `dirty` and
  /// resumes from there — there is no separate persisted resume cursor to
  /// maintain.
  ///
  /// Issue #525: no longer returns whether any batch saw resolved rows —
  /// that used to be a second, independent reconcile trigger
  /// ([_reconcileIfDue]'s old `resolvedSeen` parameter), dropped because
  /// [_pushBatch] already applies every resolved row correctly on its own.
  Future<void> _push(String uid) async {
    final totalDirty = await _storage.dirtyCount();
    _emit(_snapshot.copyWith(pushedRows: 0, totalDirtyRows: totalDirty));
    if (totalDirty == 0) return;

    var pushedRows = 0;
    final cursor = _PushCursor(_storage, _batchSize);
    while (true) {
      final round = await _readPushRound(cursor);
      if (round.batch.isEmpty) {
        if (round.done) break;
        continue;
      }
      await _pushBatch(uid, round.batch);
      pushedRows += round.batch.length;
      _emit(_snapshot.copyWith(pushedRows: pushedRows));
      if (round.done) break;
    }
  }

  /// One round of [_push]: a fresh profiles page is read on *every* call
  /// via [cursor] — never gated behind a cached "done" flag (finding #1).
  /// Whenever that fresh page falls short of a full batch (profiles
  /// momentarily exhausted, from this round's point of view), the same
  /// round also reads the next day-entry page, so the two ride together
  /// exactly as the old single-shot chunking did. Because the profiles
  /// read is never skipped, a profile created mid-cycle (a ULID above the
  /// cursor) surfaces in a later round's page and is pushed before or
  /// alongside its own day entries — never after, which would otherwise
  /// reject the entries on a foreign key it hasn't seen yet. Returns this
  /// round's pushable items and whether the loop may terminate after it
  /// (this round's profile page was genuinely empty and day entries are
  /// exhausted).
  Future<({List<SyncPushItem> batch, bool done})> _readPushRound(
    _PushCursor cursor,
  ) async {
    final profilePage = await cursor.readProfilePage();
    final profilesEmptyThisRound = profilePage.isEmpty;
    final batch = <SyncPushItem>[
      for (final row
          in _apply.pushable(profilePage, (p) => p.id, (p) => p.localRev))
        SyncPushItem(
            SyncTable.profiles, row.id, row.localRev, encodeProfile(row)),
    ];
    if (profilePage.length < cursor.batchSize && !cursor.entriesDone) {
      final entryPage = await cursor.readEntryPage();
      batch.addAll([
        for (final row in _apply.pushable(entryPage, (e) => e.id, (e) => e.localRev))
          SyncPushItem(SyncTable.dayEntries, row.id, row.localRev,
              encodeDayEntry(row), profileId: row.profileId),
      ]);
    }
    // Issue #240: observations ride the same chaining rule day entries use
    // relative to profiles — read this round only once day entries are
    // (now, or already) exhausted, so the tables share one keyset scan's
    // worth of batching rather than each getting its own full
    // [_batchSize] allotment every round. Issue #188 extends the same
    // chain via [_appendModeTableItems].
    if (cursor.entriesDone && !cursor.observationsDone) {
      final observationPage = await cursor.readObservationPage();
      batch.addAll([
        for (final row
            in _apply.pushable(observationPage, (o) => o.id, (o) => o.localRev))
          SyncPushItem(SyncTable.observations, row.id, row.localRev,
              encodeObservation(row), profileId: row.profileId),
      ]);
    }
    await _appendModeTableItems(batch, cursor);
    return (
      batch: batch,
      done: profilesEmptyThisRound && cursor.allTablesDone,
    );
  }

  /// Issue #188: the profile_modes and cycle_overrides pages ride the same
  /// chaining rule — profile modes read once observations are exhausted,
  /// cycle overrides once profile modes are. Split out of [_readPushRound]
  /// (and the `done` conjunction into [_PushCursor.allTablesDone]) so that
  /// method's branch count stays under the CRAP gate as tables are added.
  /// Issue #128 extends the same chain via [_appendCareTableItems]: care
  /// notes ride once cycle overrides are exhausted, visit-prep items once
  /// care notes are.
  Future<void> _appendModeTableItems(
    List<SyncPushItem> batch,
    _PushCursor cursor,
  ) async {
    if (cursor.observationsDone && !cursor.profileModesDone) {
      final profileModePage = await cursor.readProfileModePage();
      batch.addAll([
        for (final row in _apply.pushable(
            profileModePage, (m) => m.profileId, (m) => m.localRev))
          SyncPushItem(SyncTable.profileModes, row.profileId, row.localRev,
              encodeProfileMode(row), profileId: row.profileId),
      ]);
    }
    if (cursor.profileModesDone && !cursor.cycleOverridesDone) {
      final cycleOverridePage = await cursor.readCycleOverridePage();
      batch.addAll([
        for (final row in _apply.pushable(
            cycleOverridePage, (o) => o.id, (o) => o.localRev))
          SyncPushItem(SyncTable.cycleOverrides, row.id, row.localRev,
              encodeCycleOverride(row), profileId: row.profileId),
      ]);
    }
    await _appendCareTableItems(batch, cursor);
  }

  /// Issue #128: the care_notes and visit_prep_items pages ride the same
  /// chaining rule — care notes read once cycle overrides are exhausted,
  /// visit-prep items once care notes are. Split out of
  /// [_appendModeTableItems] so that method's branch count stays under the
  /// CRAP gate as tables are added.
  Future<void> _appendCareTableItems(
    List<SyncPushItem> batch,
    _PushCursor cursor,
  ) async {
    if (cursor.cycleOverridesDone && !cursor.careNotesDone) {
      final careNotePage = await cursor.readCareNotePage();
      batch.addAll([
        for (final row
            in _apply.pushable(careNotePage, (n) => n.id, (n) => n.localRev))
          SyncPushItem(SyncTable.careNotes, row.id, row.localRev,
              encodeCareNote(row), profileId: row.profileId),
      ]);
    }
    if (cursor.careNotesDone && !cursor.visitPrepItemsDone) {
      final prepItemPage = await cursor.readVisitPrepItemPage();
      batch.addAll([
        for (final row in _apply.pushable(prepItemPage, (i) => i.id, (i) => i.localRev))
          SyncPushItem(SyncTable.visitPrepItems, row.id, row.localRev,
              encodeVisitPrepItem(row), profileId: row.profileId),
      ]);
    }
    // Issue #130: merge events ride the same chaining rule, once
    // visit-prep items are exhausted.
    if (cursor.visitPrepItemsDone && !cursor.guardianNotesDone) {
      final guardianNotePage = await cursor.readGuardianNotePage();
      batch.addAll([
        for (final row in _apply.pushable(
            guardianNotePage, (n) => n.id, (n) => n.localRev))
          SyncPushItem(SyncTable.guardianNotes, row.id, row.localRev,
              encodeGuardianNote(row), profileId: row.profileId),
      ]);
    }
    await _appendMergeAndRegistryItems(batch, cursor);
  }

  /// Issue #130/#257: the merge-event and tag-registry pages ride the same
  /// chaining rule, once guardian notes are exhausted. Split out of
  /// [_appendCareTableItems] so neither method's branch count reaches the
  /// CRAP gate as tables are added.
  Future<void> _appendMergeAndRegistryItems(
    List<SyncPushItem> batch,
    _PushCursor cursor,
  ) async {
    if (cursor.guardianNotesDone && !cursor.mergeEventsDone) {
      final mergeEventPage = await cursor.readMergeEventPage();
      batch.addAll([
        for (final row in _apply.pushable(mergeEventPage, (e) => e.id, (e) => e.localRev))
          SyncPushItem(SyncTable.dayEntryMergeEvents, row.id, row.localRev,
              encodeDayEntryMergeEvent(row), profileId: row.profileId),
      ]);
    }
    if (cursor.mergeEventsDone && !cursor.tagRegistryDone) {
      final tagRegistryPage = await cursor.readTagRegistryPage();
      batch.addAll([
        for (final row in _apply.pushable(tagRegistryPage, (e) => e.id, (e) => e.localRev))
          SyncPushItem(SyncTable.profileTagRegistry, row.id, row.localRev,
              encodeProfileTagRegistryEntry(row), profileId: row.profileId),
      ]);
    }
  }

  /// One push batch's request/response handling, split out of [_push]
  /// verbatim — same sequencing, same conditions. Issue #525: no longer
  /// returns whether the batch saw resolved rows (see [_push]'s doc); the
  /// clock offset computed below is applied internally and was never read
  /// by the caller either, so this method's return value is dropped
  /// entirely rather than kept as unused plumbing.
  ///
  /// Issue #566: `sentAt` is read immediately before [_transport.push] —
  /// not after it returns — so the offset measures `serverNow - sentAt`
  /// rather than `serverNow - (a clock reading taken after the full round
  /// trip and after [SupabaseSyncApply.applyPushResult] has written up to
  /// [PushBatch.maxRows] rows locally)`. The old, later reading was biased
  /// on a slow link: a 2s-RTT / 500-row batch used to stamp every
  /// subsequent local write a couple of seconds into the past, which loses
  /// LWW races that device should win. The raw sample is then smoothed via
  /// [_smoothOffset] before it is applied or persisted.
  Future<void> _pushBatch(
    String uid,
    List<SyncPushItem> batch,
  ) async {
    _checkpoint(uid);
    final sentAt = _clock();
    final PushResult result;
    try {
      result = await _transport.push(PushBatch(
        profiles: [for (final i in batch) if (i.table == SyncTable.profiles) i.json],
        dayEntries: [for (final i in batch) if (i.table == SyncTable.dayEntries) i.json],
        observations: [for (final i in batch) if (i.table == SyncTable.observations) i.json],
        profileModes: [for (final i in batch) if (i.table == SyncTable.profileModes) i.json],
        cycleOverrides: [for (final i in batch) if (i.table == SyncTable.cycleOverrides) i.json],
        careNotes: [for (final i in batch) if (i.table == SyncTable.careNotes) i.json],
        visitPrepItems: [for (final i in batch) if (i.table == SyncTable.visitPrepItems) i.json],
        mergeEvents: [for (final i in batch) if (i.table == SyncTable.dayEntryMergeEvents) i.json],
        tagRegistry: [for (final i in batch) if (i.table == SyncTable.profileTagRegistry) i.json],
        guardianNotes: [for (final i in batch) if (i.table == SyncTable.guardianNotes) i.json],
      ));
    } on SyncTransportRejectedError catch (error) {
      // A transport without per-row results: the named rows are rejected,
      // the rest of the batch stays dirty for the next cycle.
      _apply.markRejected(batch, error.ids);
      return;
    }
    await _apply.applyPushResult(batch, result);
    // The in-memory offset takes effect immediately (it stamps the next
    // local writes) and is persisted to sync_state for this committed batch.
    final sample = result.serverNow.toUtc().difference(sentAt.toUtc());
    final offset = _smoothOffset(sample);
    _storage.setClockOffset(offset);
    // Issue #641 LLA-042: once we have learned the server clock (from this
    // push's serverNow), rebase any dirty row that is still future-stamped
    // (the reason at least one row in this batch was rejected) so it becomes
    // pushable again instead of staying unsyncable until real time catches
    // up. Only runs when this batch saw a rejection — the common case for a
    // fast client clock — and matches only rows the server would reject.
    if (result.rejectedIds.isNotEmpty) {
      await _storage.rebaseFutureStampedRows(serverNow: result.serverNow);
    }
    await _updateState(
        (s) => s.copyWith(serverClockOffsetMs: Value(offset.inMilliseconds)));
  }

  // ------------------------------------------------------------------- pull

  /// Incremental pull per table, profiles first (KTD2). Returns whether a
  /// page hit a retryable apply failure (left for the next cycle).
  ///
  /// Issue #521: fetches the commit-safe cursor watermark once for the
  /// whole cycle (not once per table) before paging any table, and hands
  /// it to every [_pullTable] call — a single call is enough since the
  /// watermark only ever gets *less* stale as the cycle progresses, and one
  /// fewer round trip per cycle is one fewer failure mode to handle. `null`
  /// (the RPC is unavailable) makes every table fall back to
  /// [kCursorLookback] independently.
  ///
  /// Per-table paging and the profileGuardians-specific retry bookkeeping
  /// are split into [_pullTable]/[_onTablePullFailure]/
  /// [_onTablePullSettled] (finding #4 follow-up) so this stays a plain
  /// orchestrator: each extracted piece is small enough to score well
  /// under the CRAP gate on its own, instead of one method carrying all
  /// of it.
  Future<bool> _pullIncremental(String uid) async {
    _emit(_snapshot.copyWith(phase: _phase(SyncPhase.pulling)));
    final watermark = await _fetchWatermark();
    await _primePullCycle(await _incrementalCycleCursors());
    var retry = false;
    for (final table in _pullTableOrder) {
      if (await _pullTable(table, uid, watermark: watermark)) retry = true;
    }
    return retry;
  }

  /// [_pullIncremental]'s watermark fetch, wrapped so a transport that
  /// forgets its own graceful-fallback contract (throws instead of
  /// returning null) still degrades to [kCursorLookback] instead of failing
  /// the whole cycle — the watermark is an optimization the pull cursor can
  /// always do without, never a correctness requirement.
  Future<int?> _fetchWatermark() async {
    try {
      return await _transport.fetchWatermark();
    } catch (_) {
      return null;
    }
  }

  /// [_incrementalCycleCursors]'s starting-cursor snapshot for every table
  /// [SyncTransport.primePullCycle] can prime (issue #598) — every
  /// [SyncTable] but [SyncTable.deletedProfiles], which `sync_pull` does
  /// not cover and which [_pullIncremental] still pages from version 0
  /// every cycle via [_startingCursor]'s own carve-out for it.
  static const List<SyncTable> _pullRpcTables = [
    SyncTable.profiles,
    SyncTable.profileGuardians,
    SyncTable.dayEntries,
    SyncTable.observations,
    SyncTable.profileModes,
    SyncTable.cycleOverrides,
    SyncTable.careNotes,
    SyncTable.visitPrepItems,
    // Issue #130: sync_pull carries this table's pages too (a missing key
    // in its response would make _decodePullResponse drop the whole cache,
    // so the server side grew with the client, atomically).
    SyncTable.dayEntryMergeEvents,
    // Issue #257: same — sync_pull's tenth per-profile key.
    SyncTable.profileTagRegistry,
    // Issue #170: same — sync_pull's eleventh per-profile key (and a
    // table the RPC covers; the fallback select's own relation-not-found
    // leniency covers a server predating this table's migration).
    SyncTable.dayEntryHistory,
  ];

  /// One [_storage.readSyncState] read, turned into the persisted starting
  /// cursor for every [_pullRpcTables] entry (issue #598) — the snapshot
  /// [_primePullCycle] hands the transport before [_pullIncremental]'s own
  /// per-table loop begins reading (and advancing) those same cursors.
  Future<Map<SyncTable, int>> _incrementalCycleCursors() async {
    final state = await _storage.readSyncState();
    return {
      for (final table in _pullRpcTables) table: _startingCursor(table, state),
    };
  }

  /// Best-effort prime of this cycle's `sync_pull` cache (issue #598): never
  /// lets a transport that forgets [SyncTransport.primePullCycle]'s own
  /// never-throws contract fail the whole cycle — priming is purely an
  /// optimization the per-table pull below still works correctly without,
  /// just via `SupabaseSyncTransport`'s own select fallback.
  Future<void> _primePullCycle(Map<SyncTable, int> cursors) async {
    try {
      await _transport.primePullCycle(cursors);
    } catch (_) {
      // Deliberately swallowed — see the doc comment above.
    }
  }

  /// Pages [table] incrementally until exhausted or a page hits a
  /// retryable apply failure. Returns whether it failed (left for the next
  /// cycle by the caller's `retry` flag).
  Future<bool> _pullTable(SyncTable table, String uid, {int? watermark}) async {
    final state = await _storage.readSyncState();
    var after = _startingCursor(table, state);
    var failed = false;
    while (true) {
      _checkpoint(uid);
      final page = await _transport.pullPage(
          table: table, afterVersion: after, limit: _pageSize);
      if (page.isEmpty) break;
      final newCursor = _clampedCursor(page, floor: after, watermark: watermark);
      try {
        await _storage.applyRemotePage(
            table: table, rows: page, newCursor: newCursor);
      } on RetryableSyncApplyError {
        failed = true;
        await _onTablePullFailure(table);
        break;
      }
      final progressed = newCursor > after;
      after = newCursor;
      // Issue #521: when the clamp below holds the cursor short of the
      // page's own maximum version, a full-size page no longer proves the
      // table is exhausted the way it used to — but if the clamp also
      // stops the cursor from progressing at all, looping on an identical
      // page forever would be wrong, so `!progressed` still ends this
      // table's turn here; the rows above the clamp are left for a later
      // cycle, once the watermark (or, on reconcile, a page-less scan from
      // zero) has caught up.
      if (page.length < _pageSize || !progressed) break;
    }
    _onTablePullSettled(table, failed);
    return failed;
  }

  /// The new cursor for one page (issue #521): [maxVersion] of [page]
  /// (floored at [floor], never regressing), clamped to at most
  /// [watermark] when one was supplied by the server, or otherwise to at
  /// most [kCursorLookback] below that maximum. Either way the result never
  /// drops below [floor] — a stale or lagging watermark must never move the
  /// cursor backward, only fail to advance it as far as the page allows.
  int _clampedCursor(
    List<RemoteRow> page, {
    required int floor,
    required int? watermark,
  }) {
    final maxVersion = _apply.maxVersion(page, floor);
    final target = watermark ?? (maxVersion - kCursorLookback);
    final clamped = target < maxVersion ? target : maxVersion;
    return clamped > floor ? clamped : floor;
  }

  /// [_pullTable]'s persisted-cursor lookup. Split out so [_pullTable]'s
  /// branch count stays under the CRAP gate as tables are added (Issue
  /// #188 added two cases; Issue #128 two more). Issue #525:
  /// `profileGuardians` reads a real persisted cursor too, instead of
  /// always starting at 0 (schema v3's original, un-cursored shape) — every
  /// cycle used to force a full sequential scan of the global
  /// `profile_guardians` table. Issue #597 applies the identical fix to
  /// `deletedProfiles`, the one table #525 deliberately left un-cursored.
  int _startingCursor(SyncTable table, SyncStateRow state) =>
      _startingCursors[table]!(state);

  /// The per-table persisted-cursor getter for [_startingCursor] — a map
  /// rather than an exhaustive switch since Issue #130's tenth SyncTable
  /// (the switch sat permanently over the quality gate's per-method
  /// complexity ceiling; row_codec.dart's `_syncTableNames` and
  /// storage_remote_apply.dart's `_pageRowAppliers` grew the same way).
  /// Issue #597: deletedProfiles has a persisted cursor too.
  static final Map<SyncTable, int Function(SyncStateRow)> _startingCursors = {
    SyncTable.profiles: (s) => s.cursorProfiles,
    SyncTable.dayEntries: (s) => s.cursorDayEntries,
    SyncTable.observations: (s) => s.cursorObservations,
    SyncTable.profileModes: (s) => s.cursorProfileModes,
    SyncTable.cycleOverrides: (s) => s.cursorCycleOverrides,
    SyncTable.careNotes: (s) => s.cursorCareNotes,
    SyncTable.guardianNotes: (s) => s.cursorGuardianNotes,
    SyncTable.visitPrepItems: (s) => s.cursorVisitPrepItems,
    SyncTable.dayEntryMergeEvents: (s) => s.cursorDayEntryMergeEvents,
    SyncTable.profileTagRegistry: (s) => s.cursorProfileTagRegistry,
    SyncTable.dayEntryHistory: (s) => s.cursorDayEntryHistory,
    SyncTable.profileGuardians: (s) => s.cursorProfileGuardians,
    SyncTable.deletedProfiles: (s) => s.cursorDeletedProfiles,
  };

  /// A page of [table] hit a [RetryableSyncApplyError]. Only profileGuardians
  /// carries follow-up bookkeeping (KTD2 predates a retry story for the
  /// other tables).
  Future<void> _onTablePullFailure(SyncTable table) async {
    if (table != SyncTable.profileGuardians) return;
    // A guardian row whose profile is not held locally: the profile may
    // sit below the profiles cursor (joined share), so rewind it - the
    // next cycle re-pulls profiles from version 0 and the share converges
    // without involving the reconcile-retry bound (#74 owns that path
    // exclusively).
    //
    // Bounded the same way as that cap (finding #4): after fixing #8, the
    // only row that can still reach here is an accepted membership whose
    // profile genuinely never arrives, and without its own bound that
    // single row would force a full profile re-pull every cycle forever.
    // Past kMaxConsecutiveReconcileRetries consecutive failures the
    // rewind stops - unlike the reconcile cap there is no time-based gate
    // like lastFullPullAt to lean on here, so the count is only reset
    // once profileGuardians applies cleanly again ([_onTablePullSettled]),
    // not on hitting the cap itself.
    _consecutiveGuardianPullRetries++;
    if (_consecutiveGuardianPullRetries < kMaxConsecutiveReconcileRetries) {
      final s = await _storage.readSyncState();
      await _storage.writeSyncState(s.copyWith(cursorProfiles: 0));
    }
  }

  /// [table]'s page loop finished (normally or via a failure). Clears the
  /// profileGuardians retry count once it applies cleanly again.
  void _onTablePullSettled(SyncTable table, bool failed) {
    if (table == SyncTable.profileGuardians && !failed) {
      _consecutiveGuardianPullRetries = 0;
    }
  }

  /// Full reconciliation: every row of tables paged from version 0,
  /// applied under LWW without touching the cursors (KTD2). Returns whether
  /// a row hit a retryable apply failure.
  Future<bool> _reconcile(String uid) async {
    _emit(_snapshot.copyWith(phase: _phase(SyncPhase.pulling)));
    // Issue #598: every table reconcile pages starts at version 0, so this
    // cycle's prime is just that — no persisted-state read needed, unlike
    // _pullIncremental's snapshot.
    await _primePullCycle({for (final table in _pullRpcTables) table: 0});
    var retry = false;
    for (final table in _pullTableOrder) {
      var after = 0;
      while (true) {
        _checkpoint(uid);
        final page = await _transport.pullPage(
            table: table, afterVersion: after, limit: _pageSize);
        if (page.isEmpty) break;
        if (await _apply.applyReconcilePage(page)) retry = true;
        final next = _apply.maxVersion(page, after);
        if (page.length < _pageSize || next <= after) break;
        after = next;
      }
    }
    return retry;
  }

  // --------------------------------------------------------------- snapshot

  void _emit(SyncSnapshot next) {
    if (_snapshots.isClosed) return;
    if (next == _snapshot) return;
    _snapshot = next;
    _snapshots.add(next);
  }
}
