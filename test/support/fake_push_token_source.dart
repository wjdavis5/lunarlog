/// Hand-written [PushTokenSource] fake (Issue #5, U7), matching
/// `test/support/fake_sync_engine.dart`'s convention: controllable streams
/// plus a settable current token, so coordinator tests never touch
/// firebase_messaging.
library;

import 'dart:async';

import 'package:lunarlog/domain/notifications/push_registration.dart';

class FakePushTokenSource implements PushTokenSource {
  String? tokenToReturn;
  final StreamController<String> _refreshes = StreamController<String>.broadcast();
  final StreamController<String?> _taps = StreamController<String?>.broadcast();

  int currentTokenCalls = 0;

  @override
  Future<String?> currentToken() async {
    currentTokenCalls++;
    return tokenToReturn;
  }

  @override
  Stream<String> tokenRefreshes() => _refreshes.stream;

  @override
  Stream<String?> taps() => _taps.stream;

  void emitRefresh(String token) => _refreshes.add(token);

  void emitTap(String? profileId) => _taps.add(profileId);

  /// Round-2 review #4: FirebasePushTokenSource's real `tokenRefreshes()`/
  /// `taps()` are `async*` generators that surface an init failure as a
  /// stream *error* event (not a data event) -- these let coordinator tests
  /// exercise that without touching the real, plugin-bound class.
  void emitRefreshError(Object error) => _refreshes.addError(error);

  void emitTapError(Object error) => _taps.addError(error);

  Future<void> close() async {
    await _refreshes.close();
    await _taps.close();
  }
}
