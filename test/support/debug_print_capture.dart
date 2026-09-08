/// Test helper for asserting what `debugPrint` produced (#97 U2): the
/// type-only log discipline is a property of printed output, so the
/// assertion has to capture it.
///
/// `debugPrint` is a reassignable global in `flutter/foundation`; this
/// swaps it for a collector and restores the original afterwards. Lines
/// are captured verbatim, before any wrapping/throttling the default
/// implementation would apply.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class DebugPrintCapture {
  DebugPrintCapture._(this._original) {
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
  }

  final DebugPrintCallback _original;

  /// Every `debugPrint` call's message while the capture is installed.
  final List<String> lines = [];

  /// Puts the original `debugPrint` back. Must be called before the test
  /// body ends: the framework's foundation-variable invariant check runs
  /// at the end of the body, *before* `addTearDown` callbacks, and fails
  /// the test if a foundation global is still swapped out. (A tearDown
  /// backstop is still registered, so a test that fails mid-body does not
  /// leak the swap into other tests.)
  void restore() {
    debugPrint = _original;
  }
}

DebugPrintCapture captureDebugPrint() {
  final capture = DebugPrintCapture._(debugPrint);
  addTearDown(capture.restore);
  return capture;
}
