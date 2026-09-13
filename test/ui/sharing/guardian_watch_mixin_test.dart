/// Issue #540: the guardian-watch subscriptions duplicated across
/// `MonthCalendar`/`OverviewPanel`/`TodayLogFab`/`AnalysisTab`/
/// `CareNotesScreen` never passed `onError` — a stream error would have
/// propagated as an unhandled root-zone async error rather than degrading.
/// These tests exercise the extracted helper/mixin directly rather than
/// each of the five call sites.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/sharing/guardian_watch_mixin.dart';

ProfileGuardian _guardian(String id) => ProfileGuardian(
      id: id,
      profileId: 'p1',
      userId: 'u1',
      role: GuardianRole.caregiver,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeGuardiansRepository implements ProfileGuardiansRepository {
  _FakeGuardiansRepository(this._controller);

  final StreamController<List<ProfileGuardian>> _controller;

  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      _controller.stream;

  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async =>
      const [];
}

/// Minimal harness exercising [GuardianWatchMixin] the same way each of
/// the five real call sites does: subscribe in `initState`, expose the
/// live list, cancel in `dispose`.
class _Harness extends StatefulWidget {
  const _Harness({required this.repository, required this.onGuardians});

  final ProfileGuardiansRepository repository;
  final void Function(List<ProfileGuardian>) onGuardians;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with GuardianWatchMixin<_Harness> {
  @override
  void initState() {
    super.initState();
    watchGuardiansForProfile(widget.repository, 'p1', widget.onGuardians);
  }

  @override
  void dispose() {
    disposeGuardianWatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(defaultBreadcrumbLog.clear);

  group('watchGuardiansForProfileSafely', () {
    test('a stream error is recorded and dropped, not propagated', () async {
      final controller = StreamController<List<ProfileGuardian>>();
      addTearDown(controller.close);
      final events = <List<ProfileGuardian>>[];
      final errors = <Object>[];

      watchGuardiansForProfileSafely(
        _FakeGuardiansRepository(controller),
        'p1',
      ).listen(events.add, onError: errors.add);

      controller.addError(StateError('boom'));
      await pumpEventQueue();

      expect(errors, isEmpty,
          reason: 'the error is intercepted and logged, never forwarded');
      expect(defaultBreadcrumbLog.snapshot(), isNotEmpty);
      expect(defaultBreadcrumbLog.snapshot().single, contains('guardianWatch'));
    });

    test('data after an error still arrives normally', () async {
      final controller = StreamController<List<ProfileGuardian>>();
      addTearDown(controller.close);
      final events = <List<ProfileGuardian>>[];

      watchGuardiansForProfileSafely(
        _FakeGuardiansRepository(controller),
        'p1',
      ).listen(events.add);

      controller.addError(StateError('boom'));
      controller.add([_guardian('g1')]);
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.single.id, 'g1');
    });
  });

  group('GuardianWatchMixin', () {
    testWidgets('resets to empty immediately, then delivers guardians',
        (tester) async {
      final controller = StreamController<List<ProfileGuardian>>();
      addTearDown(controller.close);
      final received = <List<ProfileGuardian>>[];

      await tester.pumpWidget(_Harness(
        repository: _FakeGuardiansRepository(controller),
        onGuardians: received.add,
      ));

      expect(received, [const <ProfileGuardian>[]],
          reason: 'the mixin resets synchronously before subscribing');

      controller.add([_guardian('g1')]);
      await tester.pump();

      expect(received.last.single.id, 'g1');
    });

    testWidgets('a stream error never crashes the widget tree',
        (tester) async {
      final controller = StreamController<List<ProfileGuardian>>();
      addTearDown(controller.close);
      final received = <List<ProfileGuardian>>[];

      await tester.pumpWidget(_Harness(
        repository: _FakeGuardiansRepository(controller),
        onGuardians: received.add,
      ));

      controller.addError(StateError('boom'));
      await tester.pump();

      // No FlutterError was recorded and the widget is still mounted --
      // an unhandled root-zone error from a raw .listen(onData) with no
      // onError is exactly what issue #540 reported.
      expect(tester.takeException(), isNull);
      expect(defaultBreadcrumbLog.snapshot(), isNotEmpty);

      controller.add([_guardian('g2')]);
      await tester.pump();
      expect(received.last.single.id, 'g2',
          reason: 'the subscription survives the error and keeps delivering');
    });

    testWidgets('dispose cancels the subscription', (tester) async {
      final controller = StreamController<List<ProfileGuardian>>.broadcast();
      addTearDown(controller.close);
      final received = <List<ProfileGuardian>>[];

      await tester.pumpWidget(_Harness(
        repository: _FakeGuardiansRepository(controller),
        onGuardians: received.add,
      ));
      await tester.pump();
      expect(controller.hasListener, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(controller.hasListener, isFalse);
    });
  });
}
