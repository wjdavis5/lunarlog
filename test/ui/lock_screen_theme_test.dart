/// Issue #886: [LockScreen] hosts its own [MaterialApp] (so it can follow
/// `themeMode` independent of the app content), but it used to resolve
/// `Theme.of(context)` from the *enclosing* context — a light [ThemeData] —
/// and paint that theme's explicitly-coloured `headlineSmall` onto the
/// nested app's dark `Scaffold`. The measured result was ~1.28:1: a
/// near-invisible title on the screen every re-lock shows.
///
/// These tests pump the screen under a light ancestor with
/// `themeMode: ThemeMode.dark` (and the dark-ancestor/light-mode mirror),
/// then recompute WCAG contrast between the resolved title ink and the
/// background the nested `Scaffold` actually paints. The shared helper in
/// `test/support/wcag_contrast.dart` is the same math `theme_test.dart`
/// uses (issue #886 review).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

import '../support/wcag_contrast.dart';
import 'gate_test.dart' show FakeGate;

/// Resolves the painted title ink and the background it sits on for a
/// [LockScreen] pumped under [ancestorTheme] with its own [lockThemeMode].
Future<({Color title, Color background})> _resolveTitle(
  WidgetTester tester, {
  required ThemeData ancestorTheme,
  required ThemeMode lockThemeMode,
}) async {
  final controller = GateController(gate: FakeGate(canAuthenticateNext: true));
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: ancestorTheme,
      home: LockScreen(controller: controller, themeMode: lockThemeMode),
    ),
  );
  // `MaterialApp` cross-fades theme changes through `AnimatedTheme`; when a
  // later case reuses the tree a bare `pump()` would read a mid-lerp colour.
  await tester.pumpAndSettle();

  final titleWidget = tester.widget<Text>(find.text('lunarlog is locked'));
  final titleColor = titleWidget.style?.color;
  expect(
    titleColor,
    isNotNull,
    reason:
        'ThemeData merges an explicit colour into the text theme, so '
        'the title style must carry a resolved colour to contrast against',
  );

  final scaffoldContext = tester.element(
    find.byKey(const ValueKey('lock-screen')),
  );
  final background = Theme.of(scaffoldContext).scaffoldBackgroundColor;

  return (title: titleColor!, background: background);
}

void main() {
  testWidgets(
    'light ancestor + ThemeMode.dark: the title clears 4.5:1 against the '
    'painted dark Scaffold (issue #886)',
    (tester) async {
      final resolved = await _resolveTitle(
        tester,
        ancestorTheme: AppTheme.lightTheme,
        lockThemeMode: ThemeMode.dark,
      );

      final ratio = wcagContrastRatio(resolved.title, resolved.background);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'the lock-screen title must come from the nested dark theme, '
            'not the enclosing light one (measured $ratio)',
      );
    },
  );

  testWidgets(
    'dark ancestor + ThemeMode.light: the mirror case also clears 4.5:1 '
    '(issue #886)',
    (tester) async {
      final resolved = await _resolveTitle(
        tester,
        ancestorTheme: AppTheme.darkTheme,
        lockThemeMode: ThemeMode.light,
      );

      final ratio = wcagContrastRatio(resolved.title, resolved.background);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'the lock-screen title must come from the nested light theme '
            'when the ancestor is dark (measured $ratio)',
      );
    },
  );

  testWidgets('the title colour tracks the nested theme, not the ancestor '
      '(issue #886)', (tester) async {
    final dark = await _resolveTitle(
      tester,
      ancestorTheme: AppTheme.lightTheme,
      lockThemeMode: ThemeMode.dark,
    );
    final light = await _resolveTitle(
      tester,
      ancestorTheme: AppTheme.lightTheme,
      lockThemeMode: ThemeMode.light,
    );

    expect(
      dark.title,
      AppTheme.darkTheme.textTheme.headlineSmall?.color,
      reason: 'dark mode must paint the dark theme headline ink',
    );
    expect(
      light.title,
      AppTheme.lightTheme.textTheme.headlineSmall?.color,
      reason: 'light mode must paint the light theme headline ink',
    );
  });
}
