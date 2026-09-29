/// `HealthBackgroundImportCoordinator`'s whole behavior (Issue #993) plus
/// the `lunarlog/health` trigger channel's Dart half
/// (`MethodChannelHealthBackgroundTrigger`), both driven by fakes / the
/// mock messenger — no health data is ever involved.
///
/// The coordinator's contract, one test each: the startup pull turns a
/// trigger that fired before Dart could listen into exactly one pass; a
/// pushed trigger runs one pass; an empty latch runs none; overlapping
/// triggers are dropped (never queued — the pipeline is idempotent and
/// reads the whole window every pass); a disposed coordinator hears
/// nothing; a throwing runner is a coarse log line, never a propagated
/// throw; and every log entry carries counts and deny-reason names only,
/// never a sample id or date.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_background_import_service.dart';
import 'package:lunarlog/data/health/health_background_import_trigger.dart';
import 'package:lunarlog/data/health/health_channel_codec.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';

const _channel = MethodChannel('lunarlog/health');

class _FakeTrigger implements HealthBackgroundImportTrigger {
  void Function()? listened;
  bool pendingPull = false;
  int pulls = 0;
  bool disposed = false;

  /// Simulates the platform firing the push (what iOS's observer handler
  /// and Android's worker both do through the real trigger).
  void fire() => listened?.call();

  @override
  void listen(void Function() onTrigger) {
    disposed = false;
    listened = onTrigger;
  }

  @override
  Future<bool> consumePendingTrigger() async {
    pulls++;
    return pendingPull;
  }

  @override
  void dispose() {
    disposed = true;
    listened = null;
  }
}

class _FakeRunner implements HealthBackgroundImportRunner {
  int calls = 0;

  /// What the next pass returns; a not-yet-completed [completer] holds the
  /// pass open so a test can fire a second trigger while one runs.
  HealthImportSummary result = const HealthImportSummary();
  Completer<HealthImportSummary>? completer;
  Object? throw_;

  @override
  HealthImportPlatform get platform => HealthImportPlatform.appleHealth;

  @override
  Future<HealthImportSummary> importInBackground() async {
    calls++;
    if (throw_ != null) throw throw_!;
    final held = completer;
    if (held != null) return held.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTrigger trigger;
  late _FakeRunner runner;
  late HealthBackgroundImportCoordinator coordinator;

  setUp(() {
    trigger = _FakeTrigger();
    runner = _FakeRunner();
    coordinator = HealthBackgroundImportCoordinator(
      trigger: trigger,
      runner: runner,
    );
    defaultBreadcrumbLog.clear();
  });

  tearDown(() {
    coordinator.dispose();
    defaultBreadcrumbLog.clear();
  });

  group('HealthBackgroundImportCoordinator', () {
    test('the startup pull runs one pass when a trigger fired before '
        'Dart could listen', () async {
      trigger.pendingPull = true;

      await coordinator.start();

      expect(trigger.pulls, 1);
      expect(runner.calls, 1);
    });

    test('an empty latch runs no pass', () async {
      await coordinator.start();

      expect(trigger.pulls, 1);
      expect(runner.calls, 0);
    });

    test('a pushed trigger after start runs one pass', () async {
      await coordinator.start();
      trigger.fire();

      expect(runner.calls, 1);
    });

    test(
      'an overlapping trigger while a pass runs is dropped, not queued',
      () async {
        final held = Completer<HealthImportSummary>();
        runner.completer = held;

        await coordinator.start();
        trigger.fire();
        expect(runner.calls, 1);

        // The second platform trigger lands while the first pass is still
        // running (HealthKit fires per read type; a WorkManager tick can
        // overlap an observer pass).
        trigger.fire();
        expect(runner.calls, 1);

        held.complete(const HealthImportSummary());
        // Let the pass's logging (and the dropped trigger's) settle. The skip
        // is logged the moment the overlap is detected — before the running
        // pass finishes — so it is matched anywhere in the ring, not as the
        // last entry.
        await pumpEventQueue();
        expect(runner.calls, 1);
        expect(
          defaultBreadcrumbLog.snapshot().any(
            (entry) => entry.contains('skippedOverlappingTrigger'),
          ),
          isTrue,
          reason:
              'expected a skippedOverlappingTrigger entry in '
              '${defaultBreadcrumbLog.snapshot()}',
        );
      },
    );

    test(
      'a pass that starts after the previous finished runs normally',
      () async {
        await coordinator.start();
        trigger.fire();
        await pumpEventQueue();
        trigger.fire();
        await pumpEventQueue();

        expect(runner.calls, 2);
      },
    );

    test('dispose stops the trigger from starting passes', () async {
      await coordinator.start();
      coordinator.dispose();

      trigger.fire();

      expect(runner.calls, 0);
      expect(trigger.disposed, isTrue);
    });

    test('a throwing runner is logged coarsely, never rethrown', () async {
      runner.throw_ = StateError('storage exploded');
      trigger.pendingPull = true;

      // start() itself awaits the pulled pass — it must not throw.
      await coordinator.start();

      expect(runner.calls, 1);
      expect(defaultBreadcrumbLog.snapshot().last, contains('failed'));
    });

    test('every log line is counts-only: no sample id, no date', () async {
      runner.result = const HealthImportSummary(
        samplesRead: 12,
        daysWritten: 2,
        daysUnchanged: 5,
        daysKeptManual: 1,
        spottingDaysWritten: 1,
      );

      await coordinator.start();
      trigger.fire();
      await pumpEventQueue();

      final entries = defaultBreadcrumbLog.snapshot();
      final line = entries.last;
      expect(line, startsWith('healthBackgroundImport: appleHealth'));
      expect(line, contains('imported(2+1)'));
      expect(line, contains('unchanged=5'));
      expect(line, contains('keptManual=1'));
      expect(line, contains('samples=12'));
      // The health-content markers a leak would carry.
      expect(line, isNot(contains('sample-')));
      expect(line, isNot(contains('2026')));
    });

    test('an unbound device logs the unbound outcome, not counts', () async {
      runner.result = const HealthImportSummary(bound: false);

      await coordinator.start();
      trigger.fire();
      await pumpEventQueue();

      expect(defaultBreadcrumbLog.snapshot().last, contains('unbound'));
    });

    test('a permission probe denial logs its own outcome', () async {
      runner.result = const HealthImportSummary(
        blocked: HealthPlatformPermissionDenied(),
      );

      await coordinator.start();
      trigger.fire();
      await pumpEventQueue();

      expect(
        defaultBreadcrumbLog.snapshot().last,
        contains('permissionNotGranted'),
      );
    });

    test('a guard refusal logs the deny reason', () async {
      runner.result = const HealthImportSummary(
        blocked: HealthPlatformResult.refused(HealthSyncCheck.notOwner),
      );

      await coordinator.start();
      trigger.fire();
      await pumpEventQueue();

      expect(
        defaultBreadcrumbLog.snapshot().last,
        contains('guardRefused(notOwner)'),
      );
    });
  });

  group('MethodChannelHealthBackgroundTrigger', () {
    late MethodChannelHealthBackgroundTrigger impl;

    setUp(() {
      impl = MethodChannelHealthBackgroundTrigger();
    });

    tearDown(() {
      impl.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    /// Delivers one platform→Dart message on the shared channel, returning
    /// the raw reply (what the native side's callback would receive). Null
    /// is the channel's not-implemented signal; any non-null envelope is an
    /// ack from the registered listener.
    Future<ByteData?> pushFromPlatform(String method) async {
      final message = _channel.codec.encodeMethodCall(MethodCall(method));
      ByteData? reply;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _channel.name,
            message,
            (data) => reply = data,
          );
      return reply;
    }

    test('the native push reaches the listener and is answered with a '
        'non-null ack', () async {
      var fired = 0;
      impl.listen(() => fired++);

      final reply = await pushFromPlatform(
        HealthChannelMethods.onBackgroundImportTriggered,
      );

      expect(fired, 1);
      // The ack is deliberately non-null (an empty reply IS the channel's
      // not-implemented signal, which the native caller would misread as
      // nobody-listening): it decodes to the Bool ack the Swift/Kotlin
      // push sites both treat as delivered.
      expect(reply, isNotNull);
      expect(_channel.codec.decodeEnvelope(reply!), isTrue);
    });

    test(
      'a second push fires the listener again (each delivery is one ask)',
      () async {
        var fired = 0;
        impl.listen(() => fired++);

        await pushFromPlatform(
          HealthChannelMethods.onBackgroundImportTriggered,
        );
        await pushFromPlatform(
          HealthChannelMethods.onBackgroundImportTriggered,
        );

        expect(fired, 2);
      },
    );

    test(
      'an unknown method on the channel is not answered by this listener',
      () async {
        var fired = 0;
        impl.listen(() => fired++);

        final reply = await pushFromPlatform('readMenstrualFlowPage');

        expect(fired, 0);
        // The listener rethrows MissingPluginException for methods it does
        // not speak, which the channel wrapper turns into the empty
        // not-implemented envelope — the caller sees not-implemented, never
        // a fake success. (An empty reply is exactly what decodeEnvelope
        // surfaces as MissingPluginException on the caller's side.)
        expect(reply, isNull);
      },
    );

    test(
      'consumePendingTrigger returns the native latch and clears it',
      () async {
        var latch = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
              expect(
                call.method,
                HealthChannelMethods.consumePendingBackgroundImportTrigger,
              );
              final value = latch;
              latch = false;
              return value;
            });

        expect(await impl.consumePendingTrigger(), isTrue);
        expect(await impl.consumePendingTrigger(), isFalse);
      },
    );

    test('a null latch answer degrades to false, never to a trigger', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => null);

      expect(await impl.consumePendingTrigger(), isFalse);
    });

    test('a channel with no native half degrades to false (the degraded '
        'probe is not a trigger)', () async {
      // No mock handler: the invoke throws MissingPluginException inside
      // the platform messenger, exactly as an unmocked (or unsupported)
      // platform would.
      expect(await impl.consumePendingTrigger(), isFalse);
    });

    test('dispose clears the listener', () async {
      var fired = 0;
      impl.listen(() => fired++);
      impl.dispose();

      final reply = await pushFromPlatform(
        HealthChannelMethods.onBackgroundImportTriggered,
      );

      expect(fired, 0);
      // Nobody listens anymore: the caller sees the empty not-implemented
      // reply.
      expect(reply, isNull);
    });
  });
}
