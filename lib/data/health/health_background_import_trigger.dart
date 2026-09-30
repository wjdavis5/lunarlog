/// The background-import trigger port (Issue #993) — the narrow seam
/// between the platform halves that *fire* a background import (an
/// `HKObserverQuery` on iOS, the WorkManager job on Android) and the Dart
/// coordinator that runs one (see `health_background_import_service.dart`).
///
/// Both platforms share the `lunarlog/health` channel, so the trigger rides
/// the same wire protocol two methods append to `HealthChannelMethods`:
///
/// * `onBackgroundImportTriggered` (native → Dart): the push. Fired when an
///   observer or worker wants a pass; the Dart side answers immediately
///   (the coordinator runs the pass asynchronously, never inside the
///   reply) so a worker's wait is bounded by an ack, not by a full import.
/// * `consumePendingBackgroundImportTrigger` (Dart → native): the pull.
///   Returns whether a trigger fired while nobody was listening (the
///   startup race: the observer is registered before Dart's handler can
///   be) and clears that latch, so a delivery made before `listen` is not
///   lost — the coordinator pulls once right after registering. Android
///   has no latch (its worker pushes only into a live engine, and a
///   restarted process answers `false`); iOS's observer can fire during
///   engine init, so the latch is what makes that delivery reliable.
///
/// Deliberately not coverage-excluded (unlike the two platform pins): the
/// MethodChannel mechanics here are driven under `flutter test` through
/// `TestDefaultBinaryMessengerBinding`'s mock handler — the same technique
/// `health_channel_test.dart` uses for the platform's own half.
library;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;

import 'health_channel.dart' show kHealthChannelName;
import 'health_channel_codec.dart' show HealthChannelMethods;

/// How the coordinator hears the platform (see the library doc). One
/// implementation; fakes in tests.
abstract interface class HealthBackgroundImportTrigger {
  /// Registers [onTrigger] as the answerer of the native push. One
  /// listener at a time — calling again replaces the previous one; [dispose]
  /// clears it.
  void listen(void Function() onTrigger);

  /// Asks the native side whether a trigger fired before [listen] ran and
  /// clears that latch. False when nothing is pending **or** when the
  /// native half does not answer (an older native side than this Dart
  /// side, or a platform with no health channel at all) — a degraded probe
  /// must never be read as a trigger.
  Future<bool> consumePendingTrigger();

  /// Clears the listener. Safe to call more than once.
  void dispose();
}

/// The production [HealthBackgroundImportTrigger] over the shared
/// `lunarlog/health` channel.
class MethodChannelHealthBackgroundTrigger
    implements HealthBackgroundImportTrigger {
  MethodChannelHealthBackgroundTrigger({
    this.channel = const MethodChannel(kHealthChannelName),
  });

  final MethodChannel channel;

  void Function()? _onTrigger;

  @override
  void listen(void Function() onTrigger) {
    _onTrigger = onTrigger;
    channel.setMethodCallHandler((call) async {
      if (call.method != HealthChannelMethods.onBackgroundImportTriggered) {
        // The one method this listener speaks; anything else keeps the
        // platform's not-implemented contract rather than answering
        // success for a call no one handled.
        throw MissingPluginException(
          '${call.method} is not a background-import trigger method',
        );
      }
      // Ack immediately; the coordinator runs the pass on its own. A reply
      // that waited for the import would hold a worker's bounded wait open
      // for the length of a full pass. The ack is deliberately NON-null:
      // an empty Dart reply is the channel's not-implemented signal (the
      // native caller's `notImplemented`/FlutterMethodNotImplemented), and
      // this method's whole purpose is answering implemented.
      _onTrigger?.call();
      return true;
    });
  }

  @override
  Future<bool> consumePendingTrigger() async {
    try {
      return await channel.invokeMethod<bool>(
            HealthChannelMethods.consumePendingBackgroundImportTrigger,
          ) ??
          false;
    } on MissingPluginException {
      // No native half (unsupported platform, or an unmocked channel in a
      // test): no latch could exist, so nothing is pending.
      return false;
    }
  }

  @override
  void dispose() {
    _onTrigger = null;
    channel.setMethodCallHandler(null);
  }
}
