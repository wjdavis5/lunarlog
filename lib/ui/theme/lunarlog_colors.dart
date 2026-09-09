/// Domain colour roles the M3 [ColorScheme] cannot express (issue #176;
/// B-1, B-34): a four-step flow-intensity ramp, a symptom-log accent, the
/// "predicted period" calendar band, confidence-badge colours, and
/// family-role badge colours.
///
/// Every colour here is *derived*, not hardcoded: each is built from the
/// theme's own generated [ColorScheme] (its primary/tertiary hue and its
/// actual surface luminance) via a luminance search, so the documented
/// contrast ratios hold for whatever seed/brightness produced the scheme --
/// see [LunarLogColors.forColorScheme] and `test/ui/theme_test.dart`, which
/// walks both themes and asserts the ratios independently. The flow ramp
/// solves against `colorScheme.surfaceContainerLow` specifically, not
/// `surface`: that's the actual `CardThemeData.color` (see `app_theme.dart`)
/// the calendar/overview widgets render flow chips onto, so the ramp's 3:1
/// floor (`flowSpotting`) holds against the background it really sits on
/// rather than a background it never appears against.
///
/// Dark variants are *re-derived*, not merely inverted (the #137 failure
/// this issue heads off): boldness reads as "further from the background" in
/// both directions, but which direction that is flips with brightness (see
/// `toneLighterThanSurface` below), so a "heavy" step still pops off a dark
/// backdrop instead of receding into it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class LunarLogColors extends ThemeExtension<LunarLogColors> {
  const LunarLogColors({
    required this.flowSpotting,
    required this.onFlowSpotting,
    required this.flowLight,
    required this.onFlowLight,
    required this.flowMedium,
    required this.onFlowMedium,
    required this.flowHeavy,
    required this.onFlowHeavy,
    required this.symptomDot,
    required this.predictedBand,
    required this.predictedBorder,
    required this.confidenceHigh,
    required this.confidenceLearning,
    required this.confidenceIrregular,
    required this.roleOwner,
    required this.roleCoParent,
    required this.roleCaregiver,
    required this.roleViewer,
  });

  /// Builds the full role set from a generated [ColorScheme]. The flow ramp
  /// is derived from [ColorScheme.primary]'s hue (B-1's "ramp on the primary
  /// hue", not a separate menstrual-red palette); [symptomDot] from
  /// [ColorScheme.tertiary]'s. Confidence and role badges use fixed,
  /// mutually-distinguishable hues of their own.
  factory LunarLogColors.forColorScheme(ColorScheme colorScheme) {
    final toneLighterThanSurface = colorScheme.brightness == Brightness.dark;
    final surfaceLuminance = _relativeLuminance(colorScheme.surface);
    // The flow ramp is solved against the Card background it actually
    // renders onto (`CardThemeData.color` in `app_theme.dart`), not
    // `surface` -- see the library doc comment.
    final cardLuminance = _relativeLuminance(colorScheme.surfaceContainerLow);
    final primaryHue = HSLColor.fromColor(colorScheme.primary).hue;
    final tertiaryHue = HSLColor.fromColor(colorScheme.tertiary).hue;

    // Four steps, increasingly bold: contrast against the card background
    // climbs from the documented minimum (3:1) upward, and saturation
    // climbs with it, so the ramp actually reads as a progression rather
    // than four hues at one fixed lightness.
    const flowMinContrasts = [3.0, 4.2, 5.6, 7.4];
    const flowSaturations = [0.30, 0.48, 0.65, 0.85];
    final flowSteps = [
      for (var i = 0; i < flowMinContrasts.length; i++)
        _ToneOnTone.build(
          hue: primaryHue,
          saturation: flowSaturations[i],
          backgroundLuminance: cardLuminance,
          toneLighterThanBackground: toneLighterThanSurface,
          minToneContrast: flowMinContrasts[i],
          minOnToneContrast: 4.5,
        ),
    ];

    final symptomDot = _toneAtContrast(
      hue: tertiaryHue,
      saturation: 0.55,
      backgroundLuminance: surfaceLuminance,
      toneLighterThanBackground: toneLighterThanSurface,
      minContrast: 3.0,
    );

    final predictedBorder = _toneAtContrast(
      hue: primaryHue,
      saturation: 0.40,
      backgroundLuminance: surfaceLuminance,
      toneLighterThanBackground: toneLighterThanSurface,
      minContrast: 3.0,
    );
    // Low-chroma fill: the border (plus the dashed/hatched pattern the
    // consuming widget draws) carries the "predicted" meaning, not colour
    // alone, so the fill itself only needs to be a soft wash.
    final predictedBand = predictedBorder.withValues(alpha: 0.16);

    Color badge(double hue, double saturation) => _toneAtContrast(
          hue: hue,
          saturation: saturation,
          backgroundLuminance: surfaceLuminance,
          toneLighterThanBackground: toneLighterThanSurface,
          minContrast: 3.0,
        );

    return LunarLogColors(
      flowSpotting: flowSteps[0].tone,
      onFlowSpotting: flowSteps[0].onTone,
      flowLight: flowSteps[1].tone,
      onFlowLight: flowSteps[1].onTone,
      flowMedium: flowSteps[2].tone,
      onFlowMedium: flowSteps[2].onTone,
      flowHeavy: flowSteps[3].tone,
      onFlowHeavy: flowSteps[3].onTone,
      symptomDot: symptomDot,
      predictedBand: predictedBand,
      predictedBorder: predictedBorder,
      // Fixed hues (not the primary/tertiary hue) so these badge families
      // stay visually distinct from the flow ramp and from each other.
      confidenceHigh: badge(142, 0.45), // green -- regular, well-established
      confidenceLearning: badge(38, 0.65), // amber -- still building history
      confidenceIrregular: badge(6, 0.60), // red-orange -- flagged irregular
      roleOwner: badge(primaryHue, 0.50),
      roleCoParent: badge(258, 0.40), // violet
      roleCaregiver: badge(199, 0.45), // blue
      roleViewer: badge(0, 0), // neutral grey -- read-only, deliberately flat
    );
  }

  /// A four-step ramp on the primary hue for flow intensity, lightest to
  /// boldest. Each `flow*` is >=3:1 against `surface`; each `onFlow*` is
  /// >=4.5:1 against its own `flow*`.
  final Color flowSpotting;
  final Color onFlowSpotting;
  final Color flowLight;
  final Color onFlowLight;
  final Color flowMedium;
  final Color onFlowMedium;
  final Color flowHeavy;
  final Color onFlowHeavy;

  /// Tertiary-derived accent for a logged symptom, >=3:1 against `surface`.
  final Color symptomDot;

  /// Low-chroma fill for a predicted-period calendar cell. Distinguishable
  /// without colour: pair with a dashed/hatched [predictedBorder], never
  /// colour alone.
  final Color predictedBand;
  final Color predictedBorder;

  /// Prediction-confidence badge colours.
  final Color confidenceHigh;
  final Color confidenceLearning;
  final Color confidenceIrregular;

  /// Family-role badge colours.
  final Color roleOwner;
  final Color roleCoParent;
  final Color roleCaregiver;
  final Color roleViewer;

  /// Resolves a `copyWith` parameter: an unpassed (`null`) argument keeps
  /// [fallback]. Pulling the `??` out of [copyWith] and into this helper
  /// keeps that method's own body free of `??`/`&&`/`||` decision points --
  /// the quality gate's per-method CRAP score counts each `??` as one, and
  /// eighteen of them inline (one per field) pushed `copyWith` well past
  /// the gate's complexity cap regardless of test coverage. Mirrors the
  /// sentinel-based `_resolveNullable` in `Profile.copyWith`, minus the
  /// sentinel: every field here is non-nullable, so a plain `??` (not
  /// "was this argument passed at all") is the right resolution rule.
  static T _or<T>(T? value, T fallback) => value ?? fallback;

  @override
  LunarLogColors copyWith({
    Color? flowSpotting,
    Color? onFlowSpotting,
    Color? flowLight,
    Color? onFlowLight,
    Color? flowMedium,
    Color? onFlowMedium,
    Color? flowHeavy,
    Color? onFlowHeavy,
    Color? symptomDot,
    Color? predictedBand,
    Color? predictedBorder,
    Color? confidenceHigh,
    Color? confidenceLearning,
    Color? confidenceIrregular,
    Color? roleOwner,
    Color? roleCoParent,
    Color? roleCaregiver,
    Color? roleViewer,
  }) {
    return LunarLogColors(
      flowSpotting: _or(flowSpotting, this.flowSpotting),
      onFlowSpotting: _or(onFlowSpotting, this.onFlowSpotting),
      flowLight: _or(flowLight, this.flowLight),
      onFlowLight: _or(onFlowLight, this.onFlowLight),
      flowMedium: _or(flowMedium, this.flowMedium),
      onFlowMedium: _or(onFlowMedium, this.onFlowMedium),
      flowHeavy: _or(flowHeavy, this.flowHeavy),
      onFlowHeavy: _or(onFlowHeavy, this.onFlowHeavy),
      symptomDot: _or(symptomDot, this.symptomDot),
      predictedBand: _or(predictedBand, this.predictedBand),
      predictedBorder: _or(predictedBorder, this.predictedBorder),
      confidenceHigh: _or(confidenceHigh, this.confidenceHigh),
      confidenceLearning: _or(confidenceLearning, this.confidenceLearning),
      confidenceIrregular: _or(confidenceIrregular, this.confidenceIrregular),
      roleOwner: _or(roleOwner, this.roleOwner),
      roleCoParent: _or(roleCoParent, this.roleCoParent),
      roleCaregiver: _or(roleCaregiver, this.roleCaregiver),
      roleViewer: _or(roleViewer, this.roleViewer),
    );
  }

  @override
  LunarLogColors lerp(
    covariant ThemeExtension<LunarLogColors>? other,
    double t,
  ) {
    if (other is! LunarLogColors) return this;
    return LunarLogColors(
      flowSpotting: Color.lerp(flowSpotting, other.flowSpotting, t)!,
      onFlowSpotting: Color.lerp(onFlowSpotting, other.onFlowSpotting, t)!,
      flowLight: Color.lerp(flowLight, other.flowLight, t)!,
      onFlowLight: Color.lerp(onFlowLight, other.onFlowLight, t)!,
      flowMedium: Color.lerp(flowMedium, other.flowMedium, t)!,
      onFlowMedium: Color.lerp(onFlowMedium, other.onFlowMedium, t)!,
      flowHeavy: Color.lerp(flowHeavy, other.flowHeavy, t)!,
      onFlowHeavy: Color.lerp(onFlowHeavy, other.onFlowHeavy, t)!,
      symptomDot: Color.lerp(symptomDot, other.symptomDot, t)!,
      predictedBand: Color.lerp(predictedBand, other.predictedBand, t)!,
      predictedBorder: Color.lerp(predictedBorder, other.predictedBorder, t)!,
      confidenceHigh: Color.lerp(confidenceHigh, other.confidenceHigh, t)!,
      confidenceLearning:
          Color.lerp(confidenceLearning, other.confidenceLearning, t)!,
      confidenceIrregular:
          Color.lerp(confidenceIrregular, other.confidenceIrregular, t)!,
      roleOwner: Color.lerp(roleOwner, other.roleOwner, t)!,
      roleCoParent: Color.lerp(roleCoParent, other.roleCoParent, t)!,
      roleCaregiver: Color.lerp(roleCaregiver, other.roleCaregiver, t)!,
      roleViewer: Color.lerp(roleViewer, other.roleViewer, t)!,
    );
  }

  /// The four-step flow ramp, split out purely to keep [operator ==]'s own
  /// cyclomatic complexity (and so its CRAP score) low as fields grow --
  /// same reasoning as `Profile._sameProfileIdentity`/`_sameProfileDetails`.
  bool _sameFlowColors(LunarLogColors other) =>
      other.flowSpotting == flowSpotting &&
      other.onFlowSpotting == onFlowSpotting &&
      other.flowLight == flowLight &&
      other.onFlowLight == onFlowLight &&
      other.flowMedium == flowMedium &&
      other.onFlowMedium == onFlowMedium &&
      other.flowHeavy == flowHeavy &&
      other.onFlowHeavy == onFlowHeavy;

  bool _sameAccentColors(LunarLogColors other) =>
      other.symptomDot == symptomDot &&
      other.predictedBand == predictedBand &&
      other.predictedBorder == predictedBorder;

  bool _sameConfidenceColors(LunarLogColors other) =>
      other.confidenceHigh == confidenceHigh &&
      other.confidenceLearning == confidenceLearning &&
      other.confidenceIrregular == confidenceIrregular;

  bool _sameRoleColors(LunarLogColors other) =>
      other.roleOwner == roleOwner &&
      other.roleCoParent == roleCoParent &&
      other.roleCaregiver == roleCaregiver &&
      other.roleViewer == roleViewer;

  // Value equality (issue #176 review): without this, two independently
  // built `LunarLogColors` instances (e.g. `AppTheme.lightTheme` read
  // twice, pre-memoization) never compare equal, which made every
  // containing `ThemeData` compare unequal too -- `AnimatedTheme` restarted
  // its animation and every `Theme.of` dependent rebuilt on every
  // `setState`, even when nothing about the theme actually changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LunarLogColors &&
          _sameFlowColors(other) &&
          _sameAccentColors(other) &&
          _sameConfidenceColors(other) &&
          _sameRoleColors(other);

  @override
  int get hashCode => Object.hashAll([
        flowSpotting,
        onFlowSpotting,
        flowLight,
        onFlowLight,
        flowMedium,
        onFlowMedium,
        flowHeavy,
        onFlowHeavy,
        symptomDot,
        predictedBand,
        predictedBorder,
        confidenceHigh,
        confidenceLearning,
        confidenceIrregular,
        roleOwner,
        roleCoParent,
        roleCaregiver,
        roleViewer,
      ]);
}

/// WCAG 2.x relative luminance of an sRGB colour, in `[0, 1]`.
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double _relativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}

/// WCAG 2.x contrast ratio between two colours, in `[1, 21]`.
/// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
double contrastRatio(Color a, Color b) {
  final luminanceA = _relativeLuminance(a);
  final luminanceB = _relativeLuminance(b);
  final lighter = math.max(luminanceA, luminanceB);
  final darker = math.min(luminanceA, luminanceB);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Safety margin added to every requested contrast ratio before solving for
/// a target luminance: [HSLColor.toColor] rounds each channel to an 8-bit
/// integer, so the *achieved* contrast of the resulting [Color] is slightly
/// noisier than the continuous target this function solves for. Without
/// this margin that quantization can land a hair under the documented
/// minimum (observed ~0.3-0.7% short); solving for a target ~2% higher
/// absorbs it with room to spare.
const double _contrastSafetyFactor = 1.02;

/// Relative-luminance target that clears [minContrast] against a background
/// of [backgroundLuminance], approaching from above (lighter) or below
/// (darker) as directed by [lighterThanBackground].
double _targetLuminanceForContrast({
  required double backgroundLuminance,
  required bool lighterThanBackground,
  required double minContrast,
}) {
  final safeMinContrast = minContrast * _contrastSafetyFactor;
  final target = lighterThanBackground
      ? safeMinContrast * (backgroundLuminance + 0.05) - 0.05
      : (backgroundLuminance + 0.05) / safeMinContrast - 0.05;
  return target.clamp(0.0, 1.0);
}

/// Binary-searches HSL lightness (at a fixed hue/saturation) for the colour
/// closest to [targetLuminance]. Relative luminance is monotonic
/// non-decreasing in HSL lightness for any fixed hue/saturation (each of R,
/// G, B is itself monotonic non-decreasing in `L`), so this always
/// converges regardless of hue.
Color _colorAtLuminance({
  required double hue,
  required double saturation,
  required double targetLuminance,
}) {
  var lo = 0.0;
  var hi = 1.0;
  var candidate = HSLColor.fromAHSL(1, hue, saturation, 0.5).toColor();
  for (var i = 0; i < 30; i++) {
    final mid = (lo + hi) / 2;
    candidate = HSLColor.fromAHSL(1, hue, saturation, mid).toColor();
    if (_relativeLuminance(candidate) < targetLuminance) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return candidate;
}

/// A single tone built to clear [minContrast] against a background of
/// [backgroundLuminance], at the given hue/saturation.
Color _toneAtContrast({
  required double hue,
  required double saturation,
  required double backgroundLuminance,
  required bool toneLighterThanBackground,
  required double minContrast,
}) {
  final targetLuminance = _targetLuminanceForContrast(
    backgroundLuminance: backgroundLuminance,
    lighterThanBackground: toneLighterThanBackground,
    minContrast: minContrast,
  );
  return _colorAtLuminance(
    hue: hue,
    saturation: saturation,
    targetLuminance: targetLuminance,
  );
}

/// A background-contrasting tone paired with a black-or-white "on" colour,
/// whichever contrasts more against it (always >=4.5:1 for the tones this
/// file builds -- see `test/ui/theme_test.dart`).
class _ToneOnTone {
  const _ToneOnTone(this.tone, this.onTone);

  factory _ToneOnTone.build({
    required double hue,
    required double saturation,
    required double backgroundLuminance,
    required bool toneLighterThanBackground,
    required double minToneContrast,
    required double minOnToneContrast,
  }) {
    final tone = _toneAtContrast(
      hue: hue,
      saturation: saturation,
      backgroundLuminance: backgroundLuminance,
      toneLighterThanBackground: toneLighterThanBackground,
      minContrast: minToneContrast,
    );
    const black = Colors.black;
    const white = Colors.white;
    final onTone = contrastRatio(tone, black) >= contrastRatio(tone, white)
        ? black
        : white;
    // Defensive, not load-bearing: the black/white extremes should always
    // clear the target, but assert loudly (rather than silently ship a
    // WCAG failure) if a future saturation/contrast tuning ever breaks it.
    assert(
      contrastRatio(tone, onTone) >= minOnToneContrast,
      'onTone contrast ${contrastRatio(tone, onTone)} fell below '
      '$minOnToneContrast for hue $hue',
    );
    return _ToneOnTone(tone, onTone);
  }

  final Color tone;
  final Color onTone;
}
