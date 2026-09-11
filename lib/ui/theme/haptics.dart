/// Centralized semantic haptic feedback helpers (Issue #474).
///
/// Provides tactile confirmation for key logging, selection, and destructive
/// interactions across LunarLog. All calls are fire-and-forget, defensively
/// guarded against platform channel errors, and automatically no-op on platforms
/// without haptic hardware (desktop/web) or in headless unit tests.
library;

import 'package:flutter/services.dart';

abstract final class LLHaptics {
  /// Light sensory tick for chip selection, tab switching, and date navigation.
  static void selection() {
    HapticFeedback.selectionClick().ignore();
  }

  /// Crisp feedback for primary logging actions (e.g. "Period started today",
  /// "Log today" FAB, quick logs).
  static void action() {
    HapticFeedback.mediumImpact().ignore();
  }

  /// Firm feedback for destructive confirmations (e.g. deleting an entry,
  /// archiving/deleting a profile).
  static void destructive() {
    HapticFeedback.heavyImpact().ignore();
  }
}
