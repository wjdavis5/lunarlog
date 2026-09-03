/// Session gate lifecycle (U7, R7, flow F3, AE4): the gate controller and
/// the app root that enforces it.
///
/// * Cold start: gated platforms show the lock screen *before any profile
///   data renders* and *before the database is opened* — a declined
///   credential never decrypts anything (AE4).
/// * Re-lock: backgrounding (paused/hidden — and `inactive`, which is what
///   split-screen/multi-window focus loss reports) always re-locks;
///   foreground inactivity re-locks after a timeout (default 2 minutes,
///   toggleable via [SettingsKeys.relockEnabled], default on).
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
/// This file is composition-root territory (like `main.dart`): it is
/// allowed to touch `lib/data` types to wire the drift settings store into
/// the controller.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/gate/app_gate.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';
import 'package:lunarlog/ui/startup/fail_closed_screen.dart';
import 'package:provider/provider.dart';

/// Platform channel used to set Android FLAG_SECURE (snapshot/screenshot
/// suppression at the window level). Best effort — see
/// [applyPlatformPrivacyProtections].
const String kPrivacyChannel = 'lunarlog/privacy';

/// v1 inactivity auto-relock timeout (fixed; the settings screen shows it).
const Duration kDefaultInactivityTimeout = Duration(minutes: 2);

/// Best-effort platform privacy hardening, called once at root startup.
/// Currently: FLAG_SECURE on Android (blocks app-switcher snapshots and
/// screenshots natively). Failures are swallowed — the opaque lifecycle
/// cover remains the cross-platform baseline.
Future<void> applyPlatformPrivacyProtections() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel(kPrivacyChannel)
        .invokeMethod<void>('setFlagSecure', true);
  } catch (_) {
    // Best effort only.
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
  }) : _gate = gate {
    _locked = gate.requiresUnlock;
    WidgetsBinding.instance.addObserver(this);
  }

  final AppGate _gate;
  final Duration inactivityTimeout;
  final InactivityTimerFactory inactivityTimerFactory;

  bool _locked = false;
  bool _authenticating = false;
  bool _denied = false;
  bool _obscured = false;
  bool _relockEnabled = true;
  bool _lifecycleDuringAuth = false;
  String? _pendingLaunchProfileId;
  InactivityTimer? _inactivityTimer;
  StreamSubscription<String?>? _relockSub;

  bool get locked => _locked;

  bool get unlocked => !_locked;

  bool get authenticating => _authenticating;

  /// True when the last credential attempt was declined or unavailable.
  bool get lastAttemptDenied => _denied;

  /// True while content must be covered (lifecycle not resumed) — the
  /// app-switcher snapshot posture.
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

  /// Presents the device credential. Stays locked on any decline — the app
  /// never shows data and never exits (the lock screen offers retry).
  Future<void> unlock() async {
    if (!_locked || _authenticating) return;
    _authenticating = true;
    _lifecycleDuringAuth = false;
    notifyListeners();
    final granted = await _gate.requestAccess();
    _authenticating = false;
    if (granted && !_lifecycleDuringAuth) {
      _denied = false;
      _locked = false;
      _obscured = false;
      _armInactivity();
    } else {
      _denied = !granted;
      if (_lifecycleDuringAuth) {
        // The app left the foreground while the credential prompt was up
        // (the prompt itself reports `inactive`). Fail closed regardless
        // of the outcome: the next resume re-gates.
        _obscured = true;
        _locked = _gate.requiresUnlock || _locked;
        _inactivityTimer?.cancel();
        _inactivityTimer = null;
      }
    }
    _lifecycleDuringAuth = false;
    notifyListeners();
  }

  /// Re-lock now. Backgrounding always calls this; on un-gated platforms it
  /// only sets the cover flag.
  void lock() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (_gate.requiresUnlock) {
      _locked = true;
    } else {
      _obscured = true;
    }
    notifyListeners();
  }

  /// Called by the shell's [Listener] on every pointer event; restarts the
  /// inactivity countdown.
  void noteActivity() {
    if (_locked || _authenticating || !_relockEnabled) return;
    _armInactivity();
  }

  void _armInactivity() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (!_relockEnabled || _locked || _authenticating) return;
    _inactivityTimer = inactivityTimerFactory(
        inactivityTimeout, () => lock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _obscured = false;
        if (!_locked) _armInactivity();
        notifyListeners();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _departed();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Any departure from the foreground: cover the content (snapshots) and
  /// re-lock (split-screen focus loss reports `inactive`; the system
  /// credential prompt also reports `inactive`, which is why in-flight
  /// authentication is exempted and resolved fail-closed in [unlock]).
  void _departed() {
    if (_authenticating) {
      _lifecycleDuringAuth = true;
      return;
    }
    _obscured = true;
    lock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    unawaited(_relockSub?.cancel());
    super.dispose();
  }
}

/// App root and state machine: locked → (credential) → database open →
/// app; or locked forever on repeated declines; or fail-closed screen on
/// any open/quarantine/key failure. The database is opened only after the
/// first successful authentication on gated platforms (AE4).
class LunarLogRoot extends StatefulWidget {
  const LunarLogRoot({
    super.key,
    required this.gate,
    required this.dbOpener,
    this.launchProfileId,
    this.scheduler,
    this.authService,
    this.inactivityTimeout = kDefaultInactivityTimeout,
    this.inactivityTimerFactory = defaultInactivityTimerFactory,
  });

  final AppGate gate;

  /// Opens (and never quarantines silently — throws U2's typed errors).
  final Future<LunarLogDatabase> Function() dbOpener;

  /// Initial launch payload for the seam (U8 sets this for real).
  final String? launchProfileId;

  /// Reminder scheduler (U8); null disables reminders entirely.
  final ReminderScheduler? scheduler;

  /// Account auth service (U4), started by the bootstrap before the first
  /// frame; null when the build has no Supabase configuration (KTD11), in
  /// which case no account UI is provided at all.
  final AuthService? authService;

  final Duration inactivityTimeout;
  final InactivityTimerFactory inactivityTimerFactory;

  @override
  State<LunarLogRoot> createState() => _LunarLogRootState();
}

class _LunarLogRootState extends State<LunarLogRoot> {
  late final GateController _gate;
  LunarLogDatabase? _db;
  Object? _error;
  bool _opening = false;
  bool _firstUnlockAttempted = false;

  @override
  void initState() {
    super.initState();
    _gate = GateController(
      gate: widget.gate,
      inactivityTimeout: widget.inactivityTimeout,
      inactivityTimerFactory: widget.inactivityTimerFactory,
    )..addListener(_onGateChanged);
    if (widget.launchProfileId != null) {
      _gate.setPendingLaunchProfileId(widget.launchProfileId);
    }
    unawaited(applyPlatformPrivacyProtections());
    if (_gate.unlocked) {
      // Un-gated platform (web): open straight away.
      unawaited(_openDatabase());
    } else {
      // Cold start presents the credential automatically (F3); every later
      // prompt after a decline or re-lock is an explicit retry tap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _firstUnlockAttempted || !_gate.locked) return;
        _firstUnlockAttempted = true;
        unawaited(_gate.unlock());
      });
    }
  }

  Future<void> _openDatabase() async {
    if (_opening || _db != null || _error != null) return;
    _opening = true;
    try {
      final db = await widget.dbOpener();
      _db = db;
      _gate.attachSettings(DriftSettingsStore(db.storage));
    } catch (error, stackTrace) {
      debugPrint('lunarlog startup failed: $error\n$stackTrace');
      _error = error;
    } finally {
      _opening = false;
      if (mounted) setState(() {});
    }
  }

  void _onGateChanged() {
    // AE4: nothing touches the database until a credential was accepted.
    if (_gate.unlocked && _db == null && _error == null) {
      unawaited(_openDatabase());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_error != null) {
      content = FailClosedApp(error: _error!);
    } else if (_db != null) {
      content = LunarLogApp(
        db: _db!,
        scheduler: widget.scheduler,
        authService: widget.authService,
      );
    } else if (_gate.locked) {
      // Behind the lock before the first unlock: a static, data-free
      // placeholder — nothing renders, not even a spinner.
      content = const MaterialApp(home: Scaffold(body: SizedBox.expand()));
    } else {
      content = const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    // The shell (Stack/Listener) renders *above* the content's
    // MaterialApp, so nothing else provides a text direction — not even in
    // the real app, where runApp() has no Directionality ancestor either.
    return ChangeNotifierProvider<GateController>.value(
      value: _gate,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GateShell(controller: _gate, child: content),
      ),
    );
  }
}

/// Wraps the app content with the activity listener and the lock/cover
/// layers. Content is kept offstage and input-blocked while hidden so no
/// data paints and no stray tap reaches it.
class GateShell extends StatelessWidget {
  const GateShell({super.key, required this.controller, required this.child});

  final GateController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateController>();
    final hidden = gate.locked || gate.obscured;
    return Listener(
      onPointerDown: (_) => gate.noteActivity(),
      onPointerMove: (_) => gate.noteActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AbsorbPointer(
            absorbing: hidden,
            child: Visibility(
              visible: !hidden,
              maintainState: true,
              child: child,
            ),
          ),
          if (gate.obscured && !gate.locked) const PrivacyCover(),
          if (gate.locked) LockScreen(controller: controller),
        ],
      ),
    );
  }
}

/// Opaque cover shown whenever the lifecycle is not resumed: the
/// app-switcher snapshot sees this, never data (R7).
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('privacy-cover'),
      color: Color(0xFF000000),
      child: SizedBox.expand(),
    );
  }
}
