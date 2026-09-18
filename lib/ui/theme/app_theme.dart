/// Single theme factory (issue #176; B-1, B-3, B-4, B-34): the one place
/// [ThemeData] is built, consumed by all of `lib/`'s `MaterialApp`s
/// (`lib/app.dart`, `lib/ui/gate/lock_screen.dart`,
/// `lib/ui/startup/fail_closed_screen.dart`, and the two shell
/// placeholders in `lib/app_root.dart`) so a theme change is made once
/// instead of five times.
///
/// [darkTheme] is wired in through `darkTheme:`/`themeMode:` by every
/// `MaterialApp` since issue #137 (system-following by default, with the
/// device-local `SettingsKeys.themeMode` override resolved by
/// `lib/ui/theme/appearance.dart`) —
/// `test/architecture/theme_wiring_test.dart` guards that no `MaterialApp`
/// in `lib/` can regress to light-only wiring.
///
/// [lightTheme]/[darkTheme] are memoized `static final`s, built once at
/// class load rather than on every read (issue #176 review): a getter that
/// rebuilt a fresh [ThemeData] on every access, combined with
/// [LunarLogColors] having no `==`/`hashCode` of its own, meant no two reads
/// of "the same" theme ever compared `==` -- so `AnimatedTheme` restarted
/// its cross-fade and every `Theme.of` dependent rebuilt on every
/// `setState`, even when nothing about the theme had changed.
library;

import 'package:flutter/material.dart';

import 'lunarlog_colors.dart';
import 'tokens.dart';

abstract final class AppTheme {
  /// The existing seed colour (a teal), unchanged by this issue.
  static const Color _seed = Color(0xFF00696F);

  static final ThemeData lightTheme = _build(Brightness.light);
  static final ThemeData darkTheme = _build(Brightness.dark);

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

  /// The type ramp (B-4), matching issue #176's table and #807. `displayLarge`
  /// and the unused `headlineLarge` slot are left at Flutter's M3 default.
  static TextTheme _textTheme() {
    return TextTheme(
      displayMedium: LLType.displayMedium.toTextStyle(),
      displaySmall: LLType.displaySmall.toTextStyle(),
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
    final radius = BorderRadius.circular(LLRadius.rMd);
    // The idle/enabled/disabled state stays borderless (`BorderSide.none`)
    // -- filled M3 fields read their resting state from `fillColor` alone.
    // But Flutter does *not* derive `focusedBorder`/`errorBorder`/
    // `focusedErrorBorder` from `border` when `border.borderSide` is
    // `BorderSide.none` (it short-circuits rather than substituting a
    // themed colour), so leaving those three unset silently drops the
    // focus and validation-error indicator from every text field in the
    // app. Declaring them explicitly restores state-aware borders without
    // giving the idle state a visible outline it never had.
    return InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.error, width: 2),
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
