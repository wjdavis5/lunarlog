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
  String get daySheetUnrecognised => 'Unrecognised';

  @override
  String get daySheetNoEntry => 'No entry for this day.';

  @override
  String get daySheetFlowLabel => 'Flow';

  @override
  String get daySheetTagsLabel => 'Tags';

  @override
  String get daySheetNoNote => 'No note';

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
}
