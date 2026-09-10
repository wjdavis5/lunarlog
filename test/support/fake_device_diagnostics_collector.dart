/// Test double for the `DeviceDiagnosticsCollector` domain contract
/// (Issue #6, U4).
///
/// The real collector (`lib/data/diagnostics/`) touches the
/// `device_info_plus`/`package_info_plus` plugins, which cannot answer under
/// `flutter test`'s default binary messenger; widget tests provide this in
/// the tree so `context.read<DeviceDiagnosticsCollector>()` resolves and
/// `FeedbackController.loadDiagnostics()` settles without a plugin call.
library;

import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

class FakeDeviceDiagnosticsCollector implements DeviceDiagnosticsCollector {
  FakeDeviceDiagnosticsCollector({DeviceDiagnostics? result})
      : result = result ?? _default;

  static const DeviceDiagnostics _default = DeviceDiagnostics(
    os: 'test',
    osVersion: '0',
    model: 'test',
    appVersion: '1.0.0',
    buildNumber: '1',
    locale: 'en_US',
    breadcrumbs: <String>[],
  );

  DeviceDiagnostics result;

  @override
  Future<DeviceDiagnostics> collect() async => result;
}
