/// Single theme factory (issue #176; B-1, B-3, B-4, B-34): the one place
/// [ThemeData] is built, consumed by all three `MaterialApp`s
/// (`lib/app.dart`, `lib/ui/gate/lock_screen.dart`,
/// `lib/ui/startup/fail_closed_screen.dart`) so a theme change is made once
/// instead of three times.
///
/// [darkTheme] exists and is unit-tested for role completeness and contrast
/// (`test/ui/theme_test.dart`), but no `MaterialApp` wires it in via
/// `darkTheme:`/`themeMode:` yet -- flipping the app to follow system
/// brightness is issue #137's job, which should consume this factory rather
/// than invent its own dark palette.
library;

import 'package:flutter/material.dart';

import 'lunarlog_colors.dart';
import 'tokens.dart';

abstract final class AppTheme {
  /// The existing seed colour (a teal), unchanged by this issue.
  static const Color _seed = Color(0xFF00696F);

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final textTheme = _textTheme();
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      chipTheme: _chipTheme(colorScheme, textTheme),
      cardTheme: _cardTheme(colorScheme),
      inputDecorationTheme: _inputDecorationTheme(colorScheme),
      listTileTheme: _listTileTheme(colorScheme),
      extensions: [LunarLogColors.forColorScheme(colorScheme)],
    );
  }

  /// The type ramp (B-4), matching issue #176's table. `display*` and the
  /// unused `headlineLarge` slot are left at Flutter's M3 default.
  static TextTheme _textTheme() {
    return TextTheme(
      headlineMedium: LLType.headlineMedium.toTextStyle(),
      headlineSmall: LLType.headlineSmall.toTextStyle(),
      titleLarge: LLType.titleLarge.toTextStyle(),
      titleMedium: LLType.titleMedium.toTextStyle(),
      titleSmall: LLType.titleSmall.toTextStyle(),
      bodyLarge: LLType.bodyLarge.toTextStyle(),
      bodyMedium: LLType.bodyMedium.toTextStyle(),
      bodySmall: LLType.bodySmall.toTextStyle(),
      labelLarge: LLType.labelLarge.toTextStyle(),
      labelMedium: LLType.labelMedium.toTextStyle(),
      labelSmall: LLType.labelSmall.toTextStyle(),
    );
  }

  static ChipThemeData _chipTheme(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.secondaryContainer,
      labelStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LLSpace.space3,
        vertical: LLSpace.space1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LLRadius.rFull),
      ),
      side: BorderSide.none,
    );
  }

  static CardThemeData _cardTheme(ColorScheme colorScheme) {
    return CardThemeData(
      elevation: LLElevation.e1,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LLRadius.rLg),
      ),
      margin: const EdgeInsets.all(LLSpace.space2),
    );
  }

  static InputDecorationThemeData _inputDecorationTheme(
    ColorScheme colorScheme,
  ) {
    return InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LLRadius.rMd),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LLSpace.space4,
        vertical: LLSpace.space3,
      ),
    );
  }

  static ListTileThemeData _listTileTheme(ColorScheme colorScheme) {
    return ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LLRadius.rMd),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LLSpace.space4,
        vertical: LLSpace.space1,
      ),
      iconColor: colorScheme.onSurfaceVariant,
    );
  }
}
