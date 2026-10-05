/// Exports the app theme's resolved design tokens to JSON for the React web
/// client in `webapp/` (issue #1249).
///
/// The web client never hand-copies a hex value from the app: this export is
/// its single source for colour, type ramp, and spacing. Both M3 colour
/// schemes are emitted fully resolved from the same [AppTheme] factories the
/// Flutter app renders with, so the two clients cannot drift apart — a theme
/// change that forgets to regenerate the export fails
/// `test/tool/export_webapp_tokens_test.dart` in CI, the same freshness
/// discipline `tool/export_help_cards.dart` applies to the site's help cards
/// and CI applies to `db.g.dart`.
///
/// Regenerate (the theme lives on `package:flutter`, so this runs through
/// `flutter test`, the same way `tool/screenshots/render_screens_test.dart`
/// does — never plain `dart run`):
///
/// ```
/// flutter test tool/export_webapp_tokens_generate_test.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

/// Repository-relative path of the generated export.
const String kWebappTokensExportPath = 'webapp/src/theme/tokens.generated.json';

/// Every [ColorScheme] role the web client consumes today. Enumerated
/// explicitly (not reflectively) so a new Flutter role lands here as a
/// reviewed, diff-visible change.
const List<String> _kColorRoles = <String>[
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'secondary',
  'onSecondary',
  'secondaryContainer',
  'onSecondaryContainer',
  'tertiary',
  'onTertiary',
  'tertiaryContainer',
  'onTertiaryContainer',
  'error',
  'onError',
  'errorContainer',
  'onErrorContainer',
  'surface',
  'onSurface',
  'surfaceContainerLowest',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
  'surfaceContainerHighest',
  'surfaceDim',
  'surfaceBright',
  'surfaceTint',
  'onSurfaceVariant',
  'outline',
  'outlineVariant',
  'inverseSurface',
  'onInverseSurface',
  'inversePrimary',
  'scrim',
  'shadow',
];

/// Every slot of the type ramp (`tokens.dart`'s [LLType]), in that file's
/// own order.
const Map<String, LLTypeSlot> _kTypeSlots = <String, LLTypeSlot>{
  'displayMedium': LLType.displayMedium,
  'displaySmall': LLType.displaySmall,
  'headlineMedium': LLType.headlineMedium,
  'headlineSmall': LLType.headlineSmall,
  'titleLarge': LLType.titleLarge,
  'titleMedium': LLType.titleMedium,
  'titleSmall': LLType.titleSmall,
  'bodyLarge': LLType.bodyLarge,
  'bodyMedium': LLType.bodyMedium,
  'bodySmall': LLType.bodySmall,
  'labelLarge': LLType.labelLarge,
  'labelMedium': LLType.labelMedium,
  'labelSmall': LLType.labelSmall,
};

/// `_hex(c)` — `#RRGGBB`, or `#RRGGBBAA` when the colour is not fully
/// opaque. Built from the component accessors (Color's `value` getter is
/// deprecated on the pinned SDK) so the export compiles clean.
String _hex(Color c) {
  String part(double component) =>
      ((component * 255).round() & 0xff).toRadixString(16).padLeft(2, '0');
  final r = part(c.r);
  final g = part(c.g);
  final b = part(c.b);
  final a = part(c.a);
  return a == 'ff' ? '#$r$g$b' : '#$r$g$b$a';
}

/// `_weightValue(w)` — the numeric weight (CSS `font-weight`). FontWeight's
/// own `value` field is the non-deprecated accessor on the pinned SDK (it is
/// Color's `value` that is deprecated).
int? _weightValue(FontWeight? w) => w?.value;

/// `_num(v)` — integral doubles encode as JSON integers so the committed
/// file stays readable (`16`, not `16.0`).
Object _num(double v) =>
    v == v.truncateToDouble() ? v.toInt() : v;

/// Resolves one role name against a concrete [ColorScheme]. A switch (not a
/// map of getters) so the compiler enforces exhaustiveness against the
/// names in [_kColorRoles] at review time.
Color _role(ColorScheme s, String role) => switch (role) {
        'primary' => s.primary,
        'onPrimary' => s.onPrimary,
        'primaryContainer' => s.primaryContainer,
        'onPrimaryContainer' => s.onPrimaryContainer,
        'secondary' => s.secondary,
        'onSecondary' => s.onSecondary,
        'secondaryContainer' => s.secondaryContainer,
        'onSecondaryContainer' => s.onSecondaryContainer,
        'tertiary' => s.tertiary,
        'onTertiary' => s.onTertiary,
        'tertiaryContainer' => s.tertiaryContainer,
        'onTertiaryContainer' => s.onTertiaryContainer,
        'error' => s.error,
        'onError' => s.onError,
        'errorContainer' => s.errorContainer,
        'onErrorContainer' => s.onErrorContainer,
        'surface' => s.surface,
        'onSurface' => s.onSurface,
        'surfaceContainerLowest' => s.surfaceContainerLowest,
        'surfaceContainerLow' => s.surfaceContainerLow,
        'surfaceContainer' => s.surfaceContainer,
        'surfaceContainerHigh' => s.surfaceContainerHigh,
        'surfaceContainerHighest' => s.surfaceContainerHighest,
        'surfaceDim' => s.surfaceDim,
        'surfaceBright' => s.surfaceBright,
        'surfaceTint' => s.surfaceTint,
        'onSurfaceVariant' => s.onSurfaceVariant,
        'outline' => s.outline,
        'outlineVariant' => s.outlineVariant,
        'inverseSurface' => s.inverseSurface,
        'onInverseSurface' => s.onInverseSurface,
        'inversePrimary' => s.inversePrimary,
        'scrim' => s.scrim,
        'shadow' => s.shadow,
        _ => throw ArgumentError('Unknown color role: $role'),
      };

Map<String, Object?> _colorScheme(ColorScheme s) => <String, Object?>{
      for (final role in _kColorRoles) role: _hex(_role(s, role)),
    };

/// Every [LunarLogColors] slot the web calendar consumes (issue #1253) —
/// the flow swatches, symptom dot/palette, predicted/fertile borders, the
/// PMS/cramps badges, and the confidence tints. The two translucent band
/// fills are deliberately absent: `predictedBand`/`fertileBand` are their
/// border colour at 16% alpha, and this export's contract is fully opaque
/// colours (test/tool/export_webapp_tokens_test.dart) — the web derives
/// the fills with `color-mix(in srgb, var(--ll-cal-…-border) 16%,
/// transparent)`. Enumerated explicitly so a new palette slot lands here
/// as a reviewed change.
///
/// The `onFlow*` tones are the ink for content drawn on a `flow*` fill:
/// the web calendar fills a logged period day with its flow colour, as the
/// app's does, and writes the day number and flow marks in the matching
/// tone.
const List<String> _kCalendarColorSlots = <String>[
  'flowSpotting',
  'flowLight',
  'flowMedium',
  'flowHeavy',
  'onFlowSpotting',
  'onFlowLight',
  'onFlowMedium',
  'onFlowHeavy',
  'symptomDot',
  'symptomLayer1',
  'symptomLayer2',
  'symptomLayer3',
  'predictedBorder',
  'fertileBorder',
  'pmsBadge',
  'crampsBadge',
  'confidenceHigh',
  'confidenceLearning',
  'confidenceIrregular',
  'confidenceProvisional',
];

/// Resolves one [LunarLogColors] slot name against a concrete palette. A
/// switch (not a map of getters) so the compiler enforces exhaustiveness
/// against [_kCalendarColorSlots] at review time.
Color _calendarSlot(LunarLogColors c, String slot) => switch (slot) {
      'flowSpotting' => c.flowSpotting,
      'flowLight' => c.flowLight,
      'flowMedium' => c.flowMedium,
      'flowHeavy' => c.flowHeavy,
      'onFlowSpotting' => c.onFlowSpotting,
      'onFlowLight' => c.onFlowLight,
      'onFlowMedium' => c.onFlowMedium,
      'onFlowHeavy' => c.onFlowHeavy,
      'symptomDot' => c.symptomDot,
      'symptomLayer1' => c.symptomLayer1,
      'symptomLayer2' => c.symptomLayer2,
      'symptomLayer3' => c.symptomLayer3,
      'predictedBorder' => c.predictedBorder,
      'fertileBorder' => c.fertileBorder,
      'pmsBadge' => c.pmsBadge,
      'crampsBadge' => c.crampsBadge,
      'confidenceHigh' => c.confidenceHigh,
      'confidenceLearning' => c.confidenceLearning,
      'confidenceIrregular' => c.confidenceIrregular,
      'confidenceProvisional' => c.confidenceProvisional,
      _ => throw ArgumentError('Unknown calendar color slot: $slot'),
    };

Map<String, Object?> _calendarColors(ColorScheme s) {
  final palette = LunarLogColors.forColorScheme(s);
  return <String, Object?>{
    for (final slot in _kCalendarColorSlots) slot: _hex(_calendarSlot(palette, slot)),
  };
}

String buildWebappTokensJson() {
  final schemes = <String, Object?>{
    'light': _colorScheme(AppTheme.lightTheme.colorScheme),
    'dark': _colorScheme(AppTheme.darkTheme.colorScheme),
  };
  final type = <String, Object?>{
    for (final entry in _kTypeSlots.entries)
      entry.key: <String, Object?>{
        'fontSize': _num(entry.value.fontSize),
        'lineHeight': _num(entry.value.lineHeight),
        'fontWeight': _weightValue(entry.value.fontWeight),
        'fontFamily': entry.value.fontFamily,
        'letterSpacing': entry.value.letterSpacing,
        'tabularFigures': entry.value.fontFeatures?.any(
              (f) => f.feature == 'tnum',
            ) ??
            false,
      },
  };
  final tokens = <String, Object?>{
    'fonts': <String, String>{
      'text': LLFonts.text,
      'display': LLFonts.display,
    },
    'space': <String, Object?>{
      'space1': _num(LLSpace.space1),
      'space2': _num(LLSpace.space2),
      'space3': _num(LLSpace.space3),
      'space4': _num(LLSpace.space4),
      'space5': _num(LLSpace.space5),
      'space6': _num(LLSpace.space6),
      'space7': _num(LLSpace.space7),
    },
    'radius': <String, Object?>{
      'rSm': _num(LLRadius.rSm),
      'rMd': _num(LLRadius.rMd),
      'rLg': _num(LLRadius.rLg),
      'rXl': _num(LLRadius.rXl),
      'rFull': _num(LLRadius.rFull),
    },
    'elevation': <String, Object?>{
      'e0': _num(LLElevation.e0),
      'e1': _num(LLElevation.e1),
      'e2': _num(LLElevation.e2),
    },
    'motion': <String, Object?>{
      'fastMs': LLMotion.fast.inMilliseconds,
      'baseMs': LLMotion.base.inMilliseconds,
      'slowMs': LLMotion.slow.inMilliseconds,
    },
    'type': type,
    'schemes': schemes,
    'calendar': <String, Object?>{
      'light': _calendarColors(AppTheme.lightTheme.colorScheme),
      'dark': _calendarColors(AppTheme.darkTheme.colorScheme),
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(tokens)}\n';
}

/// Writes the export to [kWebappTokensExportPath], creating the directory.
/// Called only by `tool/export_webapp_tokens_generate_test.dart` (the
/// explicit regeneration runner) — the CI freshness test never writes.
void writeWebappTokensExport() {
  final json = buildWebappTokensJson();
  final file = File(kWebappTokensExportPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(json);
  stdout.writeln('Wrote ${file.path} (${json.length} bytes)');
}
