/// The shared Dart half of the `lunarlog/health` first-party platform
/// channel (Issue #173) — the one implementation behind both
/// `IOSHealthChannel` and `AndroidHealthChannel` (they pin this to each
/// platform's native counterpart; see those files). Follows the
/// `PasskeyCeremonyClient` precedent: a platform adapter behind a pure
/// domain port ([HealthPlatformStore]), with an [UnsupportedHealthPlatform]
/// default that fails cleanly on platforms with no native half.
///
/// **Guard ordering — the property this class exists to enforce on the
/// Dart side:** every guarded method evaluates
/// `HealthSyncBinding.canWrite` FIRST (with the profile, session, and
/// ownership facts from [HealthGuardFacts], plus [minorBindingAllowed])
/// and returns `refused(check)` without a single channel invocation when
/// denied — proven by `test/data/health/health_channel_test.dart` against
/// a fake MethodChannel asserting zero invocations on every deny reason.
/// When the Dart guard allows, the call crosses the channel carrying the
/// same facts so the native handler re-evaluates the mirrored predicate
/// against its OWN natively-stored binding (`UserDefaults` /
/// `SharedPreferences`) before touching `HKHealthStore` /
/// `HealthConnectClient` at all — the native half of the invariant, which
/// no Dart-side bug can bypass. The deliberate duplication of the
/// predicate (Dart + Swift + Kotlin) is the safety property issue #173
/// demands: the two sides cannot share code, and each must fail closed
/// on disagreement (a write only proceeds when BOTH the Dart-stored and
/// natively-stored bindings name the written profile).
///
/// Not coverage-excluded: every branch here is driven under `flutter
/// test` through `TestDefaultBinaryMessengerBinding`'s mock channel
/// handler (the same technique `notification_scheduler_test.dart` uses),
/// so the guard-ordering logic stays inside the quality gates' view.
/// Only the two platform-pinning files are excluded — see
/// `tool/quality/exclusions.dart`.
library;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import '../../domain/health/day_boundary.dart';
import '../../domain/health/health_platform.dart';
import '../../domain/health/health_sync_binding.dart';
import 'android_health_channel.dart';
import 'health_channel_codec.dart';
import 'ios_health_channel.dart';

/// The channel both native halves answer on (`ios/Runner/AppDelegate.swift`
/// and `android/.../HealthConnectAdapter.kt`), following the
/// `lunarlog/privacy` naming precedent.
const String kHealthChannelName = 'lunarlog/health';

/// Shared [HealthPlatformStore] implementation over one [MethodChannel].
///
/// [minorBindingAllowed] is a constructor parameter precisely so
/// production wiring passes `AppConfig.healthSyncMinorBindingAllowed`
/// and nothing else — the same single-source rule
/// `health_sync_policy.dart` states for every other caller; tests pass
/// their own value.
class MethodChannelHealthPlatform implements HealthPlatformStore {
  MethodChannelHealthPlatform({
    this.channel = const MethodChannel(kHealthChannelName),
    required this.binding,
    required this.minorBindingAllowed,
  });

  final MethodChannel channel;
  final HealthSyncBinding binding;
  final bool minorBindingAllowed;

  /// The Dart-side guard every guarded method runs before any channel
  /// invocation. Kept as one helper so the ordering cannot drift between
  /// methods: each method is literally
  /// `_guard(facts) ?? await _invokeGuarded(...)`. Null means "allowed —
  /// proceed to the channel"; a non-null result is the refusal to return
  /// instead.
  Future<HealthPlatformResult?> _guard(HealthGuardFacts facts) async {
    final check = await binding.canWrite(
      profile: facts.profile,
      signedInUserId: facts.signedInUserId,
      ownerUserId: facts.ownerUserId,
      minorBindingAllowed: minorBindingAllowed,
    );
    if (check.isAllowed) return null;
    return HealthPlatformResult.refused(check);
  }

  /// Sends one guarded call. [dayArgs]/[payloadArgs] are *builders*, not
  /// maps: they are evaluated only after the guard allowed, so (a) a
  /// denied write never even computes — let alone throws on — a day
  /// envelope, and (b) an unresolvable time zone becomes a `failed`
  /// result, never an exception across the port boundary. Result decoded
  /// via the codec; [PlatformException]/[MissingPluginException] mapped
  /// to typed outcomes.
  Future<HealthPlatformResult> _invokeGuarded(
    String method,
    HealthGuardFacts facts, {
    Map<String, Object?> Function()? dayArgs,
    Map<String, Object?> Function()? payloadArgs,
  }) async {
    final refused = await _guard(facts);
    if (refused != null) return refused;
    try {
      final raw = await channel.invokeMethod<Object?>(method, {
        ...encodeGuardArgs(facts, minorBindingAllowed: minorBindingAllowed),
        ...?dayArgs?.call(),
        ...?payloadArgs?.call(),
      });
      return decodeHealthResult(raw);
    } on PlatformException catch (error) {
      return _platformFailure(method, error);
    } on MissingPluginException {
      // No native handler registered (web/desktop, or a native side that
      // predates this channel) — the honest answer is "no health store
      // here", matching `isAvailable`'s false on those platforms.
      return const HealthPlatformResult.unavailable();
    } on ArgumentError {
      return const HealthPlatformResult.failed('invalid channel arguments');
    } on TimeZoneResolutionException catch (error) {
      return HealthPlatformResult.failed(
        'unresolvable time zone for $method: $error',
      );
    } on Exception catch (error) {
      return HealthPlatformResult.failed('$method failed: $error');
    }
  }

  HealthPlatformResult _platformFailure(
    String method,
    PlatformException error,
  ) =>
      switch (error.code) {
        'unavailable' => const HealthPlatformResult.unavailable(),
        'permissionDenied' => const HealthPlatformResult.permissionDenied(),
        _ => HealthPlatformResult.failed(
            '$method failed (${error.code}): ${error.message}',
          ),
      };

  @override
  Future<bool> isAvailable() async {
    try {
      return await channel.invokeMethod<bool>(
            HealthChannelMethods.isAvailable,
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) =>
      _invokeGuarded(HealthChannelMethods.bind, facts);

  @override
  Future<void> unbindProfile() async {
    try {
      await channel.invokeMethod<Object?>(HealthChannelMethods.unbind);
    } on PlatformException {
      // Best effort, mirroring HealthSyncBinding.unbind's tolerance: a
      // stale native binding can only fail closed (deny every write), so
      // there is nothing to recover from here.
    } on MissingPluginException {
      // Same: nothing native to clear.
    }
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) =>
      _invokeGuarded(HealthChannelMethods.requestWriteAuthorization, facts);

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) =>
      _invokeGuarded(
        HealthChannelMethods.writeMenstrualFlow,
        write.facts,
        dayArgs: () => encodeDayArgs(write.date, write.tzName),
        payloadArgs: () => {
          'flow': write.flow.toWire(),
          'cycleStart': write.cycleStart,
        },
      );

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) =>
      _invokeGuarded(
        HealthChannelMethods.writeIntermenstrualBleeding,
        write.facts,
        dayArgs: () => encodeDayArgs(write.date, write.tzName),
      );
}

/// The default [HealthPlatformStore] for platforms with no native half
/// (web, desktop) — the `UnsupportedPasskeyCeremonyClient` pattern: pure
/// Dart, no plugin import, deliberately NOT coverage-excluded because
/// "an unsupported platform fails cleanly, never crashes" is itself the
/// testable behavior. Guarded methods answer `unavailable()` without
/// touching any channel; `isAvailable()` is `false`.
class UnsupportedHealthPlatform implements HealthPlatformStore {
  const UnsupportedHealthPlatform();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformResult.unavailable();

  @override
  Future<void> unbindProfile() async {}

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformResult.unavailable();

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async =>
      const HealthPlatformResult.unavailable();

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) async =>
      const HealthPlatformResult.unavailable();
}

/// Production wiring entry: the platform adapter for [platform]
/// (defaults to `defaultTargetPlatform`), or
/// [UnsupportedHealthPlatform] wherever no native half exists — web
/// above all (health-store sync is a native-only feature, like push).
HealthPlatformStore createHealthPlatform(
  TargetPlatform? platform, {
  required HealthSyncBinding binding,
  required bool minorBindingAllowed,
}) {
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return IOSHealthChannel(
        binding: binding,
        minorBindingAllowed: minorBindingAllowed,
      );
    case TargetPlatform.android:
      return AndroidHealthChannel(
        binding: binding,
        minorBindingAllowed: minorBindingAllowed,
      );
    case TargetPlatform.fuchsia ||
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows:
      return const UnsupportedHealthPlatform();
  }
}
