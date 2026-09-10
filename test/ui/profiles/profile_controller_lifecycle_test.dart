/// Regression coverage for issue #206 (C-17): `ProfileController.load()` is
/// fire-and-forget from `lib/app.dart`'s provider `create:`, and a device
/// reset (`resetDevice` in `lib/app_lifecycle.dart`) deliberately disposes
/// the whole app subtree — including this controller — while an in-flight
/// `load()` is parked on one of its storage reads. Before the fix,
/// `load()` had no disposed guard: `notifyListeners()` threw "A
/// ChangeNotifier was used after being disposed" as an unhandled zone
/// error, and subscriptions created after disposal were stored where
/// `dispose()` would never cancel them.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';

void main() {
  group('ProfileController.load() disposed guard (#206 C-17)', () {
    test('dispose() while load() is parked on each storage read in turn: '
        'load() completes without throwing, never loads, and never '
        'subscribes', () async {
      // The reads load() performs, in order: two settings gets around one
      // profiles list. Disposing while parked on read N exercises the
      // disposed-check that follows read N's await.
      const parkPoints = 3;
      for (var parkAt = 0; parkAt < parkPoints; parkAt++) {
        final settings = _BlockingSettingsStore();
        final profiles = _ManualProfilesRepository();
        final controller = ProfileController(
          profilesRepository: profiles,
          settingsStore: settings,
        );

        // Fire-and-forget, exactly like app.dart's `..load()`.
        final load = controller.load();
        await _advanceLoadToParkPoint(settings, profiles, parkAt);

        // The reset disposes the controller while a storage read is still
        // pending.
        controller.dispose();

        // Whatever read load() is parked on still settles afterwards — the
        // database is being torn down, but the read completes.
        _completeReadAt(settings, profiles, parkAt);
        await expectLater(load, completes,
            reason: 'parked at read $parkAt');

        expect(controller.loaded, isFalse,
            reason: 'an in-flight load() that loses the race against '
                'dispose() must never flip to loaded, let alone '
                'notifyListeners()');
        expect(profiles.watchListenCount, 0,
            reason: 'load() must bail before subscribing to profiles.watch() '
                '(parked at read $parkAt)');
        expect(settings.watchCallCount, 0,
            reason: 'load() must bail before subscribing to the settings '
                'watch (parked at read $parkAt)');
      }
    });

    test('dispose() landing after the final disposed-check but before the '
        'watches are stored: subscriptions created by the in-flight load() '
        'are cancelled, not left live', () async {
      final settings = _BlockingSettingsStore();
      final profiles = _ManualProfilesRepository();
      // The disposal lands inside load()'s subscribe-and-store window —
      // modelled by hooking dispose() into the profiles.watch() listen
      // itself (no await separates that window in load(), so a synchronous
      // hook is the only way to interleave).
      final controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: settings,
      );
      profiles.onWatchListen = controller.dispose;

      final load = controller.load();
      await _advanceLoadToParkPoint(settings, profiles, 3);
      await expectLater(load, completes);

      await pumpEventQueue();
      expect(profiles.watchLive, isFalse,
          reason: 'a subscription created after disposal must be cancelled '
              'rather than stored where dispose() will never see it');
      expect(settings.watchLive, isFalse);
    });

    test('an undisposed load() still reaches the watches (happy path is '
        'unchanged)', () async {
      final settings = _BlockingSettingsStore();
      final profiles = _ManualProfilesRepository();
      final controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: settings,
      );
      addTearDown(controller.dispose);
      addTearDown(settings.closeAll);
      addTearDown(profiles.closeAll);

      final load = controller.load();
      await _advanceLoadToParkPoint(settings, profiles, 3);
      await expectLater(load, completes);

      expect(controller.loaded, isTrue);
      expect(profiles.watchListenCount, 1);
      expect(settings.watchCallCount, 1);
    });
  });
}

/// Advances an in-flight [load] until it is parked on storage read
/// [parkAt] (0-based: 0 = first settings get, 1 = profiles list, 2 = second
/// settings get); 3 runs the whole sequence to completion. Every
/// completion needs a queue pump before load() reaches the next read.
Future<void> _advanceLoadToParkPoint(
  _BlockingSettingsStore settings,
  _ManualProfilesRepository profiles,
  int parkAt,
) async {
  for (var read = 0; read < parkAt; read++) {
    _completeReadAt(settings, profiles, read);
    await pumpEventQueue();
  }
}

/// Completes the storage read at index [read]: 0 and 2 are settings gets,
/// 1 is the profiles list.
void _completeReadAt(
  _BlockingSettingsStore settings,
  _ManualProfilesRepository profiles,
  int read,
) {
  switch (read) {
    case 0:
    case 2:
      settings.completeNextGet(null);
    case 1:
      profiles.completeNextList(const []);
  }
}

/// [SettingsStore] whose `get()` futures are completed manually by the
/// test, in call order — so the test can park `load()` mid-flight and
/// dispose the controller while a read is pending.
class _BlockingSettingsStore implements SettingsStore {
  final _pendingGets = <Completer<String?>>[];
  final _watchStreams = <_TrackedWatch>[];
  int watchCallCount = 0;

  void completeNextGet(String? value) {
    _pendingGets.removeAt(0).complete(value);
  }

  @override
  Future<String?> get(String key) {
    final completer = Completer<String?>();
    _pendingGets.add(completer);
    return completer.future;
  }

  @override
  Future<void> set(String key, String value) async {}

  @override
  Stream<String?> watch(String key) {
    watchCallCount++;
    final stream = _TrackedWatch();
    _watchStreams.add(stream);
    return stream;
  }

  bool get watchLive =>
      _watchStreams.any((stream) => stream.subscribed && !stream.cancelled);

  void closeAll() {
    for (final stream in _watchStreams) {
      stream.close();
    }
  }
}

/// [ProfilesRepository] whose `list()` future is completed manually by the
/// test, and whose `watch()` streams track their subscription lifecycle.
/// Nothing else is exercised in these tests.
class _ManualProfilesRepository implements ProfilesRepository {
  final _pendingLists = <Completer<List<Profile>>>[];
  final _watchStreams = <_TrackedWatch>[];
  int watchListenCount = 0;

  /// Synchronous hook fired when [watch] is listened to — the one place a
  /// disposal can interleave with load()'s subscribe-and-store window.
  void Function()? onWatchListen;

  void completeNextList(List<Profile> profiles) {
    _pendingLists.removeAt(0).complete(profiles);
  }

  bool get watchLive =>
      _watchStreams.any((stream) => stream.subscribed && !stream.cancelled);

  @override
  Future<List<Profile>> list() {
    final completer = Completer<List<Profile>>();
    _pendingLists.add(completer);
    return completer.future;
  }

  @override
  Stream<List<Profile>> watch() {
    final stream = _TrackedWatch(onListen: onWatchListen);
    _watchStreams.add(stream);
    watchListenCount++;
    // The mapped view is type-compatible with the repository contract while
    // keeping the subscription tracking on the underlying stream.
    return stream.map<List<Profile>>((_) => const <Profile>[]);
  }

  void closeAll() {
    for (final stream in _watchStreams) {
      stream.close();
    }
  }

  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError('not exercised in the lifecycle tests');

  @override
  Future<Profile> update(Profile profile) =>
      throw UnimplementedError('not exercised in the lifecycle tests');

  @override
  Future<Profile?> findById(String id) =>
      throw UnimplementedError('not exercised in the lifecycle tests');

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError('not exercised in the lifecycle tests');

  @override
  Future<void> delete(String id) =>
      throw UnimplementedError('not exercised in the lifecycle tests');
}

/// A watch stream that records whether it was ever subscribed to and
/// whether that subscription has been cancelled.
class _TrackedWatch extends Stream<String?> {
  _TrackedWatch({this.onListen}) {
    _controller.onCancel = () {
      cancelled = true;
    };
  }

  /// Synchronous hook fired when this stream is listened to.
  final void Function()? onListen;

  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();
  bool subscribed = false;
  bool cancelled = false;

  @override
  StreamSubscription<String?> listen(
    void Function(String?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    subscribed = true;
    onListen?.call();
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<void> close() => _controller.close();
}
