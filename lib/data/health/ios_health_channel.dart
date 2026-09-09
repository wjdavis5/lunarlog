/// The iOS pin of the `lunarlog/health` channel (Issue #173): the same
/// [MethodChannelHealthPlatform] engine, documented against and pinned to
/// its Swift counterpart — the `HKHealthStore` handler registered on
/// `lunarlog/health` in `ios/Runner/AppDelegate.swift`.
///
/// Nothing iOS-specific lives in Dart: both platforms speak the exact
/// wire protocol defined in `health_channel_codec.dart`, so the per-
/// platform Dart files exist as the named homes for each platform's
/// half — this one is where #193's pure `FlowLevel` →
/// `HKCategoryValueVaginalBleeding` mapping function (with the
/// spotting-in/outside-episode branch) will live, keeping platform
/// vocabulary next to its platform pin rather than in the shared engine.
///
/// Coverage-excluded (`tool/quality/exclusions.dart`): the constructor
/// is the entire executable surface here — the real behavior it binds to
/// is Swift and can never run under `flutter test`, same treatment as
/// `google_sign_in_client.dart`. Every piece of shared logic (guard
/// ordering, codec, error mapping) deliberately lives in
/// `health_channel.dart`/`health_channel_codec.dart`, which are NOT
/// excluded and are directly tested.
library;

import 'package:flutter/services.dart' show MethodChannel;

import 'health_channel.dart';

/// The HealthKit adapter: [HealthPlatformStore] over the
/// `lunarlog/health` channel as answered by the Swift `HKHealthStore`
/// handler in `ios/Runner/AppDelegate.swift`.
///
/// See `health_channel.dart`'s library doc for the guard-ordering
/// contract; `health_platform.dart`'s for the (a)-vs-(b) first-party
/// channel decision this file is half of.
class IOSHealthChannel extends MethodChannelHealthPlatform {
  IOSHealthChannel({
    required super.binding,
    required super.minorBindingAllowed,
  }) : super(channel: const MethodChannel(kHealthChannelName));
}
