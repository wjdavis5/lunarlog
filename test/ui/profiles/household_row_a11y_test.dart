/// Widget tests for the household row at accessibility text sizes
/// (issue #1233): the profile picker's trailing "Log today" button scales
/// with the text, and inside a `ListTile` it takes its intrinsic width —
/// at the accessibility sizes the row's title and signal lines were
/// squeezed into a glyph-wide column ("Maya" one letter per line,
/// "Period expected today" breaking mid-word).
///
/// The fix is the same stacked-layout answer #836 gave the today card:
/// above [kProfileCardStackedTextScale] ([profileCardStacksTrailingAt])
/// `ProfileCard` renders the tile full width and moves the trailing
/// controls beneath it, so these tests pump the card the picker wires
/// (`profile_picker_screen.dart`'s household trailing — its keys are
/// mirrored here on purpose, the way `profile_card_test.dart` mirrors the
/// #126 badge keys) on a phone-width surface at the issue's reported
/// 3.1x scale and at the default 1.0x, and pin both layouts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/profile_card.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

/// Fixed "today" (the shape `profile_card_test.dart` uses).
final LocalDate kToday = LocalDate(2026, 9, 10);

Profile _profile() => Profile(
      id: 'p1',
      displayName: 'Maya',
      isMinor: true,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// The household row exactly as `profile_picker_screen.dart`'s `_row`
/// wires it for a multi-profile operator (the trailing mirrors that
/// screen's `Tooltip > TextButton(log-today-…)` + overflow menu Wrap —
/// keys mirrored here on purpose, the way `profile_card_test.dart`
/// mirrors the #126 badge keys).
Widget _householdRow({void Function()? onLogToday}) => ProfileCard(
      key: const ValueKey('profile-row-p1'),
      profile: _profile(),
      info: const SharingProfileInfo.unknown(),
      todayProvider: () => kToday,
      subtitle: 'Created Jan 1, 2026',
      // The caller-owned #803 signal line (the real one is
      // [HouseholdRowSignals]; the card only places any widget).
      subtitleExtra: const Text(
        'Period expected today',
        key: ValueKey('household-timing-p1'),
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Tooltip(
            message: 'Log today for Maya',
            child: TextButton(
              key: const ValueKey('log-today-p1'),
              onPressed: onLogToday,
              child: const Text('Log today'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile actions',
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
            ],
          ),
        ],
      ),
    );

/// Pumps one household row on a 402-pt-wide surface (the iPhone the issue
/// was found on) at [textScale], through a `MediaQuery` override the
/// #836 test established. 402 x 1200 logical pixels: tall enough that the
/// stacked row still fits without scrolling, so the taps below are
/// honest.
Future<void> _pumpRow(
  WidgetTester tester, {
  double textScale = 1.0,
  void Function()? onLogToday,
}) async {
  tester.view.physicalSize = const Size(402, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(children: [_householdRow(onLogToday: onLogToday)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('profileCardStacksTrailingAt (pure, issue #1233)', () {
    test('the standard text sizes keep the side-by-side row', () {
      expect(profileCardStacksTrailingAt(TextScaler.noScaling), isFalse);
      for (final scale in const [1.0, 1.1, 1.3, 1.5, 1.8]) {
        expect(
          profileCardStacksTrailingAt(TextScaler.linear(scale)),
          isFalse,
          reason: 'scale $scale is a standard size, not an accessibility one',
        );
      }
    });

    test('every platform accessibility text size stacks', () {
      // iOS AX 1.94-3.12 and Android's 2.0+ accessibility steps (the
      // threshold's doc comment carries the ladders).
      for (final scale in const [1.94, 2.0, 2.34, 2.62, 3.1, 3.12]) {
        expect(
          profileCardStacksTrailingAt(TextScaler.linear(scale)),
          isTrue,
          reason: 'scale $scale is an accessibility size',
        );
      }
    });
  });

  testWidgets(
    'at accessibility text sizes the trailing actions stack beneath the '
    'title: the name renders one line at a sensible width and the signal '
    'line keeps the row (#1233)',
    (tester) async {
      var logTaps = 0;
      await _pumpRow(tester, textScale: 3.1, onLogToday: () => logTaps++);

      // The side-by-side layout overflowed the row here (that is the
      // reported bug); the stacked one must lay out clean.
      expect(tester.takeException(), isNull);

      // The actions moved beneath the tile...
      expect(
        find.byKey(const ValueKey('profile-card-stacked-actions-p1')),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('log-today-p1'))).dy,
        greaterThan(tester.getCenter(find.text('Maya')).dy),
        reason: 'the Log today action renders beneath the name',
      );
      // ...and remain the same actions, still tappable.
      expect(find.byTooltip('Profile actions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('log-today-p1')));
      expect(logTaps, 1);

      // The name is a single line at a sensible width. The type ramp pins
      // titleMedium at 16/24, so at 3.1x one line is ~74pt and two are
      // ~149; the test font advances one glyph per em, so "Maya" wants
      // ~198pt on one line — a stacked row gives it the width, a starved
      // one-letter-per-line column never could.
      final title = tester.getSize(find.text('Maya'));
      expect(title.width, greaterThan(150), reason: 'the name is not '
          'squeezed into a glyph-wide column');
      expect(title.height, lessThan(100), reason: '"Maya" renders on one '
          'line (one 74pt line at 3.1x, not two 149pt)');

      // The signal line gets the full row width too — word wraps, never
      // the mid-word glyph column of the report.
      final signal =
          tester.getSize(find.byKey(const ValueKey('household-timing-p1')));
      expect(signal.width, greaterThan(150));
    },
  );

  testWidgets(
    'at the default text size the row keeps its side-by-side layout '
    '(behaviour unchanged for everyone below the threshold)',
    (tester) async {
      await _pumpRow(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('profile-card-stacked-actions-p1')),
        findsNothing,
        reason: 'no stacked actions block at 1.0x',
      );
      // The action still sits on the tile itself, beside the title.
      expect(find.byKey(const ValueKey('log-today-p1')), findsOneWidget);
      expect(find.byTooltip('Profile actions'), findsOneWidget);
    },
  );
}
