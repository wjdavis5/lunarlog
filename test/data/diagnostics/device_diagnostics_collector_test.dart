// Issue #6, U4: diagnostics collection over injectable plugin seams.

import 'dart:ui' show Locale;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/diagnostics/device_diagnostics_collector.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/scrub.dart';
import 'package:package_info_plus/package_info_plus.dart';

AndroidDeviceInfo _fakeAndroidDeviceInfo({String model = 'Pixel 9', String release = '15'}) {
  return AndroidDeviceInfo.setMockInitialValues(
    version: AndroidBuildVersion.setMockInitialValues(
      codename: 'REL',
      incremental: '1',
      previewSdkInt: 0,
      release: release,
      sdkInt: 35,
    ),
    board: 'board',
    bootloader: 'bootloader',
    brand: 'google',
    device: 'device',
    display: 'display',
    fingerprint: 'fingerprint',
    hardware: 'hardware',
    host: 'host',
    id: 'id',
    manufacturer: 'Google',
    model: model,
    product: 'product',
    name: 'name',
    supported32BitAbis: const [],
    supported64BitAbis: const [],
    supportedAbis: const [],
    tags: 'tags',
    type: 'user',
    isPhysicalDevice: true,
    freeDiskSize: 1,
    totalDiskSize: 1,
    systemFeatures: const [],
    isLowRamDevice: false,
    physicalRamSize: 1,
    availableRamSize: 1,
  );
}

IosDeviceInfo _fakeIosDeviceInfo({String machine = 'iPhone15,2', String systemVersion = '18.0'}) {
  return IosDeviceInfo.setMockInitialValues(
    name: 'name',
    systemName: 'iOS',
    systemVersion: systemVersion,
    model: 'iPhone',
    modelName: 'iPhone',
    localizedModel: 'iPhone',
    freeDiskSize: 1,
    totalDiskSize: 1,
    isPhysicalDevice: true,
    isiOSAppOnMac: false,
    isiOSAppOnVision: false,
    physicalRamSize: 1,
    availableRamSize: 1,
    utsname: IosUtsname.setMockInitialValues(
      sysname: 'Darwin',
      nodename: 'iPhone',
      release: '23.0.0',
      version: 'Darwin Kernel',
      machine: machine,
    ),
  );
}

void main() {
  group('osNameFor', () {
    test('maps every TargetPlatform to a human-readable name', () {
      expect(osNameFor(TargetPlatform.iOS), 'iOS');
      expect(osNameFor(TargetPlatform.android), 'Android');
      expect(osNameFor(TargetPlatform.macOS), 'macOS');
      expect(osNameFor(TargetPlatform.windows), 'Windows');
      expect(osNameFor(TargetPlatform.linux), 'Linux');
      expect(osNameFor(TargetPlatform.fuchsia), 'Fuchsia');
    });
  });

  group('deviceModelFrom / osVersionFrom', () {
    test('reads model and OS version from AndroidDeviceInfo', () {
      final info = _fakeAndroidDeviceInfo();
      expect(deviceModelFrom(info), 'Pixel 9');
      expect(osVersionFrom(info), '15');
    });

    test('reads model and OS version from IosDeviceInfo', () {
      final info = _fakeIosDeviceInfo();
      expect(deviceModelFrom(info), 'iPhone15,2');
      expect(osVersionFrom(info), '18.0');
    });
  });

  group('DeviceDiagnosticsCollector', () {
    test('happy path: toJson keys equal the allowlist exactly', () async {
      final log = BreadcrumbLog()..record('nav', 'overview');
      final collector = DeviceDiagnosticsCollector(
        packageInfoReader: () async => PackageInfo(
          appName: 'lunarlog',
          packageName: 'com.wjdavis5.lunarlog',
          version: '1.0.0',
          buildNumber: '42',
        ),
        deviceInfoReader: () async => _fakeIosDeviceInfo(),
        localeSupplier: () => const Locale('en', 'US'),
        platform: TargetPlatform.iOS,
        breadcrumbLog: log,
      );

      final result = await collector.collect();
      final json = result.toJson();

      expect(
        json.keys.toSet(),
        {'os', 'os_version', 'model', 'app_version', 'build_number', 'locale', 'breadcrumbs'},
      );
      expect(result.os, 'iOS');
      expect(result.osVersion, '18.0');
      expect(result.model, 'iPhone15,2');
      expect(result.appVersion, '1.0.0');
      expect(result.buildNumber, '42');
      expect(result.locale, 'en_US');
      expect(result.breadcrumbs, ['nav: overview']);
    });

    test('error path: a plugin seam throws, yielding an all-unknown payload with no escaped exception', () async {
      final collector = DeviceDiagnosticsCollector(
        packageInfoReader: () async => throw StateError('plugin unavailable'),
        deviceInfoReader: () async => _fakeAndroidDeviceInfo(),
        localeSupplier: () => const Locale('en', 'US'),
        platform: TargetPlatform.android,
        breadcrumbLog: BreadcrumbLog(),
      );

      final result = await collector.collect();

      expect(result.os, 'Android', reason: 'OS name never comes from a plugin, so it is still known');
      expect(result.osVersion, kUnknownDiagnosticValue);
      expect(result.model, kUnknownDiagnosticValue);
      expect(result.appVersion, kUnknownDiagnosticValue);
      expect(result.buildNumber, kUnknownDiagnosticValue);
    });

    test('edge case: an empty breadcrumb log yields an empty breadcrumbs array', () async {
      final collector = DeviceDiagnosticsCollector(
        packageInfoReader: () async => PackageInfo(
          appName: 'lunarlog',
          packageName: 'com.wjdavis5.lunarlog',
          version: '1.0.0',
          buildNumber: '1',
        ),
        deviceInfoReader: () async => _fakeAndroidDeviceInfo(),
        localeSupplier: () => const Locale('en', 'US'),
        platform: TargetPlatform.android,
        breadcrumbLog: BreadcrumbLog(),
      );

      final result = await collector.collect();
      expect(result.breadcrumbs, isEmpty);
      expect(result.toJson()['breadcrumbs'], isEmpty);
    });

    test('a realistic payload never contains a deny-listed key', () async {
      final log = BreadcrumbLog()
        ..record('nav', 'overview')
        ..record('http', 'GET /rest/v1/feedback_tickets');
      final collector = DeviceDiagnosticsCollector(
        packageInfoReader: () async => PackageInfo(
          appName: 'lunarlog',
          packageName: 'com.wjdavis5.lunarlog',
          version: '1.2.3',
          buildNumber: '99',
        ),
        deviceInfoReader: () async => _fakeIosDeviceInfo(),
        localeSupplier: () => const Locale('en', 'US'),
        platform: TargetPlatform.iOS,
        breadcrumbLog: log,
      );

      final result = await collector.collect();
      expect(containsDenyListedKey(result.toJson()), isFalse);
    });
  });
}
