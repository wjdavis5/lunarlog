// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get calendarPreviousMonthTooltip => 'Previous month';

  @override
  String get calendarTodayTooltip => 'Today';

  @override
  String get calendarNextMonthTooltip => 'Next month';

  @override
  String calendarMonthYearLabel(String month, int year) {
    return '$month $year';
  }

  @override
  String get calendarNoEntriesTitle => 'No entries this month';

  @override
  String get calendarNoEntriesBody => 'Tap a day to log it';

  @override
  String get calendarLayerLimitSnack => 'Up to three symptom layers at once';

  @override
  String get calendarShowLegend => 'Show legend';

  @override
  String get calendarHideLegend => 'Hide legend';

  @override
  String get calendarLegend => 'Legend';

  @override
  String get calendarLegendSpotting => 'Spotting flow';

  @override
  String get calendarLegendLight => 'Light flow';

  @override
  String get calendarLegendMedium => 'Medium flow';

  @override
  String get calendarLegendHeavy => 'Heavy flow';

  @override
  String get calendarLegendSuperHeavy => 'Super heavy flow (5 marks)';

  @override
  String get calendarLegendSymptom => 'Symptom day';

  @override
  String get calendarLegendToday => 'Today';

  @override
  String get calendarLegendPredicted => 'Predicted day';

  @override
  String get calendarLegendPms => 'PMS window';

  @override
  String get calendarLegendCramps => 'Cramps window';

  @override
  String get calendarLegendLayerDots => 'Symptom layer dots';

  @override
  String get calendarSymptomLayers => 'Symptom layers';

  @override
  String calendarLayersSummary(String tags) {
    return 'Layers: $tags';
  }

  @override
  String get calendarShowSymptomLayers => 'Show symptom layers';

  @override
  String get calendarHideSymptomLayers => 'Hide symptom layers';

  @override
  String get calendarKeepLogging =>
      'Keep logging — predicted bands appear once a few cycles are recorded.';

  @override
  String calendarCellDateLabel(String weekday, String month, int day) {
    return '$weekday, $month $day';
  }

  @override
  String calendarCellFlowState(String level) {
    return '$level flow';
  }

  @override
  String get calendarCellSymptomsLogged => 'symptoms logged';

  @override
  String get calendarCellNoSymptoms => 'no symptoms';

  @override
  String get calendarCellLoggedSymptoms => 'logged symptoms';

  @override
  String get calendarCellLogged => 'logged';

  @override
  String get calendarCellNotLogged => 'not logged';

  @override
  String get calendarCellToday => 'today';

  @override
  String get calendarCellFuture => 'future date, not yet loggable';

  @override
  String get calendarCellReadOnly => 'read-only';

  @override
  String get calendarCellPredictedPeriod => 'predicted period day';

  @override
  String calendarCellCycleDay(int day) {
    return 'cycle day $day';
  }

  @override
  String calendarCellCycleDayFirstCycle(int day) {
    return 'cycle day $day of the first predicted cycle';
  }

  @override
  String get calendarCellPmsWindow => 'predicted premenstrual window';

  @override
  String get calendarCellCrampsWindow => 'predicted cramps window';

  @override
  String get calendarCellNoPrediction => 'no prediction for this date';

  @override
  String get monthPickerPreviousYear => 'Previous year';

  @override
  String get monthPickerNextYear => 'Next year';

  @override
  String get futureExplainerNoEstimate =>
      'No estimates yet — keep logging. Predicted bands appear on the calendar once a few cycles are recorded.';

  @override
  String get futureExplainerNone =>
      'No prediction for this date. Days can be logged once they arrive.';

  @override
  String futureExplainerBand(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Predicted period day. The date may shift by about $count $_temp0 either way as new periods are logged.';
  }

  @override
  String futureExplainerBandWithCycleDay(int day, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Predicted period day — cycle day $day of the first predicted cycle. The date may shift by about $count $_temp0 either way as new periods are logged.';
  }

  @override
  String get futureExplainerPms =>
      'Inside the predicted premenstrual window — symptoms like mood shifts and bloating often show up in the week before a period.';

  @override
  String get futureExplainerCramps =>
      'Inside the predicted cramps window — cramps commonly occur within two days of a period start.';

  @override
  String futureExplainerNumeral(int day) {
    return 'Cycle day $day of the first predicted cycle. Only the first predicted cycle is counted day by day — estimates compound too much further out.';
  }

  @override
  String futureExplainerConfidence(String tier) {
    return 'Estimate confidence: $tier.';
  }

  @override
  String get flowLevelNone => 'None';

  @override
  String get flowLevelSpotting => 'Spotting';

  @override
  String get flowLevelLight => 'Light';

  @override
  String get flowLevelMedium => 'Medium';

  @override
  String get flowLevelHeavy => 'Heavy';

  @override
  String get flowLevelNotBleeding => 'Not bleeding';

  @override
  String get flowLevelSuperHeavy => 'Super heavy';

  @override
  String get daySheetDeleteTitle => 'Delete this entry?';

  @override
  String daySheetDeleteBody(String date) {
    return 'The entry for $date is removed from the calendar.';
  }

  @override
  String get daySheetCancel => 'Cancel';

  @override
  String get daySheetDelete => 'Delete';

  @override
  String get daySheetFutureDate => 'Future dates can\'t be logged.';

  @override
  String get daySheetNoteLabel => 'Note';

  @override
  String get daySheetSaveError => 'Couldn\'t save — try again';

  @override
  String get daySheetDeleteError => 'Couldn\'t delete — try again';

  @override
  String get daySheetDeleteTooltip => 'Delete entry';

  @override
  String get daySheetSave => 'Save';

  @override
  String get daySheetDiscardTitle => 'Discard unsaved changes?';

  @override
  String get daySheetKeepEditing => 'Keep editing';

  @override
  String get daySheetDiscard => 'Discard';

  @override
  String get daySheetSaving => 'Saving…';

  @override
  String get daySheetSaved => 'Saved';

  @override
  String get daySheetRetryHint =>
      'Couldn\'t save. Changes are kept — retry or close.';

  @override
  String get daySheetUnrecognised => 'Unrecognised';

  @override
  String get daySheetUnverifiedPin => 'Unverified — pin before shipping';

  @override
  String get daySheetNoEntry => 'No entry for this day.';

  @override
  String get daySheetFlowLabel => 'Flow';

  @override
  String get daySheetTagsLabel => 'Tags';

  @override
  String get daySheetNoNote => 'No note';

  @override
  String get cycleConfidenceHigh => 'High confidence';

  @override
  String get cycleConfidenceLearning => 'Learning';

  @override
  String get cycleConfidenceIrregular => 'Irregular';

  @override
  String get cycleConfidenceProvisional => 'Provisional';

  @override
  String get cycleConfidenceSummaryHigh =>
      'Recent cycles are steady — estimates are at their most reliable.';

  @override
  String get cycleConfidenceSummaryLearning =>
      'Still learning — estimates improve after a few more cycles.';

  @override
  String get cycleConfidenceSummaryIrregular =>
      'Cycles vary a lot — treat estimates as rough guides.';

  @override
  String get cycleConfidenceSummaryProvisional =>
      'Based on your onboarding answers — estimates improve once real cycles are logged.';

  @override
  String get overviewSeeHistory => 'See cycle history';

  @override
  String get overviewLoggedSnackbar =>
      'Recorded a medium-flow period start for today.';

  @override
  String get overviewUndo => 'Undo';

  @override
  String get overviewExcludedSnackbar =>
      'This cycle is excluded from future averages.';

  @override
  String get overviewLongCycleTitle => 'This cycle is unusually long';

  @override
  String get overviewLongCycleBody =>
      'It has run well past a typical cycle for this profile. You can exclude it from future averages, or turn off predictions if long cycles are common for this profile.';

  @override
  String get overviewLongCycleExclude => 'Exclude this cycle';

  @override
  String get overviewLongCyclePredictionsOff =>
      'Turn off predictions (coming soon)';

  @override
  String get overviewReminderHint =>
      'Reminders unavailable — notifications are off';

  @override
  String get overviewTurnOnReminders => 'Turn on reminders';

  @override
  String cycleWheelCenterCycleDay(int day) {
    return 'Cycle day $day';
  }

  @override
  String cycleWheelCenterPeriodDay(int day) {
    return 'Period · day $day';
  }

  @override
  String cycleWheelPhasePeriodDay(int day) {
    return 'Period, day $day';
  }

  @override
  String cycleWheelSemanticsBody(String phase, int cycleDays, int periodDays) {
    return '$phase of about $cycleDays days. Period usually runs about $periodDays days.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSendFeedback => 'Send feedback';

  @override
  String get settingsSendFeedbackSubtitle =>
      'Report a bug, ask a question, or share an idea';

  @override
  String get settingsContactSupport => 'Contact support';

  @override
  String get settingsContactSupportSubtitle =>
      'Email us with a bug or question';

  @override
  String get settingsContactSupportDialogBody =>
      'Email us with a bug report, question, or idea:';

  @override
  String get settingsSupportHistory => 'Support history';

  @override
  String get settingsSupportHistorySubtitle =>
      'See replies and continue a conversation';

  @override
  String get settingsRelockTitle => 'Relock after inactivity';

  @override
  String get settingsRelockSubtitle =>
      'Locks the app after 2 minutes without input. Backgrounding relocks immediately. A sign-in or unlock prompt this app opened is the one exception: the app stays covered while it is on screen, and relocks as soon as it closes if you have left.';

  @override
  String get settingsHealthHeader => 'Health';

  @override
  String get settingsHealthSyncTitle => 'Health app sync';

  @override
  String get settingsHealthSyncSubtitle =>
      'Choose which profile\'s data may sync to this phone\'s Health app';

  @override
  String get settingsPrivacyTitle => 'Privacy policy';

  @override
  String get settingsPrivacySubtitle =>
      'Sync & family sharing, protected at rest, zero tracking';

  @override
  String get settingsPrivacyDialogTitle => 'LunarLog Privacy Policy';

  @override
  String get settingsPrivacyDialogBody =>
      'LunarLog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind biometric authentication.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Caregiver Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md';

  @override
  String get settingsClose => 'Close';

  @override
  String get firstRunValueHeadline => 'A private cycle log for your family';

  @override
  String get firstRunValueBody =>
      'Guardians can share a profile and log it together. Everything works offline. No ads, no data selling, no behavioral tracking — and predictions are never paywalled.';

  @override
  String get firstRunGuardiansTitle => 'Profiles and guardians';

  @override
  String get firstRunGuardiansBody =>
      'Each profile holds one person\'s cycle log. After signing in, you can invite another guardian — a co-parent or caregiver — to view or help log it.';

  @override
  String get firstRunMinorExplainerTitle => 'About the minor checkbox';

  @override
  String get firstRunMinorExplainerBody =>
      'It\'s a label with one real effect today: the profile is kept out of this phone\'s Health app sync. It doesn\'t restrict anything else — wording and reminders come from the care mode picked on the next screen, not from this checkbox.';

  @override
  String get firstRunNoticeBody =>
      'Signing in syncs this profile across your devices and lets you share it with other guardians. Until then, everything you log stays on this device.';

  @override
  String get firstRunNext => 'Next';

  @override
  String get firstRunSkip => 'Skip';

  @override
  String get firstRunUnderstand => 'I understand';

  @override
  String get firstRunCreateTitle => 'Create a profile';

  @override
  String get firstRunNameLabel => 'Name';

  @override
  String get firstRunMinorLabel => 'This profile is for a minor';

  @override
  String get firstRunMinorHint =>
      'A label with one effect: this profile is kept out of this phone\'s Health app sync.';

  @override
  String get firstRunCareModeLabel => 'Care mode';

  @override
  String get firstRunContinue => 'Continue';

  @override
  String get firstRunCycleCaption =>
      'A few optional questions to set this profile up — every one can be skipped. The goal and birth-control answers can be changed later when editing the profile.';

  @override
  String get firstRunCycleLastPeriodLabel => 'Last period start';

  @override
  String get firstRunCycleChooseDate => 'Choose date';

  @override
  String get firstRunCycleChangeDate => 'Change date';

  @override
  String get firstRunCycleClearDate => 'Clear';

  @override
  String get firstRunCycleTypicalCycleLabel => 'Typical cycle length (days)';

  @override
  String get firstRunCycleTypicalCycleHint => 'e.g. 28';

  @override
  String get firstRunCycleTypicalPeriodLabel => 'Typical period length (days)';

  @override
  String get firstRunCycleTypicalPeriodHint => 'e.g. 5';

  @override
  String get firstRunCycleLengthRangeError =>
      'Enter a number between 10 and 90';

  @override
  String get firstRunPeriodLengthRangeError =>
      'Enter a number between 1 and 14';

  @override
  String get firstRunCycleBirthControlLabel => 'Birth-control method';

  @override
  String get firstRunCycleGoalLabel => 'Goal / mode';

  @override
  String get firstRunCreateButton => 'Create profile';

  @override
  String get lifeStageModeLabel => 'Life-stage mode';

  @override
  String get birthControlNotAnswered => 'Not answered';

  @override
  String get birthControlNone => 'None';

  @override
  String get birthControlPill => 'Pill';

  @override
  String get birthControlHormonalIud => 'Hormonal IUD';

  @override
  String get birthControlCopperIud => 'Copper IUD';

  @override
  String get birthControlImplant => 'Implant';

  @override
  String get birthControlInjection => 'Injection';

  @override
  String get birthControlRing => 'Vaginal ring';

  @override
  String get birthControlPatch => 'Patch';

  @override
  String get birthControlCondom => 'Condom';

  @override
  String get birthControlOther => 'Other';

  @override
  String get birthControlIntakeTaken => 'Taken';

  @override
  String get birthControlIntakeLate => 'Late';

  @override
  String get birthControlIntakeMissed => 'Missed';

  @override
  String get daySheetPmsChip => 'PMS';

  @override
  String get daySheetPmsGroup => 'PMS';

  @override
  String get daySheetIntensityGroup => 'Intensity';

  @override
  String get daySheetIntensityClear => 'Clear';

  @override
  String overviewPmsBandLabel(String range) {
    return 'Predicted PMS: $range';
  }

  @override
  String overviewPmsDaysBeforePeriod(int days, int length) {
    return 'usually starts about $days days before your period and lasts about $length days';
  }

  @override
  String get reminderSectionCycle => 'Your cycle';

  @override
  String get reminderSectionBirthControl => 'Your birth control';

  @override
  String get reminderSectionOther => 'Other reminders';

  @override
  String get reminderKindPeriodStartingSoon => 'Period starting soon';

  @override
  String get reminderKindPeriodStartingSoonSubtitle =>
      'An earlier heads-up than the due reminder';

  @override
  String get reminderKindPeriodDue => 'Period due';

  @override
  String get reminderKindPeriodDueSubtitle =>
      'A heads-up before the predicted period starts';

  @override
  String get reminderKindPmsWatch => 'PMS watch';

  @override
  String get reminderKindPmsWatchSubtitle =>
      'An earlier heads-up for pre-period days';

  @override
  String get reminderKindPeriodLate => 'Period late';

  @override
  String get reminderKindPeriodLateSubtitle =>
      'A daily nudge while the cycle runs late';

  @override
  String get reminderKindFertileWindowSoon => 'Fertile window soon';

  @override
  String get reminderKindFertileWindowSoonSubtitle =>
      'A heads-up before the predicted fertile window';

  @override
  String get reminderKindCycleStats => 'Cycle statistic changes';

  @override
  String get reminderKindCycleStatsSubtitle =>
      'A note when your displayed averages shift meaningfully';

  @override
  String get reminderKindLogNudge => 'Daily log nudge';

  @override
  String get reminderKindLogNudgeSubtitle => 'A daily prompt to log the day';

  @override
  String get reminderLeadDaysBeforeStart => 'Days before predicted start';

  @override
  String get reminderLeadDaysBeforePms => 'Days before predicted PMS window';

  @override
  String get reminderLeadDaysBeforeFertileWindow =>
      'Days before predicted fertile window';

  @override
  String get reminderBirthControlTitle => 'Birth-control reminders';

  @override
  String get reminderBirthControlComingSoon => 'Coming in a future update';
}
