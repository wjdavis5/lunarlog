/// Session gate lifecycle (U7, R7, flow F3, AE4): the gate controller that
/// enforces it.
///
/// * Cold start: gated platforms show the lock screen *before any profile
///   data renders* and *before the database is opened* — a declined
///   credential never decrypts anything (AE4).
/// * Re-lock: backgrounding (paused/hidden — and `inactive`, which is what
///   split-screen/multi-window focus loss reports) always re-locks;
///   foreground inactivity re-locks after a timeout (default 2 minutes,
///   toggleable via [SettingsKeys.relockEnabled], default on).
/// * System-UI windows (#65; KTD2): the one exception to the above. While
///   the app itself has system UI on screen — its credential prompt, the
///   Google picker, the Apple sheet — a departure covers the content but
///   does not lock, because the platform reports those the same way it
///   reports a real departure and no signal separates them. Bounded by
///   [GateController.systemUiDeadline], which ignores the relock toggle.
/// * Snapshot suppression (cross-platform): an opaque cover replaces the
///   app's content whenever the lifecycle is not `resumed`, so the
///   app-switcher snapshot shows the cover, never data. On Android this is
///   backed by FLAG_SECURE via a tiny platform channel
///   ([applyPlatformPrivacyProtections]); the cover alone remains the
///   mechanism everywhere else (see README "Known limitations").
/// * Launch payload seam: [GateController.pendingLaunchProfileId] can be
///   set by the shell before content shows; U8 wires real notification
///   taps into it, and the profile home consumes it only after the gate
///   opens (routes to the firing profile's overview).
///
/// Split out of `lib/app_lifecycle.dart` (issue #433): this file owns the
/// [GateController] state machine plus its timer typedef/impl and the
/// gate-only constants. The app root ([LunarLogRoot] lives in
/// `lib/app_root.dart`). `lib/app_lifecycle.dart` remains as a thin
/// re-export barrel so existing import sites keep working.
///
/// This file is composition-root territory (like `main.dart`): it is
/// allowed to touch domain settings types to wire the drift settings store
/// into the controller.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Platform channel used to set Android FLAG_SECURE (snapshot/screenshot
/// suppression at the window level). Best effort — see
/// [applyPlatformPrivacyProtections].
const String kPrivacyChannel = 'lunarlog/privacy';

/// v1 inactivity auto-relock timeout (fixed; the settings screen shows it).
const Duration kDefaultInactivityTimeout = Duration(minutes: 2);

/// How long a closed system-UI window keeps absorbing lifecycle reports
/// (#65 U1; KTD2a). The prompt's dismissal can report `inactive` *after*
/// handing back its result, and `lock()` never sets the denial flag, so
/// without this tail a granted unlock is undone by the prompt's own
/// trailing transition — indistinguishable, on screen, from the discarded
/// grant this change removes.
const Duration kSystemUiSettleTimeout = Duration(seconds: 3);

/// Best-effort platform privacy hardening, called once at root startup.
/// Currently: FLAG_SECURE on Android (blocks app-switcher snapshots and
/// screenshots natively). Failures are swallowed — the opaque lifecycle
/// cover remains the cross-platform baseline.
Future<void> applyPlatformPrivacyProtections({
  BreadcrumbLog? breadcrumbLog,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel(kPrivacyChannel)
        .invokeMethod<void>('setFlagSecure', true);
  } catch (error, stackTrace) {
    (breadcrumbLog ?? defaultBreadcrumbLog)
        .record('privacy', error.runtimeType.toString());
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}

/// Injectable inactivity timer so tests can fire the timeout
/// deterministically instead of waiting out real time.
abstract interface class InactivityTimer {
  void cancel();
}

typedef InactivityTimerFactory = InactivityTimer Function(
    Duration delay, VoidCallback onTimeout);

class _RealInactivityTimer implements InactivityTimer {
  _RealInactivityTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

InactivityTimer defaultInactivityTimerFactory(
        Duration delay, VoidCallback onTimeout) =>
    _RealInactivityTimer(Timer(delay, onTimeout));

/// Owns the locked/unlocked session state and everything that flips it.
///
/// Notifications drive both the root's state machine and the
/// [GateShell] overlay; nothing else mutates these flags.
class GateController extends ChangeNotifier with WidgetsBindingObserver {
  GateController({
    required AppGate gate,
    this.inactivityTimeout = kDefaultInactivityTimeout,
    this.inactivityTimerFactory = defaultInactivityTimerFactory,
    this.systemUiDeadline = kDefaultInactivityTimeout,
    this.settleTimeout = kSystemUiSettleTimeout,
  }) : _gate = gate {
    _locked = gate.requiresUnlock;
    WidgetsBinding.instance.addObserver(this);
  }

  final AppGate _gate;
  final Duration inactivityTimeout;
  final InactivityTimerFactory inactivityTimerFactory;

  /// Hard bound on an open system-UI window (#65 U1; KTD5). Deliberately
  /// *not* the inactivity timer: that one is cancelled and restarted by
  /// every `resumed` and every pointer event, so it measures foreground
  /// idle time rather than window age, and it refuses to arm at all when
  /// the operator turned the relock toggle off. This one ignores all three.
  final Duration systemUiDeadline;

  /// See [kSystemUiSettleTimeout].
  final Duration settleTimeout;

  bool _locked = false;
  bool _authenticating = false;
  bool _denied = false;
  bool _obscured = false;
  bool _relockEnabled = true;
  String? _pendingLaunchProfileId;
  InactivityTimer? _inactivityTimer;
  StreamSubscription<String?>? _relockSub;

  /// Last lifecycle state this controller was told about. Tracked here
  /// rather than read from `WidgetsBinding.instance` so the gate's own
  /// notion of "is the operator back?" is driven by the same events that
  /// drive its locking, and so controller-level tests are honest.
  bool _resumed = true;

  /// Depth of nested system-UI windows (#65 U1; KTD2). A counter, not a
  /// flag: adding a sign-in method legitimately nests a credential prompt
  /// inside a provider ceremony.
  int _systemUiWindows = 0;
  int _nextSystemUiEpoch = 0;
  int? _systemUiEpoch;
  bool _settling = false;
  bool _departedDuringWindow = false;
  bool _disposed = false;

  /// Bumped whenever the gate makes a decision that supersedes an
  /// in-flight credential request — currently only the window deadline
  /// firing. A request that resolves across a bump is stale: honouring it
  /// would silently re-open a session the gate already committed to
  /// closing, and would hand the sync engine an unlocked edge on a grant
  /// nobody re-verified.
  int _generation = 0;

  /// Public read of [_generation], for a caller that runs its own operation
  /// inside [duringSystemUi] without a dedicated result-checking wrapper
  /// like [unlock] or [reauthenticate] — e.g. the feedback attachment
  /// picker. Capture this before starting the operation and compare after
  /// it resolves; a change means the deadline fired and re-locked the gate
  /// while the operation was in flight, so its result is stale and must be
  /// discarded rather than honoured.
  int get generation => _generation;
  InactivityTimer? _systemUiTimer;
  InactivityTimer? _settleTimer;

  /// True while a departure must not lock the app: the app's own system UI
  /// is on screen, or it just came off and is still settling.
  bool get _suppressingLock => _systemUiWindows > 0 || _settling;

  /// Whether the lock is currently suppressed because the app put system UI
  /// on screen itself. Diagnostics and tests only; nothing in `lib/` reads
  /// it to make a decision.
  bool get systemUiActive => _suppressingLock;

  bool get locked => _locked;

  bool get unlocked => !_locked;

  bool get authenticating => _authenticating;

  /// True when the last credential attempt was declined or unavailable.
  bool get lastAttemptDenied => _denied;

  /// True while content must be covered: either the lifecycle is not resumed
  /// or system UI opened by the app is still active.
  bool get obscured => _obscured;

  bool get relockEnabled => _relockEnabled;

  bool get requiresUnlock => _gate.requiresUnlock;

  /// Launch payload seam (U7; wired to real notifications in U8). Set by
  /// the shell before content shows; consumed by the profile home gate
  /// after the gate opens.
  String? get pendingLaunchProfileId => _pendingLaunchProfileId;

  void setPendingLaunchProfileId(String? id) {
    _pendingLaunchProfileId = id;
    notifyListeners();
  }

  void clearPendingLaunchProfileId() {
    if (_pendingLaunchProfileId == null) return;
    _pendingLaunchProfileId = null;
    notifyListeners();
  }

  /// Subscribes the inactivity toggle to the persisted setting (read after
  /// the database opens, so it is not available at construction).
  void attachSettings(SettingsStore store) {
    _relockSub?.cancel();
    _relockSub = store.watch(SettingsKeys.relockEnabled).listen((value) {
      _relockEnabled = value != 'false'; // absent ⇒ default ON (fail closed)
      if (_relockEnabled) {
        _armInactivity();
      } else {
        _inactivityTimer?.cancel();
        _inactivityTimer = null;
      }
      notifyListeners();
    });
  }

  /// Runs [action] inside a system-UI window (#65 U1; KTD2, KTD2a): while
  /// one is open, a lifecycle departure still covers the content but does
  /// not lock the app. Re-entrant.
  ///
  /// The window outlives [action] by [settleTimeout] rather than closing
  /// with it, because the platform can report the prompt's or picker's own
  /// dismissal after handing back the result. It is bounded the whole time
  /// by [systemUiDeadline].
  ///
  /// This is deliberately not "ignore `inactive`, act on `hidden`/`paused`":
  /// no lifecycle signal separates the app's own system UI from a real
  /// departure. On iOS a native modal presentation reports a spurious
  /// `hidden` while the app is fully foreground (flutter/flutter#146734);
  /// on Android the device-credential fallback launches a separate activity
  /// through `KeyguardManager` and genuinely reports `paused`.
  Future<T> duringSystemUi<T>(Future<T> Function() action) async {
    final epoch = _openSystemUiWindow();
    try {
      return await action();
    } finally {
      _closeSystemUiWindow(epoch);
    }
  }

  /// Drops the settling tail and the departure it was waiting to absorb.
  /// Every path that ends a window's life goes through here.
  void _cancelSettleTail() {
    _settling = false;
    _settleTimer?.cancel();
    _settleTimer = null;
    _departedDuringWindow = false;
  }

  int _openSystemUiWindow() {
    if (_systemUiWindows > 0) {
      _systemUiWindows++;
      return _systemUiEpoch!;
    }
    final settlingEpoch = _systemUiEpoch;
    if (settlingEpoch != null) _reconcileWindowClose(settlingEpoch);
    final epoch = ++_nextSystemUiEpoch;
    _systemUiEpoch = epoch;
    _systemUiWindows = 1;
    final wasObscured = _obscured;
    _obscured = true;
    // Suspend the foreground idle countdown for the window's duration. It
    // reaches `lock()`, which has no suppression check, so a countdown
    // already near its deadline would otherwise lock the app mid-ceremony
    // — and no pointer events arrive while system UI is up, so
    // `noteActivity` cannot refresh it. `_reconcileWindowClose` re-arms it.
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _systemUiTimer?.cancel();
    _systemUiTimer = inactivityTimerFactory(
        systemUiDeadline, () => _systemUiDeadlineExpired(epoch));
    if (!wasObscured) notifyListeners();
    return epoch;
  }

  void _closeSystemUiWindow(int epoch) {
    if (_disposed || _systemUiEpoch != epoch) return;
    if (_systemUiWindows == 0) return;
    _systemUiWindows--;
    if (_systemUiWindows > 0) return;
    if (_resumed && _obscured) {
      _obscured = false;
      notifyListeners();
    }
    _settling = true;
    _settleTimer?.cancel();
    _settleTimer = inactivityTimerFactory(
        settleTimeout, () => _onSettleTimeout(epoch));
  }

  /// The settle timer fired. Guarded because a cancelled-but-already-queued
  /// timer, or a window reopened during the tail, must not reconcile twice.
  void _onSettleTimeout(int epoch) {
    if (_disposed || !_settling || _systemUiEpoch != epoch) return;
    _reconcileWindowClose(epoch);
  }

  /// End of a window's life: the cover is reconciled against the
  /// lifecycle (#65 KTD9 — never assigned blind, or a grant landing off-screen
  /// uncovers data and a closing window strands an opaque cover with no
  /// lock screen behind it), and [reauthenticate]'s narrowed replay fires
  /// if the operator is still away (#65 KTD4).
  void _reconcileWindowClose(int epoch) {
    if (_systemUiEpoch != epoch) return;
    // The departure this window absorbed is answered here, and the answer
    // is fail-closed: if the operator has not come back by the time the
    // system UI is down, the departure takes effect. Anything softer is a
    // hole — cancelling the window deadline (above) and leaning on
    // `_armInactivity` would leave a device the operator walked away from
    // unlocked, and with the relock toggle off it would arm nothing at
    // all. That is strictly weaker than the behaviour this change
    // replaced, which locked on every departure.
    final unanswered = _departedDuringWindow && !_resumed;
    _systemUiTimer?.cancel();
    _systemUiTimer = null;
    _systemUiWindows = 0;
    _systemUiEpoch = null;
    _cancelSettleTail();
    if (unanswered) {
      _obscured = true;
      lock();
      return;
    }
    final wasObscured = _obscured;
    _obscured = !_resumed;
    _armInactivity();
    // The cover is the only thing a listener can observe here, and the
    // common case — an ordinary prompt that came and went with the app in
    // the foreground throughout — leaves it unchanged. Notifying anyway
    // would rebuild the whole shell on every unlock for nothing.
    if (_obscured != wasObscured) notifyListeners();
  }

  /// [reauthenticate]'s narrowed replay (#65 KTD4): the operator is still away
  /// now that the prompt is down, so the departure the window suppressed
  /// takes effect. Runs immediately rather than waiting out the settling
  /// tail — the tail exists to absorb a *returning* app's trailing
  /// transitions, and there is nothing to wait for when the operator has
  /// not come back.
  void _replayDeparture() {
    _systemUiTimer?.cancel();
    _systemUiTimer = null;
    _systemUiWindows = 0;
    _systemUiEpoch = null;
    _cancelSettleTail();
    _obscured = true;
    lock();
  }

  /// The window outstayed its bound (#65 KTD5). Lock unconditionally — this is
  /// the whole guarantee behind suppressing the lock in the first place,
  /// so it ignores the relock toggle, pointer activity, and nesting.
  void _systemUiDeadlineExpired(int epoch) {
    if (_disposed || _systemUiEpoch != epoch) return;
    _systemUiTimer = null;
    _systemUiWindows = 0;
    _systemUiEpoch = null;
    _generation++;
    _cancelSettleTail();
    // Release the prompt too. A credential request that never returns is
    // exactly why this deadline exists, and leaving the flag set would
    // leave the operator on a lock screen whose Unlock button is disabled
    // forever — the same dead end this change set out to remove.
    _authenticating = false;
    _obscured = !_resumed;
    lock();
  }

  /// Presents the device credential. Stays locked on any decline — the app
  /// never shows data and never exits (the lock screen offers retry).
  ///
  /// The credential's own result is what decides (#65 U1; KTD1). A
  /// lifecycle departure observed while the prompt was up no longer
  /// discards a grant: that check could never be implemented correctly,
  /// and on iOS — where the Face ID prompt reports `inactive` itself — it
  /// meant the app could not be unlocked at all (issue #65).
  Future<void> unlock() async {
    if (!_locked || _authenticating) return;
    _authenticating = true;
    notifyListeners();
    final generation = _generation;
    try {
      final granted = await duringSystemUi(_gate.requestAccess);
      if (_disposed || generation != _generation) {
        // The window deadline already locked while this request hung.
        // Honouring the answer now would re-open the session behind it.
        return;
      }
      if (granted) {
        _denied = false;
        _locked = false;
        _armInactivity();
      } else {
        _denied = true;
      }
      // The cover is not cleared here: it is reconciled against the
      // lifecycle when the window settles (#65 KTD9).
    } finally {
      // Without this a throwing authenticator leaves the flag set and the
      // re-entrancy guard turns every later Unlock tap into a no-op.
      _authenticating = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// A fresh device-credential check for a sensitive action while the app
  /// is already unlocked — adding a sign-in method (#2 U5; KTD5). Returns
  /// true only when the credential was accepted and the app is resumed when
  /// the prompt completes; false for a decline, an unavailable authenticator,
  /// a still-away completion, or while another prompt is up.
  ///
  /// Runs inside a system-UI window like every other prompt, and the
  /// credential's own result is what it reports (#65 U1; KTD4). It used to
  /// return false whenever a lifecycle change arrived during the prompt,
  /// which the prompt's own `inactive` report triggered every time — so
  /// "Add Google" cancelled itself silently.
  ///
  /// The outcome never changes the lock state directly: a granted check
  /// does not unlock and a declined one does not lock (the caller simply
  /// cancels its action, like a dismissed picker). The departure replay
  /// survives in narrowed form — [unlock]'s rationale does not transfer
  /// here, since a re-auth is not what opens the app — and is keyed on
  /// whether the operator is *still away* when the window settles, not on
  /// which lifecycle events arrived. That is a level check at one known
  /// moment, which no ordering guarantee is needed to answer.
  Future<bool> reauthenticate() async {
    if (_authenticating) return false;
    _authenticating = true;
    notifyListeners();
    final generation = _generation;
    try {
      final granted = await duringSystemUi(_gate.requestAccess);
      if (_disposed || generation != _generation) return false;
      final interrupted = _departedDuringWindow && !_resumed;
      if (interrupted) _replayDeparture();
      // A caller that acts on `true` must not act after the app re-locked
      // underneath it, or "Add Google" launches its picker over the lock
      // screen and links while the operator is away.
      return granted && !interrupted;
    } finally {
      _authenticating = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Re-lock now. Backgrounding always calls this; on un-gated platforms it
  /// only sets the cover flag.
  void lock() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (_gate.requiresUnlock) {
      _locked = true;
    } else {
      // Un-gated (web): there is no lock screen to dismiss a cover with,
      // so only cover when the app is actually away.
      _obscured = !_resumed;
    }
    notifyListeners();
  }

  /// Called by the shell's [Listener] on every pointer event; restarts the
  /// inactivity countdown.
  void noteActivity() {
    if (_locked || !_relockEnabled) return;
    _armInactivity();
  }

  /// Note this never touches the system-UI window's deadline: pointer
  /// activity refreshes foreground idle time, and must not extend the
  /// bound on an open window (#65 KTD5).
  void _armInactivity() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (!_relockEnabled || _locked || _suppressingLock) return;
    _inactivityTimer = inactivityTimerFactory(
        inactivityTimeout, () => lock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resumed = true;
        if (_systemUiWindows == 0) _obscured = false;
        if (!_locked && !_suppressingLock) _armInactivity();
        notifyListeners();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _resumed = false;
        _departed();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Any departure from the foreground: cover the content (snapshots), and
  /// re-lock unless the app itself put the system UI on screen.
  ///
  /// The cover is set either way — a window suppresses the *lock*, never
  /// the snapshot posture. Outside a window the policy is unchanged, and
  /// `inactive` still re-locks: on iPad Slide Over and an iOS app-switcher
  /// peek it can be the only departure signal delivered, so narrowing it
  /// would under-lock.
  void _departed() {
    if (_suppressingLock) {
      // A multi-step departure (Android's credential fallback reports
      // inactive -> hidden -> paused for one prompt) reaches here three
      // times; only the first changes anything.
      final changed = !_obscured || !_departedDuringWindow;
      _obscured = true;
      _departedDuringWindow = true;
      if (changed) notifyListeners();
      return;
    }
    _obscured = true;
    lock();
  }

  @override
  void dispose() {
    // Set first: a `duringSystemUi` action still in flight will run its
    // close path when it finally resolves, and without this it would arm
    // fresh timers nothing will ever cancel and notify a disposed
    // ChangeNotifier.
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _systemUiTimer?.cancel();
    _settleTimer?.cancel();
    unawaited(_relockSub?.cancel());
    super.dispose();
  }
}
