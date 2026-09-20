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

/// The two bundled families (issue #808). [text] is Inter, the default for
/// every title/body/label slot; [display] is Fraunces, reserved for the
/// display and headline slots so the hero numbers, month names, and section
/// headings read as a human, editorial face rather than a UI sans at w400.
/// Both ship as static instances under `assets/fonts/` (see `pubspec.yaml`);
/// nothing is fetched at runtime.
abstract final class LLFonts {
  static const String text = 'Inter';
  static const String display = 'Fraunces';
}

/// One slot in the type ramp: an explicit size/line-height/weight/family so
/// the ramp is auditable against issue #176's table and #808, independent of
/// whatever Flutter's default M3 [Typography] happens to ship.
@immutable
class LLTypeSlot {
  const LLTypeSlot({
    required this.fontSize,
    required this.lineHeight,
    this.fontWeight,
    this.fontFamily = LLFonts.text,
    this.letterSpacing,
    this.fontFeatures,
  });

  /// Font size in logical pixels.
  final double fontSize;

  /// Line height in logical pixels (not the [TextStyle.height] multiplier —
  /// [toTextStyle] does that division).
  final double lineHeight;

  final FontWeight? fontWeight;

  /// The bundled family this slot renders in — [LLFonts.text] unless the slot
  /// is part of the display tier ([LLFonts.display]).
  final String fontFamily;

  /// Optional tracking. Labels get positive tracking so 11–12px uppercase-ish
  /// text does not read cramped; the headline tier gets a slight negative
  /// tracking so large display type does not sit loose.
  final double? letterSpacing;

  /// Optional OpenType features — the display slots carry
  /// [FontFeature.tabularFigures] so calendar-grid and hero numerals line up.
  final List<FontFeature>? fontFeatures;

  TextStyle toTextStyle() => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight / fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        fontFeatures: fontFeatures,
      );
}

/// The type ramp (B-4): explicit M3 slot sizes/weights, auditable against
/// issue #176's table, #807, and #808. `displayLarge` and the unused
/// `headlineLarge` slot are unconfigured — `app_theme.dart` leaves them at
/// Flutter's default.
///
/// The display and headline slots use [LLFonts.display] (Fraunces); every
/// title/body/label slot uses [LLFonts.text] (Inter).
abstract final class LLType {
  static const displayMedium = LLTypeSlot(
    fontSize: 45,
    lineHeight: 52,
    fontWeight: FontWeight.w600,
    fontFamily: LLFonts.display,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const displaySmall = LLTypeSlot(
    fontSize: 36,
    lineHeight: 44,
    fontWeight: FontWeight.w600,
    fontFamily: LLFonts.display,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const headlineMedium = LLTypeSlot(
    fontSize: 28,
    lineHeight: 36,
    fontWeight: FontWeight.w600,
    fontFamily: LLFonts.display,
    letterSpacing: -0.2,
  );
  static const headlineSmall = LLTypeSlot(
    fontSize: 24,
    lineHeight: 32,
    fontWeight: FontWeight.w600,
    fontFamily: LLFonts.display,
    letterSpacing: -0.2,
  );
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
    letterSpacing: 0.1,
  );
  static const labelMedium = LLTypeSlot(
    fontSize: 12,
    lineHeight: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
  static const labelSmall = LLTypeSlot(
    fontSize: 11,
    lineHeight: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
}
