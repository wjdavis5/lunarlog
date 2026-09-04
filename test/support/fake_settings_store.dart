/// In-memory [SettingsStore] for tests that need real settings behaviour —
/// a seeded value delivered on subscribe, then every change — without
/// standing up a database.
///
/// Lives in `test/support/` so the next test needing one imports it rather
/// than hand-rolling a fifth copy; `test/ui/account_test.dart`,
/// `test/ui/settings_test.dart`, and `test/ui/gate_test.dart` each grew
/// their own before this existed.
library;

import 'dart:async';

import 'package:lunarlog/domain/repositories/settings_store.dart';

class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;
  final _controllers = <String, StreamController<String?>>{};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async {
    _values[key] = value;
    _controllers[key]?.add(value);
  }

  @override
  Stream<String?> watch(String key) {
    final controller = _controllers.putIfAbsent(
        key, () => StreamController<String?>.broadcast());
    return _seeded(_values[key], controller.stream);
  }

  static Stream<String?> _seeded(String? seed, Stream<String?> changes) async* {
    yield seed;
    yield* changes;
  }

  /// Closes every watch stream. Call from `addTearDown` so a subscription
  /// does not outlive the test.
  void close() {
    for (final controller in _controllers.values) {
      controller.close();
    }
  }
}
