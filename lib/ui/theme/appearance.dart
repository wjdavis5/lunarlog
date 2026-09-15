/// Issue #137: the appearance-override codec — the single mapping between
/// the persisted `SettingsKeys.themeMode` string (`'system'`/`'light'`/
/// `'dark'`) and [ThemeMode]. Every reader of the override (the main
/// `MaterialApp` in `lib/app.dart`, the lock screen's via
/// `lib/app_root.dart`, and the Settings picker) goes through these two
/// functions, so the wire format and the unrecognized-value fallback are
/// each defined exactly once.
///
/// The fallback is `ThemeMode.system` (follow the OS brightness) for both
/// an absent value *and* an unrecognized one: a value this build cannot
/// parse — including one written by a future build — must degrade to the
/// issue's default posture, never wedge the app on a single appearance.
///
/// Surfaces that render while no settings store exists at all (the
/// fail-closed screen, whose database failed to open; the lock screen at
/// cold start, whose database is deliberately not opened until the gate
/// unlocks — AE4) simply hardcode `ThemeMode.system` instead: following
/// the system is exactly the fallback those states would compute anyway.
library;

import 'package:flutter/material.dart';

/// Parses the persisted override. `null`, `'system'`, and any
/// unrecognized value all resolve to [ThemeMode.system].
ThemeMode themeModeFromStored(String? value) => switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Encodes [mode] for persistence through `SettingsStore.set`.
String storedThemeMode(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
