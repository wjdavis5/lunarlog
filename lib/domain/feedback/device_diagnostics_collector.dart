/// Contract for collecting the allowlisted device/app diagnostics payload
/// attached to an in-app feedback ticket (Issue #6, U4; R4, R7, R9).
///
/// `lib/ui` reads a `DeviceDiagnostics` from this seam but must not depend on
/// the plugin-backed collector in `lib/data/diagnostics/` (which touches
/// `device_info_plus`/`package_info_plus`); the contract speaks only in the
/// domain [DeviceDiagnostics] model.
library;

import 'feedback_service.dart';

abstract interface class DeviceDiagnosticsCollector {
  /// Collects the current diagnostics payload. Implementations must never
  /// throw: a plugin failure degrades to an all-unknown payload rather than
  /// failing the caller's submission.
  Future<DeviceDiagnostics> collect();
}
