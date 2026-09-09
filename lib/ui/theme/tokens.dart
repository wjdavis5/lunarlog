/// Design tokens (issue #176; B-1, B-3, B-4, B-34): the single source of
/// spacing, radius, elevation, type-ramp, and motion-duration constants
/// consumed by `app_theme.dart`. New/changed screens should reach for these
/// tokens instead of a literal `SizedBox`/`EdgeInsets`/`TextStyle` value —
/// existing literals are migrated incrementally by the issues that touch
/// each screen, not in one sweep here.
library;

import 'package:flutter/widgets.dart';

/// Spacing scale (dp) — the de-facto values already used across `lib/ui/**`,
/// named so they read as intent rather than magic numbers.
abstract final class LLSpace {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;
}

/// Corner radii (dp). [rFull] is large enough to render as a full pill or
/// circle regardless of the shape's extent (the usual `BorderRadius.circular`
/// idiom for "fully rounded").
abstract final class LLRadius {
  static const double rSm = 4;
  static const double rMd = 8;
  static const double rLg = 12;
  static const double rXl = 16;
  static const double rFull = 999;
}

/// Elevation steps (Material dp shadow keys). Everything not listed here
/// stays flat ([e0]).
abstract final class LLElevation {
  /// Flat — the default for everything else (app bars, list tiles, sheets'
  /// own background before they scroll under content).
  static const double e0 = 0;

  /// Cards.
  static const double e1 = 1;

  /// Sheets (e.g. the day-entry bottom sheet).
  static const double e2 = 3;
}

/// Motion durations. Callers should collapse to [Duration.zero] when the
/// platform/user has requested reduced motion — see [LLMotion.resolve].
abstract final class LLMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// Returns [duration] unless `MediaQuery.disableAnimationsOf(context)` is
  /// true, in which case it collapses to [Duration.zero] so no animation
  /// plays for a user/platform that has asked to reduce motion.
  static Duration resolve(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}

/// One slot in the type ramp: an explicit size/line-height/weight so the
/// ramp is auditable against issue #176's table, independent of whatever
/// Flutter's default M3 [Typography] happens to ship.
@immutable
class LLTypeSlot {
  const LLTypeSlot({
    required this.fontSize,
    required this.lineHeight,
    this.fontWeight,
  });

  /// Font size in logical pixels.
  final double fontSize;

  /// Line height in logical pixels (not the [TextStyle.height] multiplier —
  /// [toTextStyle] does that division).
  final double lineHeight;

  final FontWeight? fontWeight;

  TextStyle toTextStyle() => TextStyle(
        fontSize: fontSize,
        height: lineHeight / fontSize,
        fontWeight: fontWeight,
      );
}

/// The type ramp (B-4): explicit M3 slot sizes/weights, auditable against
/// issue #176's table. `display*` and the unused `headlineLarge` slot are
/// deliberately absent — `app_theme.dart` leaves them at Flutter's default.
abstract final class LLType {
  static const headlineMedium = LLTypeSlot(fontSize: 28, lineHeight: 36);
  static const headlineSmall = LLTypeSlot(fontSize: 24, lineHeight: 32);
  static const titleLarge = LLTypeSlot(
    fontSize: 22,
    lineHeight: 28,
    fontWeight: FontWeight.w500,
  );
  static const titleMedium = LLTypeSlot(
    fontSize: 16,
    lineHeight: 24,
    fontWeight: FontWeight.w500,
  );
  static const titleSmall = LLTypeSlot(
    fontSize: 14,
    lineHeight: 20,
    fontWeight: FontWeight.w500,
  );
  static const bodyLarge = LLTypeSlot(fontSize: 16, lineHeight: 24);
  static const bodyMedium = LLTypeSlot(fontSize: 14, lineHeight: 20);
  static const bodySmall = LLTypeSlot(fontSize: 12, lineHeight: 16);
  static const labelLarge = LLTypeSlot(
    fontSize: 14,
    lineHeight: 20,
    fontWeight: FontWeight.w500,
  );
  static const labelMedium = LLTypeSlot(
    fontSize: 12,
    lineHeight: 16,
    fontWeight: FontWeight.w500,
  );
  static const labelSmall = LLTypeSlot(
    fontSize: 11,
    lineHeight: 16,
    fontWeight: FontWeight.w500,
  );
}
