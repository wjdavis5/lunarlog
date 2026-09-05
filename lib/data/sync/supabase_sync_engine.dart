/// The sync coordinator (U5; KTD1, KTD2, KTD4, KTD10, KTD11): pushes dirty
/// rows through `sync_push` in batches, applies the server's resolutions
/// and declines in the same cycle, pulls remote pages per table by
/// `server_version`, reconciles fully on bind / after resolutions / daily,
/// and enforces the device binding guard with a non-destructive mismatch
/// state.
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

import '../../domain/auth/auth_service.dart';
import '../../domain/sync/sync_engine.dart';
import '../db/db.dart';
import '../db/storage.dart';
import '../db/ulid.dart';
import 'remote_rows.dart';
import 'row_codec.dart';
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

/// Maximum consecutive sync cycles that may retry reconciliation due to
/// un-appliable remote rows before advancing lastFullPullAt to avoid an
/// unbounded reconcile loop. Also bounds [_consecutiveGuardianPullRetries]
/// (finding #4), a separate un-appliable-row loop with the same shape in
/// [SupabaseSyncEngine._pullIncremental].
const int kMaxConsecutiveReconcileRetries = 3;

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

class _PushItem {
  const _PushItem(this.table, this.id, this.localRev, this.json);

  final SyncTable table;
  final String id;
  final int localRev;
  final JsonRow json;
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
  final UlidGenerator _ulid;

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

  /// Consecutive cycles in a row where a profileGuardians page hit a
  /// [RetryableSyncApplyError] (finding #4): bounds the `cursorProfiles`
  /// rewind in [_pullIncremental] the same way [_consecutiveReconcileRetries]
  /// bounds the reconcile path, so one permanently unresolvable row (an
  /// accepted membership whose profile never arrives — the only case left
  /// after finding #8) cannot force a full profile re-pull every cycle
  /// forever.
  int _consecutiveGuardianPullRetries = 0;

  /// Rows the server rejected, id → `local_rev` at rejection. A row is
  /// excluded from pushes while its `local_rev` still equals the rejected
  /// one; a later local write bumps it and the row is retried.
  final Map<String, int> _rejected = {};

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
        .tableUpdates(TableUpdateQuery.onAllTables([db.profiles, db.dayEntries]))
        .listen((_) => _onLocalWrite());
    _periodicTimer = _periodicTimerFactory(_periodicInterval, () {
      _rejected.clear();
      requestSync();
    });
    requestSync();
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
    if (state == AppLifecycleState.resumed) requestSync();
  }

  // ---------------------------------------------------------------- triggers

  void _onGateChanged() {
    final unlocked = _gateUnlocked();
    if (unlocked == _lastGateUnlocked) return;
    _lastGateUnlocked = unlocked;
    if (unlocked) {
      requestSync();
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

  Future<bool> _hasPushableDirty() async {
    final profiles = await _storage.readDirtyProfiles();
    if (_pushable(profiles, (p) => p.id, (p) => p.localRev).isNotEmpty) {
      return true;
    }
    final entries = await _storage.readDirtyDayEntries();
    return _pushable(entries, (e) => e.id, (e) => e.localRev).isNotEmpty;
  }

  /// Dirty rows the server has not rejected at their current `local_rev`
  /// (a later local write bumps the rev and makes the row pushable again).
  Iterable<T> _pushable<T>(
    List<T> rows,
    String Function(T) id,
    int Function(T) localRev,
  ) =>
      rows.where((row) => _rejected[id(row)] != localRev(row));

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

      // Computed (and, when due, acted on by clearing _rejected) before the
      // push so a previously-rejected row is retried once the reconcile
      // that follows re-evaluates it.
      final reconcileDueBeforePush = _reconcileDueBeforePush(bindNow, state);

      final resolvedSeen = await _push(uid);
      final pullRetry = await _pullIncremental(uid);
      state = await _storage.readSyncState();
      final reconcileRetry = await _reconcileIfDue(
        uid: uid,
        reconcileDueBeforePush: reconcileDueBeforePush,
        resolvedSeen: resolvedSeen,
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
        rejectedCount: _rejected.length,
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
  /// stale (KTD2). When due, also clears [_rejected] (a previously-rejected
  /// row is retried once the reconcile that follows re-evaluates it) —
  /// this must run before the push, so it lives here rather than in
  /// [_reconcileIfDue], which only sees post-push state.
  bool _reconcileDueBeforePush(bool bindNow, SyncStateRow state) {
    final now = _clock().toUtc();
    final lastFull = state.lastFullPullAt?.toUtc();
    final forced = _forceFullReconcile;
    _forceFullReconcile = false;
    final due = forced ||
        bindNow ||
        lastFull == null ||
        now.difference(lastFull) > kSyncFullPullInterval;
    if (due) _rejected.clear();
    return due;
  }

  /// [_cycle]'s reconcile dispatch, split out verbatim. Due either because
  /// [_reconcileDueBeforePush] already said so, or because the push saw a
  /// resolved row ([resolvedSeen]). Returns whether the reconcile (if it
  /// ran) hit a retryable apply failure.
  Future<bool> _reconcileIfDue({
    required String uid,
    required bool reconcileDueBeforePush,
    required bool resolvedSeen,
  }) async {
    if (!reconcileDueBeforePush && !resolvedSeen) return false;
    final reconcileRetry = await _reconcile(uid);
    if (!reconcileRetry) {
      _consecutiveReconcileRetries = 0;
      await _updateState(
          (s) => s.copyWith(lastFullPullAt: Value(_clock().toUtc())));
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

  void _logRetryIfNeeded({required bool pullRetry, required bool reconcileRetry}) {
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

  String? _confirmedUid() =>
      _auth.state == AuthSessionState.signedIn ? _auth.currentUserId : null;

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
    } catch (_) {
      // The status is still surfaced in memory.
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
      rejectedCount: _rejected.length,
    ));
  }

  Future<int> _safeDirtyCount() async {
    try {
      return await _storage.dirtyCount();
    } catch (_) {
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
    if (ms != null) _storage.setClockOffset(Duration(milliseconds: ms));
  }

  Future<void> _updateState(SyncStateRow Function(SyncStateRow) change) async {
    final current = await _storage.readSyncState();
    await _storage.writeSyncState(change(current));
  }

  // ------------------------------------------------------------------- push

  /// Pushes every pushable dirty row, profiles first, in batches. Returns
  /// whether any batch answered with resolved rows (a reconcile trigger).
  Future<bool> _push(String uid) async {
    final profiles = [
      for (final row in _pushable(
          await _storage.readDirtyProfiles(), (p) => p.id, (p) => p.localRev))
        _PushItem(SyncTable.profiles, row.id, row.localRev, encodeProfile(row)),
    ];
    final entries = [
      for (final row in _pushable(await _storage.readDirtyDayEntries(),
          (e) => e.id, (e) => e.localRev))
        _PushItem(
            SyncTable.dayEntries, row.id, row.localRev, encodeDayEntry(row)),
    ];
    if (profiles.isEmpty && entries.isEmpty) return false;

    var resolvedSeen = false;
    for (final batch in _chunk(profiles, entries)) {
      final outcome = await _pushBatch(uid, batch);
      if (outcome.resolvedSeen) resolvedSeen = true;
    }
    return resolvedSeen;
  }

  /// One push batch's request/response handling, split out of [_push]
  /// verbatim — same sequencing, same conditions. `offset == null` means
  /// the batch hit [SyncTransportRejectedError] (no server clock reading
  /// to take).
  Future<({bool resolvedSeen, Duration? offset})> _pushBatch(
    String uid,
    List<_PushItem> batch,
  ) async {
    _checkpoint(uid);
    final PushResult result;
    try {
      result = await _transport.push(PushBatch(
        profiles: [for (final i in batch) if (i.table == SyncTable.profiles) i.json],
        dayEntries: [for (final i in batch) if (i.table == SyncTable.dayEntries) i.json],
      ));
    } on SyncTransportRejectedError catch (error) {
      // A transport without per-row results: the named rows are rejected,
      // the rest of the batch stays dirty for the next cycle.
      _markRejected(batch, error.ids);
      return (resolvedSeen: false, offset: null);
    }
    await _applyPushResult(batch, result);
    // The in-memory offset takes effect immediately (it stamps the next
    // local writes) and is persisted to sync_state for this committed batch.
    final offset = result.serverNow.toUtc().difference(_clock().toUtc());
    _storage.setClockOffset(offset);
    await _updateState(
        (s) => s.copyWith(serverClockOffsetMs: Value(offset.inMilliseconds)));
    return (resolvedSeen: result.resolved.isNotEmpty, offset: offset);
  }

  void _markRejected(List<_PushItem> batch, List<String> rejectedIds) {
    final batchRevs = {for (final i in batch) i.id: i.localRev};
    for (final id in rejectedIds) {
      final rev = batchRevs[id];
      if (rev != null) _rejected[id] = rev;
    }
  }

  Future<void> _applyPushResult(List<_PushItem> batch, PushResult result) async {
    final rejected = result.rejectedIds.toSet();
    final acceptedProfileIds = <String>{};
    for (final item in batch) {
      if (rejected.contains(item.id)) {
        _rejected[item.id] = item.localRev;
        continue;
      }
      _rejected.remove(item.id);
      if (item.table == SyncTable.profiles) {
        acceptedProfileIds.add(item.id);
      }
      await _storage.markPushed(
          table: item.table, id: item.id, localRevAtPush: item.localRev);
    }
    if (acceptedProfileIds.isNotEmpty) {
      await _unrejectEntriesOf(acceptedProfileIds, rejected);
    }
    if (result.resolved.isNotEmpty) {
      await _storage.applyResolved(result.resolved);
    }
  }

  /// A day entry rejected alongside its profile is un-rejected once that
  /// profile is accepted (and the entry itself wasn't [rejected]), so it is
  /// retried on the next push instead of waiting for its own local edit.
  Future<void> _unrejectEntriesOf(
    Set<String> acceptedProfileIds,
    Set<String> rejected,
  ) async {
    final dirty = await _storage.readDirtyDayEntries();
    for (final entry in dirty) {
      if (acceptedProfileIds.contains(entry.profileId) &&
          !rejected.contains(entry.id)) {
        _rejected.remove(entry.id);
      }
    }
  }

  /// Batches of at most [_batchSize] rows per table with profiles in the
  /// earliest batches: profile-only batches until the profiles run out, the
  /// last of which also carries the first day entries.
  List<List<_PushItem>> _chunk(List<_PushItem> profiles, List<_PushItem> entries) {
    final batches = <List<_PushItem>>[];
    var p = 0;
    var e = 0;
    while (p < profiles.length || e < entries.length) {
      final batch = <_PushItem>[];
      final pEnd = min(p + _batchSize, profiles.length);
      batch.addAll(profiles.sublist(p, pEnd));
      p = pEnd;
      if (p >= profiles.length) {
        final eEnd = min(e + _batchSize, entries.length);
        batch.addAll(entries.sublist(e, eEnd));
        e = eEnd;
      }
      batches.add(batch);
    }
    return batches;
  }

  // ------------------------------------------------------------------- pull

  /// Incremental pull per table, profiles first (KTD2). Returns whether a
  /// page hit a retryable apply failure (left for the next cycle).
  Future<bool> _pullIncremental(String uid) async {
    _emit(_snapshot.copyWith(phase: _phase(SyncPhase.pulling)));
    var retry = false;
    for (final table in const [
      SyncTable.profiles,
      SyncTable.profileGuardians,
      SyncTable.dayEntries,
    ]) {
      final state = await _storage.readSyncState();
      // profileGuardians has no persisted cursor yet (schema v3): it pages
      // from 0 every cycle, but `after` still advances locally so a full
      // first page terminates instead of looping on the same page.
      var after = switch (table) {
        SyncTable.profiles => state.cursorProfiles,
        SyncTable.dayEntries => state.cursorDayEntries,
        SyncTable.profileGuardians => 0,
      };
      var guardianFailedThisTable = false;
      while (true) {
        _checkpoint(uid);
        final page = await _transport.pullPage(
            table: table, afterVersion: after, limit: _pageSize);
        if (page.isEmpty) break;
        final newCursor = _maxVersion(page, after);
        try {
          await _storage.applyRemotePage(
              table: table, rows: page, newCursor: newCursor);
        } on RetryableSyncApplyError {
          retry = true;
          if (table == SyncTable.profileGuardians) {
            guardianFailedThisTable = true;
            // A guardian row whose profile is not held locally: the
            // profile may sit below the profiles cursor (joined share),
            // so rewind it - the next cycle re-pulls profiles from
            // version 0 and the share converges without involving the
            // reconcile-retry bound (#74 owns that path exclusively).
            //
            // Bounded the same way as that cap (finding #4): after fixing
            // #8, the only row that can still reach here is an accepted
            // membership whose profile genuinely never arrives, and
            // without its own bound that single row would force a full
            // profile re-pull every cycle forever. Past
            // kMaxConsecutiveReconcileRetries consecutive failures the
            // rewind stops - unlike the reconcile cap there is no
            // time-based gate like lastFullPullAt to lean on here, so the
            // count is only reset once profileGuardians applies cleanly
            // again (below), not on hitting the cap itself.
            _consecutiveGuardianPullRetries++;
            if (_consecutiveGuardianPullRetries <
                kMaxConsecutiveReconcileRetries) {
              final s = await _storage.readSyncState();
              await _storage.writeSyncState(s.copyWith(cursorProfiles: 0));
            }
          }
          break;
        }
        final progressed = newCursor > after;
        after = newCursor;
        if (page.length < _pageSize || !progressed) break;
      }
      if (table == SyncTable.profileGuardians && !guardianFailedThisTable) {
        _consecutiveGuardianPullRetries = 0;
      }
    }
    return retry;
  }

  /// Full reconciliation: every row of tables paged from version 0,
  /// applied under LWW without touching the cursors (KTD2). Returns whether
  /// a row hit a retryable apply failure.
  Future<bool> _reconcile(String uid) async {
    _emit(_snapshot.copyWith(phase: _phase(SyncPhase.pulling)));
    var retry = false;
    for (final table in const [
      SyncTable.profiles,
      SyncTable.profileGuardians,
      SyncTable.dayEntries,
    ]) {
      var after = 0;
      while (true) {
        _checkpoint(uid);
        final page = await _transport.pullPage(
            table: table, afterVersion: after, limit: _pageSize);
        if (page.isEmpty) break;
        if (await _applyReconcilePage(page)) retry = true;
        final next = _maxVersion(page, after);
        if (page.length < _pageSize || next <= after) break;
        after = next;
      }
    }
    return retry;
  }

  /// Applies a reconcile page in one transaction; when a row hits a
  /// retryable apply failure the page is re-applied row by row so every
  /// other row still lands (the per-row semantics of the single-row
  /// applies). Returns whether any row was left for the next cycle.
  Future<bool> _applyReconcilePage(List<RemoteRow> page) async {
    try {
      await _storage.applyRemoteRows(page);
      return false;
    } on RetryableSyncApplyError {
      // Fall through to per-row application.
    }
    var retry = false;
    for (final row in page) {
      try {
        switch (row) {
          case RemoteProfileRow():
            await _storage.applyRemoteProfile(row);
          case RemoteProfileGuardianRow():
            await _storage.applyRemoteRows([row]);
          case RemoteDayEntryRow():
            await _storage.applyRemoteDayEntry(row);
        }
      } on RetryableSyncApplyError {
        retry = true;
      }
    }
    return retry;
  }

  int _maxVersion(List<RemoteRow> page, int floor) {
    var v = floor;
    for (final row in page) {
      if (row.serverVersion > v) v = row.serverVersion;
    }
    return v;
  }

  // --------------------------------------------------------------- snapshot

  void _emit(SyncSnapshot next) {
    if (_snapshots.isClosed) return;
    if (next == _snapshot) return;
    _snapshot = next;
    _snapshots.add(next);
  }
}
