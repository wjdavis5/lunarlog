/// The Android pin of the `lunarlog/health` channel (Issue #173): the
/// same [MethodChannelHealthPlatform] engine, documented against and
/// pinned to its Kotlin counterpart — the `HealthConnectClient` handler
/// in `android/app/src/main/kotlin/com/wjdavis5/lunarlog/
/// HealthConnectAdapter.kt`, registered from `MainActivity`.
///
/// Nothing Android-specific lives in Dart: both platforms speak the
/// exact wire protocol defined in `health_channel_codec.dart`, so the
/// per-platform Dart files exist as the named homes for each platform's
/// half — this one is where #202's pure `FlowLevel` → Health Connect
/// flow-constant mapping (reusing #193's spotting rule verbatim) will
/// live, plus the `MenstruationPeriodRecord` episode upsert surface
/// (`clientRecordId`/`clientRecordVersion`, #186).
///
/// Coverage-excluded (`tool/quality/exclusions.dart`): the constructor
/// is the entire executable surface here — the real behavior it binds to
/// is Kotlin and can never run under `flutter test`, same treatment as
/// `google_sign_in_client.dart`. Every piece of shared logic (guard
/// ordering, codec, error mapping) deliberately lives in
/// `health_channel.dart`/`health_channel_codec.dart`, which are NOT
/// excluded and are directly tested.
library;

import 'package:flutter/services.dart' show MethodChannel;

import 'health_channel.dart';

/// The Health Connect adapter: [HealthPlatformStore] over the
/// `lunarlog/health` channel as answered by the Kotlin
/// `HealthConnectAdapter` registered in `MainActivity.configureFlutterEngine`.
///
/// See `health_channel.dart`'s library doc for the guard-ordering
/// contract; `health_platform.dart`'s for the (a)-vs-(b) first-party
/// channel decision this file is half of.
class AndroidHealthChannel extends MethodChannelHealthPlatform {
  AndroidHealthChannel({
    required super.binding,
    required super.minorBindingAllowed,
  }) : super(channel: const MethodChannel(kHealthChannelName));
}
