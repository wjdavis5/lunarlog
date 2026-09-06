/// Diagnostics collection for in-app feedback (Issue #6, U4; R7, R8, R9,
/// R10). Every value maps onto the KTD3 allowlist and nothing else; an
/// unavailable value becomes `'unknown'` rather than failing submission.
///
/// [package_info_plus] and [device_info_plus] reads are typedef seams
/// defaulting to the real plugin call (mirroring the `SentryInit` seam in
/// `lib/observability/sentry_bootstrap.dart`), so this collector is
/// unit-testable with fakes instead of the real plugins.
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/scrub.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String kUnknownDiagnosticValue = 'unknown';

typedef PackageInfoReader = Future<PackageInfo> Function();
typedef DeviceInfoReader = Future<BaseDeviceInfo> Function();
typedef LocaleSupplier = Locale Function();

Future<PackageInfo> _defaultPackageInfoReader() => PackageInfo.fromPlatform();

Future<BaseDeviceInfo> _defaultDeviceInfoReader() =>
    DeviceInfoPlugin().deviceInfo;

Locale _defaultLocaleSupplier() => PlatformDispatcher.instance.locale;

/// Human-readable OS name for [platform]; never touches a plugin.
String osNameFor(TargetPlatform platform) => switch (platform) {
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };

/// The device model from a [BaseDeviceInfo] reading, for the two shipping
/// mobile platforms; anything else (web, desktop) is unknown.
String deviceModelFrom(BaseDeviceInfo info) {
  if (info is AndroidDeviceInfo) return info.model;
  if (info is IosDeviceInfo) return info.utsname.machine;
  return kUnknownDiagnosticValue;
}

/// The OS version string from a [BaseDeviceInfo] reading.
String osVersionFrom(BaseDeviceInfo info) {
  if (info is AndroidDeviceInfo) return info.version.release;
  if (info is IosDeviceInfo) return info.systemVersion;
  return kUnknownDiagnosticValue;
}

class DeviceDiagnosticsCollector {
  DeviceDiagnosticsCollector({
    this.packageInfoReader = _defaultPackageInfoReader,
    this.deviceInfoReader = _defaultDeviceInfoReader,
    this.localeSupplier = _defaultLocaleSupplier,
    TargetPlatform? platform,
    BreadcrumbLog? breadcrumbLog,
  })  : platform = platform ?? defaultTargetPlatform,
        _breadcrumbLog = breadcrumbLog ?? defaultBreadcrumbLog;

  final PackageInfoReader packageInfoReader;
  final DeviceInfoReader deviceInfoReader;
  final LocaleSupplier localeSupplier;
  final TargetPlatform platform;
  final BreadcrumbLog _breadcrumbLog;

  /// Collects the current diagnostics payload. Never throws: a plugin
  /// failure is caught, logged as its type only, and yields an all-unknown
  /// device/app payload rather than failing the caller's submission.
  Future<DeviceDiagnostics> collect() async {
    var osVersion = kUnknownDiagnosticValue;
    var model = kUnknownDiagnosticValue;
    var appVersion = kUnknownDiagnosticValue;
    var buildNumber = kUnknownDiagnosticValue;

    try {
      final packageInfo = await packageInfoReader();
      final deviceInfo = await deviceInfoReader();
      osVersion = osVersionFrom(deviceInfo);
      model = deviceModelFrom(deviceInfo);
      appVersion =
          packageInfo.version.isEmpty ? kUnknownDiagnosticValue : packageInfo.version;
      buildNumber = packageInfo.buildNumber.isEmpty
          ? kUnknownDiagnosticValue
          : packageInfo.buildNumber;
    } catch (error) {
      debugPrint('lunarlog feedback: diagnostics collection failed (${error.runtimeType})');
      osVersion = kUnknownDiagnosticValue;
      model = kUnknownDiagnosticValue;
      appVersion = kUnknownDiagnosticValue;
      buildNumber = kUnknownDiagnosticValue;
    }

    final result = DeviceDiagnostics(
      os: osNameFor(platform),
      osVersion: osVersion,
      model: model,
      appVersion: appVersion,
      buildNumber: buildNumber,
      locale: localeSupplier().toString(),
      breadcrumbs: _breadcrumbLog.snapshot(),
    );
    assert(!containsDenyListedKey(result.toJson()));
    return result;
  }
}
