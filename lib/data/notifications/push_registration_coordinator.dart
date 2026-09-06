/// Auth-state-driven push registration (Issue #5, U7; R17-R19). Registers
/// [deviceId]'s current token (and every refresh) while signed in; removes
/// this device's registration on sign-out. Fully testable against fakes -
/// mirrors `lib/data/notifications/reminder_coordinator.dart`'s disposal
/// discipline.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/notifications/push_registration.dart';

class PushRegistrationCoordinator {
  PushRegistrationCoordinator({
    required PushTokenSource tokenSource,
    required PushDeviceRegistry registry,
    required String deviceId,
    required String platform,
    required Stream<AuthSessionState> authStates,
    required AuthSessionState Function() currentAuthState,
    void Function(String profileId)? onTap,
  })  : _tokenSource = tokenSource,
        _registry = registry,
        _deviceId = deviceId,
        _platform = platform,
        _authStates = authStates,
        _currentAuthState = currentAuthState,
        _onTap = onTap;

  final PushTokenSource _tokenSource;
  final PushDeviceRegistry _registry;
  final String _deviceId;
  final String _platform;
  final Stream<AuthSessionState> _authStates;
  final AuthSessionState Function() _currentAuthState;
  final void Function(String profileId)? _onTap;

  StreamSubscription<AuthSessionState>? _authSub;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<String?>? _tapSub;
  bool _signedIn = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) return;
    _signedIn = _currentAuthState() == AuthSessionState.signedIn;
    _authSub = _authStates.listen(_onAuthState);
    _refreshSub = _tokenSource.tokenRefreshes().listen(_onTokenRefresh);
    _tapSub = _tokenSource.taps().listen(_onTap == null
        ? null
        : (profileId) {
            if (profileId != null) _onTap(profileId);
          });
    if (_signedIn) {
      await _registerCurrentToken();
    }
  }

  void _onAuthState(AuthSessionState state) {
    if (_disposed) return;
    final signedIn = state == AuthSessionState.signedIn;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      unawaited(_registerCurrentToken());
    } else {
      unawaited(_safeRemove());
    }
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await _tokenSource.currentToken();
      if (token == null || !_signedIn || _disposed) return;
      await _registry.register(_deviceId, token, platform: _platform);
    } catch (_) {
      // Best-effort; a later refresh or app restart retries.
    }
  }

  void _onTokenRefresh(String token) {
    if (_disposed || !_signedIn) return;
    unawaited(_safeRegister(token));
  }

  Future<void> _safeRegister(String token) async {
    try {
      await _registry.register(_deviceId, token, platform: _platform);
    } catch (_) {
      // Best-effort; a subsequent refresh still attempts registration.
    }
  }

  Future<void> _safeRemove() async {
    try {
      await _registry.remove(_deviceId);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _authSub?.cancel();
    _authSub = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    await _tapSub?.cancel();
    _tapSub = null;
  }
}
