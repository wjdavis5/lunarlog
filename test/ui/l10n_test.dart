/// Widget tests for the localization scaffolding (issue #160):
///
/// * **Copy parity** — every string extracted into `lib/l10n/app_en.arb`
///   must equal the exact inline literal it replaced, character for
///   character. The extraction promised "no visible change"; this is the
///   guard that keeps it true for every future ARB edit.
/// * **Delegate registration** — both `MaterialApp`s (`lib/app.dart`'s and
///   the lock screen's own) carry the delegates and supported locales.
/// * **Non-English locale fallback** — under a device locale the app does
///   not ship, resolution falls back to `en` without crashing or
///   asserting (the issue's own acceptance criterion; `en` is the only
///   supported locale today).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/gate/app_gate.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_settings_store.dart';

/// The smallest gate the [GateController] accepts: never actually consulted
/// by a [LockScreen] render, it only satisfies the constructor.
class _NoopGate implements AppGate {
  @override
  bool get requiresUnlock => true;

  @override
  Future<bool> requestAccess() async => true;
}

/// Pumps a [MaterialApp] that registers the l10n delegates and captures
/// the resolved [AppLocalizations] for the parity assertions.
Future<AppLocalizations> pumpL10n(WidgetTester tester) async {
  late AppLocalizations captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          captured = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('extracted copy parity (en ARB equals the previous literals)', () {
    testWidgets('calendar chrome, legend, and layers', (tester) async {
      final l10n = await pumpL10n(tester);
      expect(l10n.calendarPreviousMonthTooltip, 'Previous month');
      expect(l10n.calendarTodayTooltip, 'Today');
      expect(l10n.calendarNextMonthTooltip, 'Next month');
      expect(l10n.calendarMonthYearLabel('September', 2026), 'September 2026');
      expect(l10n.calendarNoEntriesTitle, 'No entries this month');
      expect(l10n.calendarNoEntriesBody, 'Tap a day to log it');
      expect(l10n.calendarLayerLimitSnack, 'Up to three symptom layers at once');
      expect(l10n.calendarShowLegend, 'Show legend');
      expect(l10n.calendarHideLegend, 'Hide legend');
      expect(l10n.calendarLegend, 'Legend');
      expect(l10n.calendarLegendSpotting, 'Spotting flow');
      expect(l10n.calendarLegendLight, 'Light flow');
      expect(l10n.calendarLegendMedium, 'Medium flow');
      expect(l10n.calendarLegendHeavy, 'Heavy flow');
      expect(l10n.calendarLegendSymptom, 'Symptom day');
      expect(l10n.calendarLegendToday, 'Today');
      expect(l10n.calendarLegendPredicted, 'Predicted day');
      expect(l10n.calendarLegendPms, 'PMS window');
      expect(l10n.calendarLegendCramps, 'Cramps window');
      expect(l10n.calendarLegendLayerDots, 'Symptom layer dots');
      expect(l10n.calendarSymptomLayers, 'Symptom layers');
      expect(l10n.calendarLayersSummary('Light, Cramps'), 'Layers: Light, Cramps');
      expect(l10n.calendarShowSymptomLayers, 'Show symptom layers');
      expect(l10n.calendarHideSymptomLayers, 'Hide symptom layers');
      expect(
        l10n.calendarKeepLogging,
        'Keep logging — predicted bands appear once a few cycles are '
        'recorded.',
      );
      expect(l10n.monthPickerPreviousYear, 'Previous year');
      expect(l10n.monthPickerNextYear, 'Next year');
    });

    testWidgets('future-day explainer, including the plural', (tester) async {
      final l10n = await pumpL10n(tester);
      expect(
        l10n.futureExplainerNoEstimate,
        'No estimates yet — keep logging. Predicted bands appear on the '
        'calendar once a few cycles are recorded.',
      );
      expect(
        l10n.futureExplainerNone,
        'No prediction for this date. Days can be logged once they arrive.',
      );
      expect(
        l10n.futureExplainerBand(1),
        'Predicted period day. The date may shift by about 1 day either '
        'way as new periods are logged.',
      );
      expect(
        l10n.futureExplainerBand(3),
        'Predicted period day. The date may shift by about 3 days either '
        'way as new periods are logged.',
      );
      expect(
        l10n.futureExplainerBandWithCycleDay(5, 2),
        'Predicted period day — cycle day 5 of the first predicted cycle. '
        'The date may shift by about 2 days either way as new periods are '
        'logged.',
      );
      expect(
        l10n.futureExplainerPms,
        'Inside the predicted premenstrual window — symptoms like mood '
        'shifts and bloating often show up in the week before a period.',
      );
      expect(
        l10n.futureExplainerCramps,
        'Inside the predicted cramps window — cramps commonly occur within '
        'two days of a period start.',
      );
      expect(
        l10n.futureExplainerNumeral(17),
        'Cycle day 17 of the first predicted cycle. Only the first '
        'predicted cycle is counted day by day — estimates compound too '
        'much further out.',
      );
      expect(l10n.futureExplainerConfidence('high'), 'Estimate confidence: high.');
    });

    testWidgets('day sheet', (tester) async {
      final l10n = await pumpL10n(tester);
      expect(l10n.flowLevelNone, 'None');
      expect(l10n.flowLevelSpotting, 'Spotting');
      expect(l10n.flowLevelLight, 'Light');
      expect(l10n.flowLevelMedium, 'Medium');
      expect(l10n.flowLevelHeavy, 'Heavy');
      expect(l10n.daySheetDeleteTitle, 'Delete this entry?');
      expect(
        l10n.daySheetDeleteBody('2026-09-07'),
        'The entry for 2026-09-07 is removed from the calendar.',
      );
      expect(l10n.daySheetCancel, 'Cancel');
      expect(l10n.daySheetDelete, 'Delete');
      expect(l10n.daySheetFutureDate, "Future dates can't be logged.");
      expect(l10n.daySheetNoteLabel, 'Note');
      expect(l10n.daySheetSaveError, "Couldn't save — try again");
      expect(l10n.daySheetDeleteError, "Couldn't delete — try again");
      expect(l10n.daySheetDeleteTooltip, 'Delete entry');
      expect(l10n.daySheetSave, 'Save');
      expect(l10n.daySheetUnrecognised, 'Unrecognised');
      expect(l10n.daySheetNoEntry, 'No entry for this day.');
      expect(l10n.daySheetFlowLabel, 'Flow');
      expect(l10n.daySheetTagsLabel, 'Tags');
      expect(l10n.daySheetNoNote, 'No note');
    });

    testWidgets('overview panel', (tester) async {
      final l10n = await pumpL10n(tester);
      expect(l10n.overviewSeeHistory, 'See cycle history');
      expect(
        l10n.overviewLoggedSnackbar,
        'Recorded a medium-flow period start for today.',
      );
      expect(l10n.overviewUndo, 'Undo');
      expect(
        l10n.overviewExcludedSnackbar,
        'This cycle is excluded from future averages.',
      );
      expect(l10n.overviewLongCycleTitle, 'This cycle is unusually long');
      expect(
        l10n.overviewLongCycleBody,
        'It has run well past a typical cycle for this profile. You can '
        'exclude it from future averages, or turn off predictions if long '
        'cycles are common for this profile.',
      );
      expect(l10n.overviewLongCycleExclude, 'Exclude this cycle');
      expect(
        l10n.overviewLongCyclePredictionsOff,
        'Turn off predictions (coming soon)',
      );
      expect(
        l10n.overviewReminderHint,
        'Reminders unavailable — notifications are off',
      );
      expect(l10n.overviewTurnOnReminders, 'Turn on reminders');
    });

    testWidgets('settings screen, including the privacy dialog body',
        (tester) async {
      final l10n = await pumpL10n(tester);
      expect(l10n.settingsTitle, 'Settings');
      expect(l10n.settingsSendFeedback, 'Send feedback');
      expect(
        l10n.settingsSendFeedbackSubtitle,
        'Report a bug, ask a question, or share an idea',
      );
      expect(l10n.settingsContactSupport, 'Contact support');
      expect(l10n.settingsContactSupportSubtitle, 'Email us with a bug or question');
      expect(
        l10n.settingsContactSupportDialogBody,
        'Email us with a bug report, question, or idea:',
      );
      expect(l10n.settingsSupportHistory, 'Support history');
      expect(
        l10n.settingsSupportHistorySubtitle,
        'See replies and continue a conversation',
      );
      expect(l10n.settingsRelockTitle, 'Relock after inactivity');
      expect(
        l10n.settingsRelockSubtitle,
        'Locks the app after 2 minutes without input. Backgrounding '
        'relocks immediately. A sign-in or unlock prompt this app opened '
        'is the one exception: the app stays covered while it is on '
        'screen, and relocks as soon as it closes if you have left.',
      );
      expect(l10n.settingsHealthHeader, 'Health');
      expect(l10n.settingsHealthSyncTitle, 'Health app sync');
      expect(
        l10n.settingsHealthSyncSubtitle,
        "Choose which profile's data may sync to this phone's Health app",
      );
      expect(l10n.settingsPrivacyTitle, 'Privacy policy');
      expect(
        l10n.settingsPrivacySubtitle,
        'Sync & family sharing, protected at rest, zero tracking',
      );
      expect(l10n.settingsPrivacyDialogTitle, 'LunarLog Privacy Policy');
      expect(l10n.settingsPrivacyDialogBody, startsWith(
        'LunarLog is a family cycle tracker built for sync and sharing.',
      ));
      expect(
        l10n.settingsPrivacyDialogBody,
        endsWith(
          'Canonical policy: '
          'https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md',
        ),
      );
      expect(
        l10n.settingsPrivacyDialogBody,
        contains(
          '• Caregiver Alerts: Optional push notifications to another '
          'guardian never carry what was logged - only a generic reminder, '
          'via Firebase Cloud Messaging.',
        ),
      );
      expect(l10n.settingsClose, 'Close');
    });

    testWidgets('first-run flow (#216): extracted pre-existing literals '
        'plus the new onboarding copy', (tester) async {
      final l10n = await pumpL10n(tester);
      // Extracted verbatim from the pre-#216 first-run surface (the
      // parity promise: no visible change).
      expect(
        l10n.firstRunNoticeBody,
        'Signing in syncs this profile across your devices and lets you '
        'share it with other guardians. Until then, everything you log '
        'stays on this device.',
      );
      expect(l10n.firstRunUnderstand, 'I understand');
      expect(l10n.firstRunCreateTitle, 'Create a profile');
      expect(l10n.firstRunNameLabel, 'Name');
      expect(l10n.firstRunMinorLabel, 'This profile is for a minor');
      expect(l10n.firstRunCareModeLabel, 'Care mode');
      expect(l10n.firstRunCreateButton, 'Create profile');
      // New #216 copy, pinned for review.
      expect(l10n.firstRunValueHeadline,
          'A private cycle log for your family');
      expect(
        l10n.firstRunValueBody,
        'Guardians can share a profile and log it together. Everything '
        'works offline. No ads, no data selling, no behavioral tracking — '
        'and predictions are never paywalled.',
      );
      expect(l10n.firstRunGuardiansTitle, 'Profiles and guardians');
      expect(
        l10n.firstRunGuardiansBody,
        "Each profile holds one person's cycle log. After signing in, you "
        'can invite another guardian — a co-parent or caregiver — to view '
        'or help log it.',
      );
      expect(l10n.firstRunMinorExplainerTitle, 'About the minor checkbox');
      expect(
        l10n.firstRunMinorExplainerBody,
        "It's a label with one real effect today: the profile is kept out "
        "of this phone's Health app sync. It doesn't restrict anything "
        'else — wording and reminders come from the care mode picked on '
        'the next screen, not from this checkbox.',
      );
      expect(l10n.firstRunMinorHint,
          "A label with one effect: this profile is kept out of this "
          "phone's Health app sync.");
      expect(l10n.firstRunNext, 'Next');
      expect(l10n.firstRunSkip, 'Skip');
      expect(l10n.firstRunContinue, 'Continue');
      expect(
        l10n.firstRunCycleCaption,
        'A few optional questions to set this profile up — every one can '
        'be skipped. The goal and birth-control answers can be changed '
        'later when editing the profile.',
      );
      expect(l10n.firstRunCycleLastPeriodLabel, 'Last period start');
      expect(l10n.firstRunCycleChooseDate, 'Choose date');
      expect(l10n.firstRunCycleChangeDate, 'Change date');
      expect(l10n.firstRunCycleClearDate, 'Clear');
      expect(l10n.firstRunCycleTypicalCycleLabel,
          'Typical cycle length (days)');
      expect(l10n.firstRunCycleTypicalCycleHint, 'e.g. 28');
      expect(l10n.firstRunCycleTypicalPeriodLabel,
          'Typical period length (days)');
      expect(l10n.firstRunCycleTypicalPeriodHint, 'e.g. 5');
      expect(l10n.firstRunCycleLengthRangeError,
          'Enter a number between 10 and 90');
      expect(l10n.firstRunPeriodLengthRangeError,
          'Enter a number between 1 and 14');
      expect(l10n.firstRunCycleBirthControlLabel, 'Birth-control method');
      expect(l10n.firstRunCycleGoalLabel, 'Goal / mode');
      expect(l10n.lifeStageModeLabel, 'Life-stage mode');
      expect(l10n.birthControlNotAnswered, 'Not answered');
      expect(l10n.birthControlNone, 'None');
      expect(l10n.birthControlPill, 'Pill');
      expect(l10n.birthControlHormonalIud, 'Hormonal IUD');
      expect(l10n.birthControlCopperIud, 'Copper IUD');
      expect(l10n.birthControlImplant, 'Implant');
      expect(l10n.birthControlInjection, 'Injection');
      expect(l10n.birthControlRing, 'Vaginal ring');
      expect(l10n.birthControlPatch, 'Patch');
      expect(l10n.birthControlCondom, 'Condom');
      expect(l10n.birthControlOther, 'Other');
    });
  });

  group('delegate registration (both MaterialApps)', () {
    testWidgets("LunarLogApp's MaterialApp registers delegates + locales",
        (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      await tester.pumpWidget(LunarLogApp(db: db));
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.localizationsDelegates,
        containsAll(AppLocalizations.localizationsDelegates),
      );
      expect(app.supportedLocales, AppLocalizations.supportedLocales);
      // Same teardown discipline as the app tests (KTD16): unmount, let
      // the coordinator disposal settle, then close the database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets("LockScreen's own MaterialApp registers delegates + locales",
        (tester) async {
      final controller = GateController(gate: _NoopGate());
      addTearDown(controller.dispose);
      await tester.pumpWidget(LockScreen(controller: controller));
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.localizationsDelegates,
        containsAll(AppLocalizations.localizationsDelegates),
      );
      expect(app.supportedLocales, AppLocalizations.supportedLocales);
    });
  });

  group('non-English device locale falls back to en (#160)', () {
    testWidgets('SettingsScreen renders en copy under a fr device locale',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('fr');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Provider<SettingsStore>.value(
            value: FakeSettingsStore(),
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Untranslated (no fr ARB): resolution falls back to en without
      // crashing or asserting.
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
    });
  });
}
