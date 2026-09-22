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
  String get calendarLegendPredicted => 'Estimated day';

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
      'Keep logging — estimated bands appear once a few cycles are recorded.';

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
  String get calendarCellPredictedPeriod => 'estimated period day';

  @override
  String calendarCellCycleDay(int day) {
    return 'cycle day $day';
  }

  @override
  String calendarCellCycleDayFirstCycle(int day) {
    return 'cycle day $day of the first estimated cycle';
  }

  @override
  String get calendarCellPmsWindow => 'estimated premenstrual window';

  @override
  String get calendarCellCrampsWindow => 'estimated cramps window';

  @override
  String get calendarCellNoPrediction => 'no estimate for this date';

  @override
  String get cyclePredictionLoadError => 'Could not load the cycle estimate.';

  @override
  String get cycleHistoryLoadError => 'Could not load cycle history.';

  @override
  String get cycleHistoryOpenCycleNotCounted =>
      'Not counted yet — the next period completes it';

  @override
  String get cycleComparisonToggleButton => 'Compare cycles';

  @override
  String get cycleComparisonCancelButton => 'Cancel';

  @override
  String cycleComparisonSelectedCount(int count) {
    return '$count of 2 selected';
  }

  @override
  String get cycleComparisonOpenButton => 'Compare';

  @override
  String cycleComparisonSelectCycleSemantic(String date) {
    return 'Select cycle starting $date for comparison';
  }

  @override
  String get cycleComparisonSelectCurrentCycleSemantic =>
      'Select current cycle for comparison';

  @override
  String get cycleComparisonScreenTitle => 'Compare cycles';

  @override
  String get cycleComparisonNotEnoughTitle => 'Nothing to compare yet';

  @override
  String get cycleComparisonNotEnoughBody =>
      'Select two cycles from your cycle history to compare them side by side.';

  @override
  String cycleComparisonSideHeading(String date) {
    return 'Cycle starting $date';
  }

  @override
  String cycleComparisonCurrentCycleHeading(String date) {
    return 'Current cycle (started $date)';
  }

  @override
  String get cycleComparisonExcludedBadge => 'Excluded from averages';

  @override
  String get cycleComparisonLengthLabel => 'Length';

  @override
  String get cycleComparisonOngoingLabel => 'Ongoing';

  @override
  String get cycleComparisonBleedDaysLabel => 'Bleed days';

  @override
  String get cycleComparisonLengthDifferenceLabel => 'Length difference';

  @override
  String get cycleComparisonBleedDaysDifferenceLabel => 'Bleed days difference';

  @override
  String get cycleComparisonLengthDifferenceUnknown => 'Not yet known';

  @override
  String cycleComparisonDayHeading(int day) {
    return 'Day $day';
  }

  @override
  String get cycleComparisonNoEntryLabel => 'Not logged';

  @override
  String get cycleComparisonCycleEndedLabel => 'Cycle ended';

  @override
  String get monthPickerPreviousYear => 'Previous year';

  @override
  String get monthPickerNextYear => 'Next year';

  @override
  String get futureExplainerNoEstimate =>
      'No estimates yet — keep logging. Estimated bands appear on the calendar once a few cycles are recorded.';

  @override
  String get futureExplainerNone =>
      'No estimate for this date. Days can be logged once they arrive.';

  @override
  String futureExplainerBand(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Estimated period day. The date may shift by about $count $_temp0 either way as new periods are logged.';
  }

  @override
  String futureExplainerBandWithCycleDay(int day, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Estimated period day — cycle day $day of the first estimated cycle. The date may shift by about $count $_temp0 either way as new periods are logged.';
  }

  @override
  String get futureExplainerPms =>
      'Inside the estimated premenstrual window — symptoms like mood shifts and bloating often show up in the week before a period.';

  @override
  String get futureExplainerCramps =>
      'Inside the estimated cramps window — cramps commonly occur within two days of a period start.';

  @override
  String futureExplainerNumeral(int day) {
    return 'Cycle day $day of the first estimated cycle. Only the first estimated cycle is counted day by day — estimates compound too much further out.';
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
  String get daySheetNoteHint => 'Anything worth remembering about today?';

  @override
  String get daySheetDoneLabel => 'Done';

  @override
  String get daySheetSaveError => 'Couldn\'t save — try again';

  @override
  String get daySheetSaveErrorFutureDate =>
      'This day is more than a day in the future, so it can\'t be saved.';

  @override
  String get daySheetSaveErrorBeforeBirthYear =>
      'This day is before the profile\'s birth year, so it can\'t be saved. Update the birth year in the profile\'s settings.';

  @override
  String get daySheetDeleteError => 'Couldn\'t delete — try again';

  @override
  String get daySheetDeleteTooltip => 'Delete entry';

  @override
  String get daySheetDeletedSnackbar => 'Entry deleted.';

  @override
  String get daySheetUndo => 'Undo';

  @override
  String get daySheetCycleStartDialogTitle => 'Start a new cycle?';

  @override
  String daySheetCycleStartDialogBody(
    int cycleDay,
    String flow,
    int cycleLength,
  ) {
    return 'This looks early — you\'re on cycle day $cycleDay. Logging $flow flow starts a new cycle, closes the current one after $cycleLength days, and updates your averages and estimates. Spotting never starts a cycle.';
  }

  @override
  String get daySheetCycleStartConfirm => 'Start new cycle';

  @override
  String get daySheetCycleStartSpotting => 'Log spotting instead';

  @override
  String get daySheetCycleStartSnackbar =>
      'New cycle started — history and estimates updated.';

  @override
  String get daySheetCycleHistorySnackbar => 'Cycle history updated.';

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
  String get daySheetUnmappedFallback => 'Unrecognised data';

  @override
  String get daySheetUnmappedImported => 'Imported, not recognised';

  @override
  String get daySheetTagSearchHint => 'Search';

  @override
  String get daySheetTagSearchSemanticsLabel => 'Search tags';

  @override
  String get daySheetTagSearchClearTooltip => 'Clear search';

  @override
  String get daySheetTagRecentLabel => 'Recent';

  @override
  String get daySheetCustomTagsLabel => 'Custom tags';

  @override
  String get daySheetCustomTagsManageTooltip => 'Manage custom tags';

  @override
  String get daySheetCustomTagsNone => 'None yet — tap manage to add one';

  @override
  String get customTagsSheetTitle => 'Custom tags';

  @override
  String get customTagsEmptyList => 'No custom tags yet — add one below.';

  @override
  String get customTagsAddHint => 'New tag name';

  @override
  String get customTagsAddTooltip => 'Add tag';

  @override
  String get customTagsErrorEmpty => 'Enter a name.';

  @override
  String get customTagsErrorTooLong => 'Names are at most 40 characters.';

  @override
  String get customTagsErrorNoLetters => 'Include a letter or digit.';

  @override
  String get customTagsErrorDuplicate => 'You already have a tag like this.';

  @override
  String get customTagsErrorTaxonomy => 'That name is already a built-in tag.';

  @override
  String customTagsErrorCap(int max) {
    return 'This profile already has $max custom tags — retire one first.';
  }

  @override
  String get customTagsRenameTooltip => 'Rename';

  @override
  String get customTagsRenameTitle => 'Rename tag';

  @override
  String get customTagsRetireTooltip => 'Retire';

  @override
  String get customTagsRetiredLabel => 'Retired';

  @override
  String customTagsRetireTitle(String label) {
    return 'Retire “$label”?';
  }

  @override
  String get customTagsRetireBody =>
      'It leaves the tag picker. Days that already use it keep showing it.';

  @override
  String get customTagsRetireConfirm => 'Retire';

  @override
  String get daySheetNoEntry => 'No entry for this day.';

  @override
  String get daySheetFlowLabel => 'Flow';

  @override
  String get daySheetTagsLabel => 'Tags';

  @override
  String get daySheetSpottingGroup => 'Spotting';

  @override
  String get daySheetChildObservationsLoading => 'Loading additional details…';

  @override
  String get daySheetChildObservationsError =>
      'Could not load additional details.';

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
  String get cycleConfidenceShortHigh => 'high';

  @override
  String get cycleConfidenceShortLearning => 'learning';

  @override
  String get cycleConfidenceShortIrregular => 'rough';

  @override
  String get cycleConfidenceShortProvisional => 'provisional';

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
  String get overviewEstimateLoadError => 'Could not load your cycle estimate.';

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
      'It has run well past a typical cycle for this profile. You can exclude it from future averages, or turn off estimates if long cycles are common for this profile.';

  @override
  String get overviewLongCycleExclude => 'Exclude this cycle';

  @override
  String get overviewLongCyclePredictionsOff => 'Turn off estimates';

  @override
  String get overviewStaleHistoryTitle => 'Your history is out of date';

  @override
  String get overviewStaleHistoryBody =>
      'It has been a long time since you logged a period, so cycle estimates would not be reliable. Log a period when it starts to pick estimates back up. You can also turn estimates off.';

  @override
  String get overviewStaleHistoryLog => 'Log a period';

  @override
  String get overviewReminderHint =>
      'Reminders unavailable — notifications are off';

  @override
  String get overviewTurnOnReminders => 'Turn on reminders';

  @override
  String get overviewAboutThisEstimate => 'About this estimate';

  @override
  String get todayCardLogPeriodStartedToday => 'Period started today';

  @override
  String get todayCardRecordEntryError =>
      'Couldn\'t record today\'s entry — try again.';

  @override
  String cycleWheelDaysUntilUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String cycleWheelDaysPastEstimateUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days past estimate',
      one: 'day past estimate',
    );
    return '$_temp0';
  }

  @override
  String cycleWheelSemanticsPastEstimate(
    int daysPast,
    int cycleDay,
    int cycleDays,
    int periodDays,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      daysPast,
      locale: localeName,
      other: '$daysPast days past the estimate.',
      one: '1 day past the estimate.',
    );
    return '$_temp0 Cycle day $cycleDay of about $cycleDays days. Period usually runs about $periodDays days.';
  }

  @override
  String cycleWheelBleedDayHero(int day) {
    return 'Day $day';
  }

  @override
  String get cycleWheelBleedOfPeriod => 'of period';

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
  String cycleWheelSemanticsBleed(int day, int cycleDays, int periodDays) {
    return 'Day $day of period. Cycle of about $cycleDays days. Period usually runs about $periodDays days.';
  }

  @override
  String cycleWheelSemanticsMidCycle(
    int daysUntil,
    int cycleDay,
    int cycleDays,
    int periodDays,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      daysUntil,
      locale: localeName,
      other: 'About $daysUntil days until next period.',
      one: 'About 1 day until next period.',
    );
    return '$_temp0 Cycle day $cycleDay of about $cycleDays days. Period usually runs about $periodDays days.';
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
  String settingsRelockSubtitle(String duration) {
    return 'Locks the app after $duration without input. Backgrounding relocks immediately. A sign-in or unlock prompt this app opened is the one exception: the app stays covered while it is on screen, and relocks as soon as it closes if you have left.';
  }

  @override
  String get settingsRelockTimeoutTitle => 'Inactivity timeout';

  @override
  String get settingsRelockTimeout2Minutes => '2 minutes';

  @override
  String get settingsRelockTimeout15Minutes => '15 minutes';

  @override
  String get settingsRelockTimeout1Hour => '1 hour';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsAppearanceSubtitle =>
      'Follow your device\'s setting, or choose light or dark';

  @override
  String get appearanceOptionSystem => 'Follow system';

  @override
  String get appearanceOptionLight => 'Light';

  @override
  String get appearanceOptionDark => 'Dark';

  @override
  String get settingsHealthHeader => 'Health';

  @override
  String settingsHealthSyncTitle(String source) {
    return '$source sync';
  }

  @override
  String settingsHealthSyncSubtitle(String source) {
    return 'Choose which profile\'s data may sync to $source';
  }

  @override
  String get settingsHealthSyncSymptomsAndroidLimitation =>
      'Symptoms (cramps, headaches, mood, and more) can\'t be written to Health Connect — it has no symptom categories. Days logged with symptoms still sync their flow and spotting; the symptoms themselves stay in lunarlog.';

  @override
  String healthSyncPermissionGranted(String source) {
    return '$source access: granted';
  }

  @override
  String healthSyncPermissionNotAsked(String source) {
    return '$source access: not yet asked';
  }

  @override
  String healthSyncPermissionDenied(String source) {
    return '$source access: denied — open Settings to change';
  }

  @override
  String healthSyncPermissionUnavailable(String source) {
    return '$source access is not available on this device.';
  }

  @override
  String get healthSyncPermissionOpenSettings => 'Open Settings';

  @override
  String healthSyncImportUpdatedDays(int count, String source) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Updated $_temp0 from $source.';
  }

  @override
  String healthSyncImportAddedSpotting(int count, String source) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Added spotting to $_temp0 from $source.';
  }

  @override
  String healthSyncImportAlreadyMatched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0 already matched.';
  }

  @override
  String healthSyncImportKeptManual(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Kept your own logged value on $_temp0.';
  }

  @override
  String healthSyncImportPlacedDeviceZone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Dated $_temp0 using the time zone of this phone.';
  }

  @override
  String healthSyncImportSkippedNoZone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Skipped $_temp0 with no recorded time zone.';
  }

  @override
  String healthSyncImportSkippedUnsupported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return 'Skipped $_temp0 with no matching flow level.';
  }

  @override
  String healthSyncImportSummaryHeadline(int imported, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      imported,
      locale: localeName,
      other: '$imported days',
      one: '1 day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped already logged',
      one: '1 already logged',
    );
    return 'Imported $_temp0, skipped $_temp1.';
  }

  @override
  String healthSyncImportSummaryNothingNew(int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped days',
      one: '1 day',
    );
    return 'Nothing new — $_temp0 already logged.';
  }

  @override
  String get healthSyncImportTileSubtitle =>
      'Bring in all available menstrual flow and spotting.';

  @override
  String healthSyncImportProgress(int samples) {
    String _temp0 = intl.Intl.pluralLogic(
      samples,
      locale: localeName,
      other: '$samples samples',
      one: '1 sample',
    );
    return 'Importing… $_temp0 read so far.';
  }

  @override
  String get healthSyncFullHistoryNote =>
      'Imports everything the health store makes available, not a recent window. Background sync is not available yet.';

  @override
  String get healthSyncImportStoppedEarly =>
      'The import stopped early after an unusual amount of data. The days already read were kept — run the import again to continue.';

  @override
  String healthSyncUnbindDialogTitle(String name) {
    return 'Stop syncing $name to this phone?';
  }

  @override
  String healthSyncUnbindDialogWriteBody(String name, String source) {
    return 'This phone will stop writing data for $name to $source and stop importing from it. Nothing already logged in lunarlog, or already written to $source, is deleted.';
  }

  @override
  String healthSyncUnbindDialogImportBody(String name, String source) {
    return 'This phone will stop importing data for $name from $source. Nothing already logged is deleted.';
  }

  @override
  String get healthSyncUnbindConfirm => 'Stop syncing';

  @override
  String get healthSyncUnbindCancel => 'Cancel';

  @override
  String get settingsPrivacyTitle => 'Privacy policy';

  @override
  String get settingsPrivacySubtitle =>
      'How your family\'s data is stored, shared, and kept private';

  @override
  String get settingsPrivacyDialogTitle => 'lunarlog Privacy Policy';

  @override
  String get settingsPrivacyDialogBody =>
      'lunarlog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind your device\'s passcode or biometrics.\n• Works Offline: Logging, viewing, and estimates keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Minimum-Age Policy: Licensed for ages 13 and older; household profiles managed by adult guardians (18+).\n• Guardian Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md';

  @override
  String get settingsClose => 'Close';

  @override
  String get settingsSectionYourData => 'Your data';

  @override
  String get clinicalPdfExportTitle => 'Export clinical summary (PDF)';

  @override
  String get clinicalPdfExportForProfileTitle => 'Export clinical summary for';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsSectionReminders => 'Reminders';

  @override
  String get settingsSectionCalendar => 'Calendar';

  @override
  String get settingsSectionHomeWidget => 'Home-screen widget';

  @override
  String get settingsHomeWidgetProfileTitle => 'Widget profile';

  @override
  String get settingsHomeWidgetFollowActive =>
      'Follow the app\'s current profile';

  @override
  String get settingsHomeWidgetDisclosure =>
      'The widget shows only a discreet state: a cycle-day count, never a name, a date, or flow details. When the profile is one you can log for, tapping it records a period started today — the entry applies only after you unlock the app, and logging it twice changes nothing. Profiles you can only view are not offered here.';

  @override
  String get settingsSectionFamilySharing => 'Family & sharing';

  @override
  String get settingsSectionPrivacySecurity => 'Privacy & security';

  @override
  String get settingsSectionHelp => 'Help';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsReminderSettingsTitle => 'Reminder settings';

  @override
  String get settingsReminderSettingsSubtitle =>
      'Choose which reminders fire, when, and for whom';

  @override
  String get settingsCaregiverAlertsTitle => 'Guardian alerts';

  @override
  String get settingsFirstDayTitle => 'First day of week';

  @override
  String get settingsFirstDaySunday => 'Sunday';

  @override
  String get settingsFirstDayMonday => 'Monday';

  @override
  String get settingsDateFormatTitle => 'Date format';

  @override
  String settingsDateFormatSystemOption(String example) {
    return 'System default ($example)';
  }

  @override
  String get settingsDateFormatDayMonthOption => 'Day first (5 Sep)';

  @override
  String get settingsDateFormatMonthDayOption => 'Month first (Sep 5)';

  @override
  String get settingsHelpTitle => 'Help & explanations';

  @override
  String get settingsHelpSubtitle =>
      'Plain-language answers about estimates, logging, sync, and sharing — works offline';

  @override
  String get settingsAboutVersionTitle => 'Version';

  @override
  String settingsAboutVersion(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get settingsAboutVersionUnavailable => 'Not available';

  @override
  String get settingsAboutLicensesTitle => 'Open-source licences';

  @override
  String get settingsAboutLicensesSubtitle =>
      'The packages and terms this app builds on';

  @override
  String get firstRunValueHeadline => 'A private cycle log for your family';

  @override
  String get firstRunValueBody =>
      'Guardians can share a profile and log it together. Everything works offline. No ads, no data selling, no behavioral tracking — and estimates are never paywalled.';

  @override
  String get firstRunGuardiansTitle => 'Profiles and guardians';

  @override
  String get firstRunGuardiansBody =>
      'Each profile holds one person\'s cycle log. After signing in, you can invite another guardian — a co-parent or caregiver — to view or help log it.';

  @override
  String get firstRunMinorExplainerTitle => 'About the minor checkbox';

  @override
  String get firstRunMinorExplainerBody =>
      'It\'s a label used across the app to describe the profile. It doesn\'t restrict anything: health app sync is off for every profile by default and, when you turn it on, works the same way for any profile you choose — minors included. Wording and reminders come from the care mode picked on the next screen, not from this checkbox.';

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
      'A label used across the app — health sync works the same for every profile.';

  @override
  String get firstRunAgeAcknowledgementLabel =>
      'I am 13 or older, or a guardian managing a family profile';

  @override
  String get firstRunAgeAcknowledgementHint =>
      'lunarlog requires users to be at least 13 years old, or managed by a parent or legal guardian.';

  @override
  String get firstRunAgeAcknowledgementRequired =>
      'Please acknowledge the minimum-age policy to continue.';

  @override
  String get firstRunCareModeLabel => 'Care mode';

  @override
  String get firstRunContinue => 'Continue';

  @override
  String get firstRunRestore => 'Restore from backup or Clue export';

  @override
  String get firstRunCycleCaption =>
      'A few optional questions to set this profile up — every one can be skipped. The life-stage mode and birth-control answers can be changed later from Edit profile.';

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
      'Enter a number between 15 and 60';

  @override
  String get firstRunPeriodLengthRangeError =>
      'Enter a number between 1 and 14';

  @override
  String get firstRunCycleBirthControlLabel => 'Birth-control method';

  @override
  String get firstRunCycleGoalLabel => 'Life-stage mode';

  @override
  String get firstRunCreateButton => 'Create profile';

  @override
  String get firstRunWhoLabel => 'Who is this profile for?';

  @override
  String get firstRunWhoMe => 'Me';

  @override
  String get firstRunWhoSomeone => 'Someone I care for';

  @override
  String get firstRunWhoBoth => 'Both';

  @override
  String get firstRunRelationshipLabel => 'Relationship';

  @override
  String get firstRunTeenSuggestedHint =>
      'Teen mode is suggested for a minor — change it any time.';

  @override
  String get firstRunCycleShortCaption =>
      'Optional: if you know when her last period started, add it below. Not sure? Just continue.';

  @override
  String get firstRunWrapUpTitle => 'Add another person?';

  @override
  String get firstRunWrapUpBody =>
      'Everyone you set up now is ready to log. You can also add profiles later from the profile picker.';

  @override
  String get firstRunWrapUpAddAnother => 'Add another person';

  @override
  String get firstRunInviteTitle => 'Add another guardian?';

  @override
  String firstRunInviteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'A co-parent or caregiver can follow and log these profiles from their own phone.',
      one: 'A co-parent or caregiver can follow and log this profile from their own phone.',
    );
    return '$_temp0';
  }

  @override
  String get firstRunInviteWhyAccount =>
      'Invites are sent from your lunarlog account, so sign in first.';

  @override
  String get firstRunInviteSignInAction => 'Sign in to invite';

  @override
  String get firstRunInviteCoParent => 'Invite a guardian';

  @override
  String get firstRunInviteSkip => 'Skip for now';

  @override
  String get firstRunInviteDone => 'Done';

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
  String overviewPmsBandLabel(String range, int days, int length) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Estimated PMS: $range — usually starts about $days $_temp0 before your period and lasts about $length $_temp1.';
  }

  @override
  String overviewPmsTierLabel(String tier) {
    return 'PMS estimate: $tier';
  }

  @override
  String get predictionsSuppressedTitle => 'Estimates paused';

  @override
  String predictionsSuppressedBody(String method) {
    return 'Because $method typically stops or irregularly affects periods, period estimates are paused while it is active. The method will resume ordinary estimates once it is switched or cleared.';
  }

  @override
  String predictionsSuppressedByModeBody(String mode) {
    return 'Because this profile is set to $mode mode, period estimates are paused — the ordinary cycle averages this app estimates from don\'t apply right now. Switch back to Period Tracking mode from Edit profile to resume ordinary estimates.';
  }

  @override
  String get predictionsDisabledTitle => 'Estimates off';

  @override
  String get predictionsDisabledBody =>
      'Estimates, calendar estimate bands, and estimate reminders are paused for this profile. Your cycle history and tracking continue unchanged.';

  @override
  String get predictionsDisabledAction => 'Manage in Settings';

  @override
  String get settingsPredictionsTitle => 'Show estimates';

  @override
  String settingsPredictionsProfileTitle(String profileName) {
    return 'Show estimates ($profileName)';
  }

  @override
  String get settingsPredictionsSubtitle =>
      'Show cycle estimates, fertile window, and estimate reminders';

  @override
  String settingsPredictionsSuppressedByModeSubtitle(String mode) {
    return 'Turned off by $mode mode — change the life-stage mode to resume.';
  }

  @override
  String settingsPredictionsSuppressedByMethodSubtitle(String method) {
    return 'Turned off by $method — change or clear the birth-control method to resume.';
  }

  @override
  String get overviewIrregularSuggestionTitle => 'Cycles vary a lot';

  @override
  String get overviewIrregularSuggestionBody =>
      'Estimates may be less useful when cycles vary widely. You can turn off cycle estimates while continuing to track normally.';

  @override
  String get overviewIrregularSuggestionSettings => 'Manage in Settings';

  @override
  String get overviewIrregularSuggestionDismiss => 'Dismiss';

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
      'A heads-up before the estimated period starts';

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
      'A heads-up before the estimated fertile window';

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
  String get reminderLeadDaysBeforeStart => 'Days before estimated start';

  @override
  String get reminderLeadDaysBeforePms => 'Days before estimated PMS window';

  @override
  String get reminderLeadDaysBeforeFertileWindow =>
      'Days before estimated fertile window';

  @override
  String get reminderBirthControlTitle => 'Birth-control reminders';

  @override
  String get reminderBirthControlFollowsMethod =>
      'Follows the birth-control method recorded in this profile\'s settings.';

  @override
  String get reminderKindBirthControlPill => 'Pill reminder';

  @override
  String get reminderKindBirthControlPillSubtitle =>
      'Daily, at the chosen time';

  @override
  String get reminderKindBirthControlPatch => 'Patch reminder';

  @override
  String get reminderKindBirthControlPatchSubtitle => 'Weekly, on change day';

  @override
  String get reminderKindBirthControlRing => 'Ring reminder';

  @override
  String get reminderKindBirthControlRingSubtitle => 'Monthly, on change day';

  @override
  String get reminderKindBirthControlShot => 'Injection reminder';

  @override
  String get reminderKindBirthControlShotSubtitle => 'Every 12 weeks';

  @override
  String get reminderBirthControlNeedsStartDate =>
      'Waits for a start date on the recorded method — re-record the method from Edit profile to set one';

  @override
  String get commonNetworkError =>
      'Network error. Please check your connection.';

  @override
  String get commonServerUnreachable =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get commonUnauthorized =>
      'You do not have permission for this action.';

  @override
  String get commonSomethingWentWrong =>
      'Something went wrong. Please try again.';

  @override
  String get sharingFailureNotFound => 'Invitation not found or invalid link.';

  @override
  String get sharingFailureExpired => 'This invitation has expired.';

  @override
  String get sharingFailureAlreadyAccepted =>
      'This invitation was already accepted.';

  @override
  String get sharingFailureAlreadyGuardian =>
      'You are already an active guardian for this child.';

  @override
  String get sharingFailureInvalidToken => 'Invalid invitation link.';

  @override
  String get sharingFailureNotSignedIn =>
      'Sign in to your account to manage sharing.';

  @override
  String get sharingNeedsAccount =>
      'Sharing needs an account. Sign in to invite a guardian.';

  @override
  String get sharingSignInAction => 'Sign in';

  @override
  String get sharingFailureOther =>
      'Failed to accept invitation. Please try again.';

  @override
  String get profileErasureFailureNetwork =>
      'Can\'t remove imported data while offline. Check your connection and try again.';

  @override
  String get profileErasureFailureUnauthorized =>
      'Only that profile\'s primary guardian can remove its imported data.';

  @override
  String get profileErasureFailureNotSignedIn =>
      'Sign in to your account to remove imported data.';

  @override
  String get profileErasureFailureInvalidSource =>
      'That import source isn\'t supported. Nothing was removed.';

  @override
  String get profileErasureFailureOther =>
      'Couldn\'t remove the imported data. Try again.';

  @override
  String get purgeImportedDataNoRows =>
      'This profile has no imported data from a supported source.';

  @override
  String purgeImportedDataPreview(int count, String source) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0 from $source';
  }

  @override
  String importEntryDatesRejectedPreview(int count, String reasons) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count day entries fall',
      one: '1 day entry falls',
    );
    return '$_temp0 outside this profile\'s date range and will be skipped when you import ($reasons).';
  }

  @override
  String importEntryDatesRejectedResult(int count, String reasons) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count day entries',
      one: '1 day entry',
    );
    return '$_temp0 skipped by date ($reasons)';
  }

  @override
  String importEntryDatesRejectionFuture(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more than a day in the future',
      one: '1 more than a day in the future',
    );
    return '$_temp0';
  }

  @override
  String importEntryDatesRejectionBeforeBirthYear(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count before the birth year',
      one: '1 before the birth year',
    );
    return '$_temp0';
  }

  @override
  String importEntryDatesRejectionReasonsJoin(String first, String second) {
    return '$first and $second';
  }

  @override
  String get inviteCancellationRevoked => 'Invitation cancelled';

  @override
  String get inviteCancellationAlreadyAccepted =>
      'That invitation was already accepted';

  @override
  String get inviteCancellationAlreadyRevoked =>
      'That invitation was already cancelled';

  @override
  String get inviteCancellationExpired => 'That invitation had already expired';

  @override
  String get transferFailureNotFound => 'Transfer not found or invalid link.';

  @override
  String get transferFailureExpired => 'This transfer link has expired.';

  @override
  String get transferFailureCancelled => 'This transfer was cancelled.';

  @override
  String get transferFailureAlreadyAccepted =>
      'This transfer was already accepted.';

  @override
  String get transferFailureSelfTransfer =>
      'You can\'t claim a transfer you created yourself.';

  @override
  String get transferFailureStaleOwner =>
      'Your role on this profile has changed, so this transfer is no longer valid.';

  @override
  String get transferFailureAlreadyArmed =>
      'A transfer is already pending for this profile. Cancel it before starting a new one.';

  @override
  String get transferFailureInvalidToken => 'Invalid transfer link.';

  @override
  String get predictionConnectionFailureNotFound => 'That code is not valid.';

  @override
  String get predictionConnectionFailureExpired => 'That code has expired.';

  @override
  String get predictionConnectionFailureAlreadyAccepted =>
      'That code was already used.';

  @override
  String get predictionConnectionFailureAlreadyGuardian =>
      'You already have full guardian access to this profile.';

  @override
  String get predictionConnectionFailureInvalidToken =>
      'Invalid connection code.';

  @override
  String get predictionConnectionFailurePregnancyMode =>
      'Prediction sharing is unavailable while this profile is in Pregnancy mode.';

  @override
  String get predictionConnectionFailureAlreadyConnected =>
      'This profile already has a prediction connection. Revoke it before sharing with someone else.';

  @override
  String get predictionConnectionFailureOneDirectional =>
      'You cannot share and view predictions with the same person at the same time.';

  @override
  String get predictionConnectionFailureMinorProfile =>
      'Prediction sharing is not available for a minor\'s profile.';

  @override
  String get feedbackFailureRateLimited =>
      'You\'ve sent a few reports already — please try again in a bit.';

  @override
  String get feedbackFailureInvalidInput => 'Check your message and try again.';

  @override
  String get feedbackFailureAttachmentTooLarge =>
      'That image is too large. Choose one under 5 MB.';

  @override
  String get feedbackFailureAttachmentRejected =>
      'That file type is not supported. Choose a PNG, JPEG, or WebP image.';

  @override
  String get feedbackFailureNotFound => 'That ticket could not be found.';

  @override
  String feedbackFailureAttachmentUploadFailed(String attachmentReason) {
    return 'Your message was sent — no need to resend it. The attachment did not upload ($attachmentReason) You can find your ticket in Support history.';
  }

  @override
  String get notificationPreferencesFailureInvalidTimeZone =>
      'Your device\'s time zone isn\'t recognised by the server yet — quiet hours will use UTC until it is';

  @override
  String get notificationPreferencesFailureOther =>
      'Failed to save notification preferences. Please try again.';

  @override
  String get guardianRoleLabelPrimaryGuardian => 'Primary Guardian';

  @override
  String get guardianRoleLabelCoParent => 'Co-Parent';

  @override
  String get guardianRoleLabelCaregiver => 'Caregiver';

  @override
  String get guardianRoleLabelViewer => 'Viewer';

  @override
  String get guardianRoleReadOnlyReasonViewer =>
      'You have view-only access to this profile.';

  @override
  String get activityActorYou => 'you';

  @override
  String get activityActorGuardianFallback => 'a guardian';

  @override
  String profilePickerSharedRoleSubtitle(String role) {
    return 'Shared with me · $role';
  }

  @override
  String get authFailureWrongPassword =>
      'That email and password combination was not accepted.';

  @override
  String authFailureWeakPassword(int minLength) {
    return 'Choose a stronger password of at least $minLength characters.';
  }

  @override
  String get authFailureProviderUnavailable =>
      'That sign-in method isn\'t available on this device. Use email instead.';

  @override
  String get authFailureRateLimited =>
      'Too many attempts. Wait a little while, then try again.';

  @override
  String get authFailureMisconfigured =>
      'That sign-in method is not set up for this app right now. Try another way to sign in.';

  @override
  String get authFailureExpiredLink =>
      'That sign-in link is no longer valid. Request a new one.';

  @override
  String get authFailureInvalidCode =>
      'That code was not accepted. Check it or request a new email.';

  @override
  String get authFailureIdentityTaken =>
      'That sign-in method already belongs to another account.';

  @override
  String get authFailureSignUpClosed =>
      'New accounts are created by invitation. Ask the person who set up your family\'s lunarlog to invite you.';

  @override
  String get authFailureLastSignInMethod =>
      'That is the only way left to sign in to this account. Add another method first.';

  @override
  String get careNotesRemoveNoteTooltip => 'Remove note';

  @override
  String get careNotesRemoveItemTooltip => 'Remove item';

  @override
  String get careNotesButtonTooltip => 'Care notes & visit prep';

  @override
  String get activityFeedTooltip => 'Activity';

  @override
  String get activityFeedLoadError => 'Could not load the activity feed.';

  @override
  String get manageGuardiansCancelInviteTooltip => 'Cancel invitation';

  @override
  String get manageGuardiansAboutRolesTooltip => 'About roles';

  @override
  String get manageGuardiansTransferOwnershipTooltip => 'Transfer ownership';

  @override
  String get manageGuardiansNotificationsTooltip => 'Notifications';

  @override
  String get manageGuardiansEndSharingTooltip => 'End prediction sharing';

  @override
  String get manageGuardiansChangeRoleTooltip => 'Change role';

  @override
  String get manageGuardiansLeaveProfileTooltip => 'Leave profile';

  @override
  String get manageGuardiansRemoveCaregiverTooltip => 'Remove guardian';

  @override
  String get feedbackRemoveAttachmentTooltip => 'Remove attachment';

  @override
  String get predictionCalendarRefreshTooltip => 'Refresh';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get profilePickerAddProfileTooltip => 'Add profile';

  @override
  String get profilePickerUnarchiveTooltip => 'Unarchive';

  @override
  String get profilePickerActionsTooltip => 'Profile actions';

  @override
  String get editProfileAction => 'Edit profile';

  @override
  String get profilePickerSharedWithMeTooltip => 'Shared with me';

  @override
  String get profileDetailSwitchProfileTooltip => 'Switch profile';

  @override
  String get appShellProfileSwitcherTooltip => 'Switch profile';

  @override
  String get quickSwitcherManageProfiles => 'Manage profiles…';

  @override
  String get profileStatusNoHistory => 'No history yet';

  @override
  String get profileStatusPredictionsSuppressed => 'Period estimates paused';

  @override
  String get profileStatusPredictionsOff => 'Period estimates off';

  @override
  String get profileStatusNoRecentPeriod => 'No recent period logged';

  @override
  String daysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$count $_temp0';
  }

  @override
  String daysValue(num count, String value) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$value days',
      one: '$value day',
    );
    return '$_temp0';
  }

  @override
  String get daySheetMeasurementsHeading => 'Measurements';

  @override
  String daySheetBbtFieldLabel(String unit) {
    return 'BBT ($unit)';
  }

  @override
  String daySheetWeightFieldLabel(String unit) {
    return 'Weight ($unit)';
  }

  @override
  String daySheetBbtRangeError(String min, String max) {
    return 'Enter a BBT between $min and $max';
  }

  @override
  String daySheetWeightRangeError(String min, String max) {
    return 'Enter a weight between $min and $max';
  }

  @override
  String get daySheetMeasurementInvalidNumber => 'Enter a number';

  @override
  String get daySheetMeasurementExcludeLabel => 'Exclude from charts';

  @override
  String get daySheetMeasurementIncludeLabel => 'Include in charts';

  @override
  String get daySheetBbtGroup => 'BBT';

  @override
  String get daySheetWeightGroup => 'Weight';

  @override
  String get settingsMeasurementUnitsTitle => 'Measurement units';

  @override
  String settingsMeasurementUnitsProfileTitle(String profileName) {
    return 'Measurement units ($profileName)';
  }

  @override
  String get settingsMeasurementUnitsBbtLabel => 'BBT unit';

  @override
  String get settingsMeasurementUnitsWeightLabel => 'Weight unit';

  @override
  String get mfaSectionTitle => 'Two-factor authentication';

  @override
  String get mfaEnrollTileTitle => 'Set up two-factor authentication';

  @override
  String get mfaEnrollTileSubtitle =>
      'Add an authenticator app as a second sign-in factor.';

  @override
  String get mfaFactorTileTitle => 'Authenticator app';

  @override
  String get mfaFactorTileSubtitleVerified => 'Enabled';

  @override
  String get mfaFactorTileSubtitlePending =>
      'Setup not finished — remove and try again';

  @override
  String get mfaRemoveFactorTitle => 'Remove two-factor authentication?';

  @override
  String get mfaRemoveFactorBody =>
      'You will only need your password to sign in and to confirm account actions.';

  @override
  String get mfaRemoveFactorConfirm => 'Remove';

  @override
  String get mfaErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get mfaEnrollScreenTitle => 'Set up two-factor authentication';

  @override
  String get mfaEnrollInstructions =>
      'Add this setup key to your authenticator app (Google Authenticator, 1Password, Authy, and similar apps all accept manual entry).';

  @override
  String get mfaEnrollSecretLabel => 'Setup key';

  @override
  String get mfaEnrollCodeLabel => 'Enter the 6-digit code from your app';

  @override
  String get mfaCodeHint => '6-digit code';

  @override
  String get mfaEnrollConfirmButton => 'Confirm';

  @override
  String get mfaEnrollSuccessMessage => 'Two-factor authentication is on.';

  @override
  String get mfaStepUpTitle => 'Confirm it\'s you';

  @override
  String get mfaStepUpBody =>
      'Enter the 6-digit code from your authenticator app to continue.';

  @override
  String get mfaStepUpConfirmButton => 'Verify';

  @override
  String get pinSettingsSectionTitle => 'App PIN';

  @override
  String get pinSettingsToggleTitle => 'Require a PIN to open lunarlog';

  @override
  String get pinSettingsToggleSubtitleOn =>
      'On — an additional lock layer on top of your device credential.';

  @override
  String get pinSettingsToggleSubtitleOff => 'Off';

  @override
  String get pinSetScreenTitle => 'Set a PIN';

  @override
  String get pinChangeScreenTitle => 'Change PIN';

  @override
  String get pinCurrentPinLabel => 'Current PIN';

  @override
  String get pinNewPinLabel => 'New PIN (4-8 digits)';

  @override
  String get pinConfirmPinLabel => 'Confirm PIN';

  @override
  String get pinMismatchError => 'PINs don\'t match.';

  @override
  String get pinTooShortError => 'Enter at least 4 digits.';

  @override
  String get pinWrongCurrentError => 'That PIN is incorrect.';

  @override
  String get pinSaveButton => 'Save';

  @override
  String get pinRemoveConfirmTitle => 'Turn off PIN?';

  @override
  String get pinRemoveConfirmBody =>
      'You can still use your device credential to unlock lunarlog.';

  @override
  String get pinRemoveConfirmButton => 'Turn off';

  @override
  String get pinLockScreenPrompt => 'Enter your PIN';

  @override
  String get pinLockScreenUnlockButton => 'Unlock';

  @override
  String pinLockScreenIncorrect(int count) {
    return 'Wrong PIN. $count attempt(s) remaining before a short lockout.';
  }

  @override
  String pinLockScreenLockedOut(String time) {
    return 'Too many attempts. Try again after $time.';
  }

  @override
  String get reminderTextTileTitle => 'Notification text';

  @override
  String get reminderTextTileDefaultSubtitle => 'Using the default text';

  @override
  String get reminderTextEditorAppBarTitle => 'Notification text';

  @override
  String get reminderTextPreviewSection => 'Preview';

  @override
  String get reminderTextPreviewAppName => 'lunarlog';

  @override
  String get reminderTextPreviewNow => 'now';

  @override
  String get reminderTextTitleLabel => 'Title';

  @override
  String get reminderTextBodyLabel => 'Body';

  @override
  String get reminderTextSaveButton => 'Save';

  @override
  String get reminderTextResetButton => 'Reset to default';

  @override
  String get reminderTextDiscretionNote =>
      'The preview is exactly what the notification will show — nothing more. lunarlog never adds a profile name, date, or health detail to notification text. Anything you type here appears on the lock screen, so keep it something anyone may see.';

  @override
  String pregnancyWeekTitle(int week) {
    return 'Week $week of pregnancy';
  }

  @override
  String pregnancyDueOn(String date) {
    return 'Estimated due date: $date';
  }

  @override
  String get pregnancyDueDateMissing =>
      'No due date yet. Add one from Edit profile.';

  @override
  String get pregnancyDueDateLabel => 'Estimated due date';

  @override
  String get pregnancyDueDateDerivedHint =>
      'Derived from the last recorded period start (280 days). Tap the date to change it.';

  @override
  String get pregnancyDueDateManualHint =>
      'Pick the estimated due date — the last period start is unknown.';

  @override
  String get pregnancyExitExclusionTitle =>
      'Exclude this pregnancy from cycle averages?';

  @override
  String get pregnancyExitExclusionBody =>
      'Cycles logged during the pregnancy can distort the averages future estimates use. Excluding them keeps the cycle history intact — the pregnancy span is just left out of the math. Individual cycles can also be excluded later from cycle history.';

  @override
  String get pregnancyExitExclusionAccept => 'Exclude pregnancy';

  @override
  String get pregnancyExitExclusionDecline => 'Keep in averages';

  @override
  String get pregnancyExitExclusionDone =>
      'Pregnancy excluded from cycle averages';

  @override
  String postpartumDayTitle(int days) {
    return 'Day $days of postpartum';
  }

  @override
  String postpartumDaySinceBirth(int days) {
    return 'Day $days since birth';
  }

  @override
  String get postpartumBirthDateLabel => 'Birth date';

  @override
  String get postpartumBirthDateHint =>
      'Optional. Pick the date to count from, or leave it blank to count from today.';

  @override
  String get postpartumStartMissing =>
      'Postpartum mode is on. The start date wasn\'t recorded, so there\'s no day count yet.';

  @override
  String get postpartumReturnTitle => 'Cycles have returned?';

  @override
  String get postpartumReturnBody =>
      'You logged a period during Postpartum mode. Switching to Period Tracking resumes ordinary estimates and lets the app start rebuilding cycle averages from your new cycles.';

  @override
  String get postpartumReturnAction => 'Switch to Period Tracking';

  @override
  String get postpartumExitExclusionTitle =>
      'Exclude this postpartum interval from cycle averages?';

  @override
  String get postpartumExitExclusionBody =>
      'Bleeding logged during the postpartum interval can distort the averages future estimates use. Excluding it keeps your cycle history intact — the postpartum span is just left out of the math. You can also exclude individual cycles later from cycle history.';

  @override
  String get postpartumExitExclusionAccept => 'Exclude postpartum interval';

  @override
  String get postpartumExitExclusionDecline => 'Keep in averages';

  @override
  String get postpartumExitExclusionDone =>
      'Postpartum interval excluded from cycle averages';

  @override
  String get conceiveTitle => 'Conceive mode';

  @override
  String get conceiveWindowLabel => 'Estimated fertile window';

  @override
  String conceivePeakDay(String date, int percent) {
    return 'Most likely day: $date (about $percent% of cycles in the study behind this estimate)';
  }

  @override
  String get perimenopauseTitle => 'Cycle changes';

  @override
  String get perimenopauseBody =>
      'In perimenopause, cycle lengths vary from one to the next. Comparing each cycle with the one before it is how change shows up — not a count of days late.';

  @override
  String get perimenopauseNotEnoughTitle => 'Nothing to compare yet';

  @override
  String get perimenopauseNotEnoughBody =>
      'Keep logging — once a second cycle is recorded, this view compares them so you can spot changes. Irregular cycles are expected around perimenopause.';

  @override
  String perimenopauseLengthLonger(String days) {
    return 'The last completed cycle was $days longer than the one before it';
  }

  @override
  String perimenopauseLengthShorter(String days) {
    return 'The last completed cycle was $days shorter than the one before it';
  }

  @override
  String get perimenopauseLengthSame =>
      'The last completed cycle was the same length as the one before it';

  @override
  String get perimenopauseLengthUnknown =>
      'This cycle is still in progress — compare it once it ends';

  @override
  String perimenopauseBleedDays(String current, String previous) {
    return 'Bleeding days: $current in the newer cycle, $previous in the one before it';
  }

  @override
  String get perimenopauseCompareButton => 'Compare cycles';

  @override
  String get importCluePasswordPrompt =>
      'Clue emails a one-time password with the export. Enter it to open the file.';

  @override
  String get importClueExportPasswordLabel => 'Export password';

  @override
  String get importClueOpenExport => 'Open export';

  @override
  String get importClueNewProfileNote =>
      'A new profile will be created for this import.';

  @override
  String get importClueProfileNameLabel => 'Profile name';

  @override
  String get importClueCancel => 'Cancel';

  @override
  String get importClueImport => 'Import';

  @override
  String get importClueDone => 'Done';

  @override
  String get guardianNotesSectionTitle => 'Notes from guardians';

  @override
  String get guardianNotesEmpty => 'No guardian notes for this day yet.';

  @override
  String get guardianNotesYou => 'You';

  @override
  String get guardianNotesRemove => 'Remove';

  @override
  String get guardianNotesAdd => 'Add note';

  @override
  String get guardianNotesUpdate => 'Update note';

  @override
  String inviteSubjectOption(String name) {
    return 'Invite $name to log their own profile';
  }

  @override
  String inviteSubjectOptionDetail(String name) {
    return 'Caregiver access - this is $name\'s own profile, listed as theirs on their device';
  }

  @override
  String inviteCreatedShareGuardian(String profile) {
    return 'Share this single-use link with the guardian for $profile:';
  }

  @override
  String inviteCreatedShareSubject(String name) {
    return 'Share this single-use link with $name - they\'ll use it to join and log their own profile:';
  }

  @override
  String acceptInviteSubjectIntro(String profile) {
    return 'This is your profile. $profile\'s cycle calendar and health logs will sync to this device - the guardians already sharing it can see and log it too.';
  }

  @override
  String get profilePickerSubjectSubtitle => 'This is your profile';

  @override
  String get manageGuardiansSubjectBadge => '(her profile)';

  @override
  String get manageGuardiansPendingSubjectLabel => 'Her own profile';

  @override
  String subjectTeenModeDialogTitle(String name) {
    return 'Switch $name to Teen mode?';
  }

  @override
  String subjectTeenModeDialogBody(String name) {
    return '$name is logging her own profile now. Teen mode frames things for someone building body literacy for the first time - same data, same honesty. You can change it any time from Edit profile.';
  }

  @override
  String get subjectTeenModeDialogAccept => 'Switch to Teen';

  @override
  String get subjectTeenModeDialogDecline => 'Keep Standard';

  @override
  String get subjectTeenModeDoneSnack => 'Switched to Teen mode';

  @override
  String get profileIrregularFramingLabel => 'Irregular cycles';

  @override
  String get profileIrregularFramingHint =>
      'Treats variation as expected, not late: ranges instead of dates, no late banner, no late nudges. On by default for teen profiles until cycles are steady.';

  @override
  String cycleRecapTitle(int cycleNumber) {
    return 'Cycle $cycleNumber wrapped up';
  }

  @override
  String cycleRecapLength(String days) {
    return 'This cycle lasted $days.';
  }

  @override
  String cycleRecapUsualRange(String range) {
    return 'Your usual range is $range.';
  }

  @override
  String cycleRecapLongerThanPrevious(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days longer than the cycle before it.',
      one: 'One day longer than the cycle before it.',
    );
    return '$_temp0';
  }

  @override
  String cycleRecapShorterThanPrevious(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days shorter than the cycle before it.',
      one: 'One day shorter than the cycle before it.',
    );
    return '$_temp0';
  }

  @override
  String get cycleRecapSameAsPrevious =>
      'About the same length as the cycle before it.';

  @override
  String get cycleRecapEstimatesMoreConfident =>
      'Your estimates are now more confident.';

  @override
  String get cycleRecapEstimatesLessConfident =>
      'Your estimates are a little less certain now.';

  @override
  String cycleRecapAverageMoved(String days) {
    return 'Your average cycle length moved by $days.';
  }

  @override
  String cycleRecapRecurringSymptom(String symptom, String days) {
    return '$symptom: most often around cycle day $days.';
  }

  @override
  String cycleRecapCrampDays(String days) {
    return 'Cramps most often land around cycle day $days.';
  }

  @override
  String get cycleRecapStillLearning =>
      'Still learning — estimates appear once a few cycles are recorded.';

  @override
  String get cycleRecapCompareAction => 'Compare with the cycle before';

  @override
  String get cycleRecapDismissLabel => 'Dismiss';

  @override
  String get householdLogToday => 'Log today';

  @override
  String householdLogTodayFor(String name) {
    return 'Log today for $name';
  }

  @override
  String get householdTimingExpectedToday => 'Period expected today';

  @override
  String householdTimingExpectedIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Period expected in $_temp0';
  }

  @override
  String householdTimingPastEstimate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days past the estimate',
      one: '1 day past the estimate',
    );
    return '$_temp0';
  }

  @override
  String householdTimingLastLogged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return 'Last period $_temp0';
  }

  @override
  String householdSilence(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'Nothing logged for $_temp0';
  }

  @override
  String householdChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0 since you last looked';
  }

  @override
  String get accountReauthFailed => 'Couldn\'t confirm it\'s you — try again';

  @override
  String get healthDeviationCardTitle => 'Apple Health noticed…';

  @override
  String get healthDeviationCardSubtitle =>
      'These are Apple\'s own estimates from your Health data — separate from lunarlog\'s own estimate.';

  @override
  String get healthDeviationDismiss => 'Dismiss';

  @override
  String get healthDeviationKindIrregular => 'irregular cycles';

  @override
  String get healthDeviationKindInfrequent => 'infrequent cycles';

  @override
  String get healthDeviationKindProlonged => 'prolonged periods';

  @override
  String get healthDeviationKindPersistentIntermenstrualBleeding =>
      'bleeding between periods';

  @override
  String healthDeviationLine(String kind, String range) {
    return 'Possible $kind ($range)';
  }

  @override
  String healthDeviationRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String healthDeviationRangeSingle(String date) {
    return '$date';
  }

  @override
  String get accountDeleteDialogBody =>
      'This permanently deletes your account, everything stored in it, and the copy on this device. This cannot be undone.';

  @override
  String get accountDeleteTileSubtitle =>
      'Deletes the account, everything in it, and this device\'s copy.';

  @override
  String get accountSignOutEverywhereBody =>
      'Signs this account out on every device. Other devices may keep working for up to an hour. The copy on this device is removed; everything stays in your account.';

  @override
  String transferOwnershipConfirmBody(String name, String role) {
    return '$name will become the Primary Guardian of this profile. You\'ll keep access as $role, and they can remove that access at any time.';
  }

  @override
  String transferOwnershipBecomesGuardian(String name) {
    return '$name becomes this profile\'s Primary Guardian.';
  }

  @override
  String get transferOwnershipRoleCoParent =>
      'Co-Parent: keep logging entries and managing this profile.';

  @override
  String get transferOwnershipRoleViewer =>
      'Viewer: read-only access to their calendar and entries.';

  @override
  String manageGuardiansLeaveProfileDialogTitle(String profile) {
    return 'Leave $profile\'s profile?';
  }

  @override
  String get manageGuardiansLeaveProfileConfirm => 'Leave';

  @override
  String get manageGuardiansWaitingForRedemption =>
      'Waiting for them to open the link';

  @override
  String get healthSyncConfirmSyncAction => 'Sync';

  @override
  String get predictionEnterLinkTitle => 'Enter a connection link';

  @override
  String get predictionEnterLinkHint => 'Paste the link you received';

  @override
  String get predictionEnterLinkAction => 'Enter link';

  @override
  String get sharePredictionsCopyLink => 'Copy link';

  @override
  String get sharePredictionsLinkExpiry =>
      'The link expires in 72 hours and can be used once.';

  @override
  String get claimProfileBecomeGuardianAction => 'Become Primary Guardian';

  @override
  String get claimProfileBody =>
      'Claiming this link makes you this profile\'s Primary Guardian. The parent who shared it keeps the role they chose, and every past entry stays with whoever originally logged it.';

  @override
  String get sharingUnexpectedError => 'An unexpected error occurred.';

  @override
  String sharingAcceptInvitePreviewIntro(String profileName, String roleLabel) {
    return 'You\'ve been invited to join $profileName\'s shared profile as $roleLabel. Accepting will sync its cycle calendar and health logs to this device.';
  }

  @override
  String get sharingAcceptInviteNeutralIntro =>
      'You\'ve been invited to a shared profile in lunarlog. Accepting will sync its cycle calendar and health logs to this device.';

  @override
  String get sharingAcceptInvitePreviewLoading => 'Loading invite details…';

  @override
  String get sharingAcceptInvitePreviewError =>
      'Couldn\'t load invite details, but you can still continue.';

  @override
  String get sharingAcceptInvitePreviewUnavailable =>
      'This invite link may have expired or already been used.';

  @override
  String get sharingAcceptInviteTitle => 'Join Shared Profile';

  @override
  String get sharingAcceptInviteDecline => 'Decline';

  @override
  String get sharingAcceptInviteAccept => 'Accept & Sync';

  @override
  String get sharingAcceptInviteNameLabel =>
      'Your display name (e.g. Dad, Mom, Grandma)';

  @override
  String get sharingAcceptInviteNameHint => 'Shows when you log entries';

  @override
  String get sharingAcceptPredictionTitle => 'Connect to cycle predictions';

  @override
  String get sharingAcceptPredictionBody =>
      'Accepting adds a read-only calendar of their estimated period, fertile, ovulation, and PMS days. No notes, tags, or logs are ever shared or synced to this device.';

  @override
  String get sharingAcceptPredictionDecline => 'Decline';

  @override
  String get sharingAcceptPredictionConnect => 'Connect';

  @override
  String get sharingClaimProfileTitle => 'Become the Owner';

  @override
  String get sharingClaimProfileDecline => 'Decline';

  @override
  String get sharingClaimProfileChildNameLabel =>
      'Child\'s display name (optional)';

  @override
  String get sharingClaimProfileChildNameHint => 'Shows on the profile';

  @override
  String get sharingClaimProfileParentLabelLabel =>
      'Label for the parent (optional)';

  @override
  String get sharingClaimProfileParentLabelHint =>
      'Shows when they log entries';

  @override
  String get sharingInviteGuardianGenerateFailed =>
      'Failed to generate invite. Please check your connection and try again.';

  @override
  String get sharingInviteGuardianRoleLabel => 'Role:';

  @override
  String get sharingInviteGuardianPresetCoParent =>
      'Co-Parent (Can log, edit profile & invite)';

  @override
  String get sharingInviteGuardianPresetCaregiver =>
      'Caregiver (Can log symptoms & periods)';

  @override
  String get sharingInviteGuardianPresetViewer => 'Viewer (Read-only access)';

  @override
  String get sharingInviteGuardianCreatedTitle => 'Invitation Created';

  @override
  String get sharingInviteGuardianExpiry =>
      'Expires in 48 hours. Can be redeemed once.';

  @override
  String get sharingInviteGuardianCopied => 'Copied to clipboard';

  @override
  String get sharingInviteGuardianDone => 'Done';

  @override
  String get sharingInviteGuardianCopyLink => 'Copy Link';

  @override
  String get sharingInviteGuardianShare => 'Share';

  @override
  String sharingInviteGuardianTitle(String profileName) {
    return 'Invite guardian to $profileName';
  }

  @override
  String get sharingInviteGuardianNicknameLabel =>
      'Nickname / Label (Optional)';

  @override
  String get sharingInviteGuardianNicknameHint =>
      'e.g. Dad, Grandma, School Nurse';

  @override
  String get sharingInviteGuardianHelpLabel => 'How do invitations work?';

  @override
  String get sharingInviteGuardianCancel => 'Cancel';

  @override
  String get sharingInviteGuardianCreateLink => 'Create Link';

  @override
  String get sharingManageGuardiansCancel => 'Cancel';

  @override
  String get sharingManageGuardiansEndPredictionTitle =>
      'End prediction sharing?';

  @override
  String get sharingManageGuardiansEndPredictionBody =>
      'They will immediately lose the shared predictions calendar. You can create a new connection any time.';

  @override
  String get sharingManageGuardiansEndSharing => 'End sharing';

  @override
  String get sharingManageGuardiansPredictionSharingEnded =>
      'Prediction sharing ended';

  @override
  String get sharingManageGuardiansEndSharingFailed =>
      'Failed to end sharing. Check connection.';

  @override
  String sharingManageGuardiansDeleteProfileTitle(String profileName) {
    return 'Delete $profileName permanently?';
  }

  @override
  String get sharingManageGuardiansDeleteProfileStep1Body =>
      'This permanently erases every day entry, care note, and visit-prep item on this profile, and removes every guardian\'s access to it — including your own. Synced copies on every device are erased too.';

  @override
  String get sharingManageGuardiansContinue => 'Continue';

  @override
  String get sharingManageGuardiansDeleteProfileStep2Title =>
      'Are you absolutely sure?';

  @override
  String sharingManageGuardiansDeleteProfileStep2Body(String profileName) {
    return '$profileName\'s history will be gone permanently, for every guardian on this profile. There is no undo.';
  }

  @override
  String get sharingManageGuardiansDeletePermanently => 'Delete permanently';

  @override
  String get sharingManageGuardiansDeleteOffline =>
      'Can\'t delete while offline. Check your connection and try again.';

  @override
  String get sharingManageGuardiansDeleteFailed =>
      'Failed to delete profile. Check connection and try again.';

  @override
  String get sharingManageGuardiansSolePrimaryLeave =>
      'You\'re now the only primary guardian, so you can\'t leave. Add another primary guardian first, then try again.';

  @override
  String get sharingManageGuardiansRemoveFailed =>
      'Failed to remove guardian. Check connection.';

  @override
  String sharingManageGuardiansRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get sharingManageGuardiansLeaveBody =>
      'You will leave this profile and no longer receive updates or sync its entries.';

  @override
  String sharingManageGuardiansRemoveBody(String profileName) {
    return 'This guardian will lose access to $profileName\'s calendar and entries.';
  }

  @override
  String get sharingManageGuardiansRemove => 'Remove';

  @override
  String sharingManageGuardiansRemoved(String name) {
    return 'Removed $name';
  }

  @override
  String sharingManageGuardiansCancelInviteTitle(String name) {
    return 'Cancel invitation for $name?';
  }

  @override
  String get sharingManageGuardiansCancelInviteBody =>
      'The invite link will stop working immediately. You can send a new one any time.';

  @override
  String get sharingManageGuardiansKeepInvitation => 'Keep Invitation';

  @override
  String get sharingManageGuardiansCancelInvitation => 'Cancel Invitation';

  @override
  String get sharingManageGuardiansCancelInviteFailed =>
      'Failed to cancel invitation. Check connection.';

  @override
  String get sharingManageGuardiansPendingLoadError =>
      'Could not load pending invitations.';

  @override
  String get sharingManageGuardiansNoPending => 'No pending invitations';

  @override
  String get sharingManageGuardiansPendingTitle => 'Pending invitations';

  @override
  String sharingManageGuardiansPendingSubtitleExpired(String kindLabel) {
    return '$kindLabel • Expired';
  }

  @override
  String sharingManageGuardiansPendingSubtitle(
    String kindLabel,
    String expiry,
  ) {
    return '$kindLabel • $expiry';
  }

  @override
  String get sharingManageGuardiansResend => 'Resend';

  @override
  String get sharingManageGuardiansExpiryExpired => 'expired';

  @override
  String sharingManageGuardiansExpiryHours(int hours) {
    return 'expires in ${hours}h';
  }

  @override
  String sharingManageGuardiansExpiryMinutes(int minutes) {
    return 'expires in ${minutes}m';
  }

  @override
  String sharingManageGuardiansScreenTitle(String profileName) {
    return '$profileName Guardians';
  }

  @override
  String get sharingManageGuardiansInviteAction => 'Invite guardian';

  @override
  String get sharingManageGuardiansNoGuardiansTitle =>
      'No guardians linked yet';

  @override
  String get sharingManageGuardiansNoGuardiansBody =>
      'Invite another guardian to sync and share tracking.';

  @override
  String get sharingManageGuardiansPredictionsSectionTitle =>
      'Predictions-only sharing';

  @override
  String get sharingManageGuardiansPredictionsSectionBody =>
      'Shares estimated period, fertile, ovulation, and PMS days on a read-only calendar - never notes or logs. One connection.';

  @override
  String get sharingManageGuardiansPredictionsMinor =>
      'Prediction sharing is not available for a minor\'s profile.';

  @override
  String get sharingManageGuardiansSharePredictionsAction =>
      'Share predictions only...';

  @override
  String get sharingManageGuardiansPredictionsPrimaryOnly =>
      'Only the primary guardian can share predictions.';

  @override
  String get sharingManageGuardiansSharingPredictions => 'Sharing predictions';

  @override
  String get sharingManageGuardiansPendingBadge => 'pending';

  @override
  String get sharingManageGuardiansPhasesOnlyCalendar =>
      'Phases-only calendar • not a guardian';

  @override
  String get sharingManageGuardiansDangerZoneTitle => 'Danger zone';

  @override
  String get sharingManageGuardiansDangerZoneBody =>
      'Permanently erases this profile and everything logged on it, for every guardian. This cannot be undone.';

  @override
  String get sharingManageGuardiansDeleteProfileAction =>
      'Delete profile permanently';

  @override
  String get sharingManageGuardiansRoleUpdateFailed =>
      'Failed to update role. Check connection.';

  @override
  String sharingManageGuardiansChangeRoleTitle(String newRoleLabel) {
    return 'Change role to $newRoleLabel?';
  }

  @override
  String sharingManageGuardiansChangeRoleBody(
    String name,
    String currentRoleLabel,
    String consequence,
  ) {
    return '$name currently has $currentRoleLabel access. $consequence No new invitation is needed — the new role applies on their next sync.';
  }

  @override
  String get sharingManageGuardiansChangeRoleAction => 'Change role';

  @override
  String sharingManageGuardiansRoleUpdated(String newRoleLabel) {
    return 'Role updated to $newRoleLabel';
  }

  @override
  String get sharingManageGuardiansYouSuffix => '(you)';

  @override
  String get sharingNotificationPreferencesTitle => 'Notifications';

  @override
  String get sharingNotificationPreferencesSaveWithoutTzTitle =>
      'Save without time zone?';

  @override
  String get sharingNotificationPreferencesSaveWithoutTzBody =>
      'Your quiet hours will not adjust for your local time zone until this is resolved. Continue anyway?';

  @override
  String get sharingNotificationPreferencesCancel => 'Cancel';

  @override
  String get sharingNotificationPreferencesSaveWithoutTz =>
      'Save without time zone';

  @override
  String get sharingNotificationPreferencesLogDeliveryTitle =>
      'Log alert delivery';

  @override
  String get sharingNotificationPreferencesLogDeliverySubtitle =>
      'Immediate, once a day, or off - extra alerts never exceed a daily limit and roll into the digest';

  @override
  String get sharingNotificationPreferencesCycleStartDelivery =>
      'Cycle-start alert delivery';

  @override
  String get sharingNotificationPreferencesHighSeverityDelivery =>
      'High-severity alert delivery';

  @override
  String get sharingNotificationPreferencesDigestTimeTitle => 'Digest time';

  @override
  String get sharingNotificationPreferencesDigestTimeSubtitle =>
      'When daily digests are delivered in your time zone';

  @override
  String get sharingNotificationPreferencesLoadError =>
      'Could not load your notification settings.';

  @override
  String get sharingNotificationPreferencesDiscretion =>
      'Alerts never show what was logged - just a generic reminder to open lunarlog.';

  @override
  String sharingNotificationPreferencesNotifyOnLog(String profileName) {
    return 'Notify me when $profileName logs an entry';
  }

  @override
  String get sharingNotificationPreferencesCycleStartOnly =>
      'Only notify on cycle start';

  @override
  String get sharingNotificationPreferencesHighSeverity =>
      'Notify on high-severity days';

  @override
  String get sharingNotificationPreferencesMissedEntryTitle =>
      'Missed-entry reminder';

  @override
  String get sharingNotificationPreferencesMissedEntrySubtitle =>
      'Check in when no entry has been logged for a while';

  @override
  String get sharingNotificationPreferencesOff => 'Off';

  @override
  String get sharingNotificationPreferencesOneDay => '1 day';

  @override
  String get sharingNotificationPreferencesTwoDays => '2 days';

  @override
  String get sharingNotificationPreferencesThreeDays => '3 days';

  @override
  String get sharingNotificationPreferencesQuietStart => 'Quiet hours start';

  @override
  String get sharingNotificationPreferencesQuietEnd => 'Quiet hours end';

  @override
  String get sharingNotificationPreferencesClearQuietHours =>
      'Clear quiet hours';

  @override
  String get sharingPredictionConnectionsTitle => 'Shared with me';

  @override
  String get sharingPredictionConnectionsStopTitle =>
      'Stop receiving these predictions?';

  @override
  String get sharingPredictionConnectionsStopBody =>
      'You will stop seeing this profile\'s shared cycle calendar. The sharer can invite you again at any time.';

  @override
  String get sharingPredictionConnectionsCancel => 'Cancel';

  @override
  String get sharingPredictionConnectionsStopAction => 'Stop receiving';

  @override
  String get sharingPredictionConnectionsStopped =>
      'Stopped receiving predictions';

  @override
  String get sharingPredictionConnectionsStopFailed =>
      'Could not stop receiving. Check connection.';

  @override
  String get sharingPredictionConnectionsFailed => 'Connection failed.';

  @override
  String get sharingPredictionConnectionsLoadError =>
      'Could not load connections.';

  @override
  String get sharingPredictionConnectionsEmptyTitle =>
      'No shared predictions yet';

  @override
  String get sharingPredictionConnectionsEmptyBody =>
      'When someone shares their cycle predictions with you, their calendar appears here.';

  @override
  String get sharingPredictionConnectionsCyclePredictions =>
      'Cycle predictions';

  @override
  String sharingPredictionConnectionsSharedSubtitle(String date) {
    return 'Shared $date • phases only';
  }

  @override
  String get sharingPredictionConnectionsStopTooltip => 'Stop receiving';

  @override
  String get sharingPredictionConnectionsConnect => 'Connect';

  @override
  String get sharingPredictionCalendarLoadError =>
      'Could not load the shared predictions.';

  @override
  String get sharingPredictionCalendarWaitingTitle =>
      'Waiting for the first update';

  @override
  String sharingPredictionCalendarWaitingBody(String profileName) {
    return 'You\'re connected, but $profileName\'s app hasn\'t shared its first predictions yet. They appear here automatically once it does - tap refresh to check again.';
  }

  @override
  String get sharingPredictionCalendarEndedTitle => 'Connection ended';

  @override
  String get sharingPredictionCalendarEndedBody =>
      'This prediction connection is no longer active.';

  @override
  String sharingPredictionCalendarConfidence(String tierLabel) {
    return 'Estimate confidence: $tierLabel';
  }

  @override
  String get sharingPredictionCalendarLegendPeriod => 'Period';

  @override
  String get sharingPredictionCalendarLegendFertile => 'Fertile';

  @override
  String get sharingPredictionCalendarLegendOvulation => 'Ovulation';

  @override
  String get sharingPredictionCalendarLegendPms => 'PMS';

  @override
  String get sharingSharePredictionsCreateFailed =>
      'Failed to create the connection. Please check your connection and try again.';

  @override
  String get sharingSharePredictionsCreatedTitle => 'Connection created';

  @override
  String sharingSharePredictionsSendLink(String profileName) {
    return 'Send this single-use link to the person who should see $profileName\'s predictions:';
  }

  @override
  String sharingSharePredictionsCreatedBody(String expiry) {
    return 'They will see estimated period, fertile, ovulation, and PMS days on a read-only calendar — no notes or logs. $expiry';
  }

  @override
  String get sharingSharePredictionsCopied => 'Copied to clipboard';

  @override
  String get sharingSharePredictionsDone => 'Done';

  @override
  String sharingSharePredictionsTitle(String profileName) {
    return 'Share predictions of $profileName';
  }

  @override
  String get sharingSharePredictionsBody =>
      'Creates a read-only connection that sees estimated period, fertile, ovulation, and PMS days — never notes, tags, or logs. One connection per profile.';

  @override
  String get sharingSharePredictionsNicknameLabel =>
      'Nickname / Label (Optional)';

  @override
  String get sharingSharePredictionsNicknameHint => 'e.g. Partner, Aunt';

  @override
  String get sharingSharePredictionsCancel => 'Cancel';

  @override
  String get sharingSharePredictionsCreateLink => 'Create Link';

  @override
  String sharingTransferOwnershipScreenTitle(String profileName) {
    return 'Transfer $profileName\'s Profile';
  }

  @override
  String get sharingTransferOwnershipConfirmTitle => 'Transfer ownership?';

  @override
  String get sharingTransferOwnershipCancel => 'Cancel';

  @override
  String get sharingTransferOwnershipTransferAction => 'Transfer';

  @override
  String get sharingTransferOwnershipPendingCancelled =>
      'Pending transfer cancelled';

  @override
  String get sharingTransferOwnershipCancelled => 'Transfer cancelled';

  @override
  String get sharingTransferOwnershipLinkCopied =>
      'Transfer link copied to clipboard';

  @override
  String get sharingTransferOwnershipWhatChanges => 'What changes';

  @override
  String get sharingTransferOwnershipBulletKeepRole =>
      'You keep the role you choose below.';

  @override
  String get sharingTransferOwnershipBulletRemoveAccess =>
      'They can remove your access at any time.';

  @override
  String get sharingTransferOwnershipBulletDeleteAccount =>
      'If they later delete their account, this profile\'s history goes with it.';

  @override
  String get sharingTransferOwnershipHelpLabel => 'How does the transfer work?';

  @override
  String get sharingTransferOwnershipRoleAfterTitle =>
      'Your role after the transfer';

  @override
  String get sharingTransferOwnershipRecipientLabel =>
      'Recipient label (optional)';

  @override
  String get sharingTransferOwnershipRecipientHint => 'e.g. Sam';

  @override
  String get sharingTransferOwnershipAction => 'Transfer Ownership';

  @override
  String get sharingTransferOwnershipPendingTitle =>
      'A Transfer Is Already Pending';

  @override
  String sharingTransferOwnershipPendingBody(String profileName) {
    return 'A transfer for $profileName is already pending, but its link is not available on this screen (it may have been created earlier or on another device). Cancel it to start a new one.';
  }

  @override
  String sharingTransferOwnershipExpires(String date) {
    return 'Expires $date';
  }

  @override
  String get sharingTransferOwnershipCancelPending => 'Cancel Pending Transfer';

  @override
  String get sharingTransferOwnershipReadyTitle => 'Transfer Ready';

  @override
  String sharingTransferOwnershipShareLink(String profileName) {
    return 'Share this single-use link with $profileName:';
  }

  @override
  String get sharingTransferOwnershipCopyLink => 'Copy Link';

  @override
  String get sharingTransferOwnershipShare => 'Share';

  @override
  String get sharingTransferOwnershipCancelTransfer => 'Cancel transfer';

  @override
  String sharingActivityFeedScreenTitle(String profileName) {
    return '$profileName Activity';
  }

  @override
  String get sharingActivityFeedJustYouTitle => 'Just you for now';

  @override
  String get sharingActivityFeedJustYouBody =>
      'This profile has one guardian, so there is no shared activity to review. When a second guardian joins, both of your changes appear here.';

  @override
  String get sharingActivityFeedNoActivityTitle => 'No activity yet';

  @override
  String get sharingActivityFeedNoActivityBody =>
      'Changes either guardian makes to this profile will appear here.';

  @override
  String get sharingActivityFeedCaption =>
      'Newest first. Each row shows a day’s latest change — earlier edits by the same guardian are not recorded separately.';

  @override
  String get sharingActivityFeedVerbLogged => 'Logged';

  @override
  String get sharingActivityFeedVerbUpdated => 'Updated';

  @override
  String get sharingActivityFeedVerbRemoved => 'Removed';

  @override
  String sharingActivityFeedByLineActor(String verb, String actor) {
    return '$verb by $actor';
  }

  @override
  String sharingActivityFeedByLineNoActor(String verb) {
    return 'Entry $verb';
  }

  @override
  String get sharingActivityFeedMergeKeptOne => 'Sync merge kept one version';

  @override
  String sharingActivityFeedMergeKeptPossessive(String possessive) {
    return 'Sync merge kept $possessive version';
  }

  @override
  String get sharingActivityFeedAccessRemovedNoActor =>
      'A guardian no longer has access';

  @override
  String sharingActivityFeedAccessRemovedActor(String actor) {
    return '$actor no longer has access';
  }

  @override
  String get sharingActivityFeedAccessRemovedSubtitle =>
      'Access to this profile was removed';

  @override
  String sharingActivityFeedForDate(String date) {
    return 'for $date';
  }

  @override
  String sharingActivityFeedLoggedBy(String actor) {
    return 'logged by $actor';
  }

  @override
  String sharingActivityFeedTagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
    );
    return '$_temp0';
  }

  @override
  String get sharingActivityFeedNote => 'note';

  @override
  String get sharingActivityFeedOneGuardian => 'one guardian';

  @override
  String get sharingActivityFeedDiscardedFlowAndNote =>
      'flow and note values were';

  @override
  String get sharingActivityFeedDiscardedNote => 'note was';

  @override
  String get sharingActivityFeedDiscardedFlow => 'flow value was';

  @override
  String sharingActivityFeedMergeDiscarded(String possessive, String what) {
    return '$possessive $what discarded in a same-date merge';
  }

  @override
  String get sharingActivityFeedNewBadge => 'New';

  @override
  String get sharingActivityFeedPossessiveYou => 'your';

  @override
  String sharingActivityFeedPossessiveName(String name) {
    return '$name\'s';
  }

  @override
  String sharingProfileSharingSharedTooltip(int count) {
    return 'Shared · $count guardians';
  }

  @override
  String sharingPendingInviteBadgePendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending invitations',
      one: '1 pending invitation',
    );
    return '$_temp0';
  }

  @override
  String sharingPendingInviteBadgeExpiredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count invitations expired',
      one: '1 invitation expired',
    );
    return '$_temp0';
  }

  @override
  String get gateLockScreenAppTitle => 'lunarlog';

  @override
  String get gateLockScreenTitle => 'lunarlog is locked';

  @override
  String get gateLockScreenProtectedBody =>
      'Everything logged on this device stays protected. Unlock to continue.';

  @override
  String get gateLockScreenDeniedBody =>
      'Not unlocked. The profiles on this device stay hidden until the device credential is accepted.';

  @override
  String get gateLockScreenUnlockButton => 'Unlock';

  @override
  String get gateLockScreenNoCredentialBody =>
      'This device has no screen lock set. lunarlog protects your family\'s data using your device\'s own screen lock, so it can\'t open until you add one — a passcode, PIN, pattern, or biometric lock all work.';

  @override
  String get gateLockScreenOpenDeviceSettings => 'Open device settings';

  @override
  String get gateLockScreenTryAgain => 'Try again';

  @override
  String get gatePinAuthorizationUseDeviceCredential =>
      'Use device credential instead';

  @override
  String get gatePinAuthorizationCancel => 'Cancel';

  @override
  String get gatePinSettingsRemoveCancel => 'Cancel';

  @override
  String get feedbackAttachmentConsentTitle => 'Attach a screenshot?';

  @override
  String get feedbackAttachmentConsentBody =>
      'Screenshots of this app usually contain cycle data for a family member. Only attach one if it helps explain the issue.';

  @override
  String get feedbackAttachmentConsentCancel => 'Cancel';

  @override
  String get feedbackAttachmentConsentContinue => 'Continue';

  @override
  String get feedbackAttachmentAddScreenshot => 'Add screenshot';

  @override
  String get feedbackScreenTitle => 'Send feedback';

  @override
  String get feedbackScreenCategoryLabel => 'Category';

  @override
  String get feedbackScreenMessageLabel => 'What happened?';

  @override
  String get feedbackScreenReplyEmailLabel => 'Reply email';

  @override
  String get feedbackScreenDiagnosticsTitle => 'Include diagnostics';

  @override
  String get feedbackScreenDiagnosticsSubtitle =>
      'App version, OS, device model, and recent activity.';

  @override
  String get feedbackScreenDiagnosticsPreview => 'See what will be attached';

  @override
  String get feedbackScreenSendButton => 'Send feedback';

  @override
  String get feedbackScreenMessageTooLong =>
      'Message must be 4000 characters or fewer.';

  @override
  String get feedbackScreenReplyEmailInvalid =>
      'Enter a valid reply email address.';

  @override
  String feedbackScreenThanks(String email) {
    return 'Thanks — we\'ll get back to you at $email.';
  }

  @override
  String get supportHistoryTitle => 'Support history';

  @override
  String get supportHistoryEmptyTitle => 'No feedback yet';

  @override
  String get supportHistoryEmptyBody =>
      'Reports you send from Settings appear here.';

  @override
  String get supportHistoryRetry => 'Retry';

  @override
  String get supportHistoryReplyLabel => 'Reply';

  @override
  String get supportHistorySend => 'Send';

  @override
  String get profileDetailUnarchive => 'Unarchive';

  @override
  String get profileDetailOverviewTab => 'Overview';

  @override
  String get profileDetailCalendarTab => 'Calendar';

  @override
  String get profileDetailArchivedSuffix => ' (archived)';

  @override
  String profileDetailSharedGuardians(int count) {
    return 'Shared · $count guardians';
  }

  @override
  String get profilePickerTitle => 'Profiles';

  @override
  String get profilePickerEmptyTitle => 'No profiles yet';

  @override
  String get profilePickerEmptyBody => 'Add a profile to start tracking.';

  @override
  String get profilePickerEmptyAddAction => 'Add profile';

  @override
  String profilePickerArchivedHeader(int count) {
    return 'Archived ($count)';
  }

  @override
  String profilePickerCreated(String date) {
    return 'Created $date';
  }

  @override
  String get profilePickerMyProfilesHeader => 'My profiles';

  @override
  String get profilePickerSharedWithMeHeader => 'Shared with me';

  @override
  String get profilePickerMenuGuardians => 'Guardians';

  @override
  String get profileArchive => 'Archive';

  @override
  String get profileDialogCountsAsMinor =>
      'Counts as a minor (derived from birth year)';

  @override
  String get profileDialogCountsAsAdult =>
      'Counts as an adult (derived from birth year)';

  @override
  String get profileDialogAddTitle => 'Add profile';

  @override
  String get profileDialogBirthYearLabel => 'Birth year (optional)';

  @override
  String get profileDialogRelationshipNone => 'None';

  @override
  String get profileDialogCancel => 'Cancel';

  @override
  String get profileDialogCreate => 'Create';

  @override
  String get profileDialogSave => 'Save';

  @override
  String profileArchiveConfirmTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get profileArchiveConfirmBody =>
      'The profile moves to the archived list and out of everyday use. Its history stays on this device and can be restored at any time.';

  @override
  String get profileArchiveConfirmCancel => 'Cancel';

  @override
  String get profileArchiveConfirmButton => 'Archive';

  @override
  String get firstRunCreateError =>
      'Could not create the profile. Please try again.';

  @override
  String careNotesTitle(String name) {
    return '$name Care';
  }

  @override
  String get careNotesReadOnlyArchived => 'This profile is archived.';

  @override
  String get careNotesSectionTitle => 'Care notes';

  @override
  String get careNotesEmpty => 'No care notes yet.';

  @override
  String get careNotesAddLabel => 'Add a care note';

  @override
  String get careNotesAddHint =>
      'Standing notes for everyone caring for this profile';

  @override
  String get careNotesAddButton => 'Add note';

  @override
  String get careNotesDeleteTitle => 'Delete this care note?';

  @override
  String get careNotesDeleteBody =>
      'Every guardian with access to this profile can see this note. Deleting it removes it for everyone and cannot be undone.';

  @override
  String get careNotesDeleteCancel => 'Cancel';

  @override
  String get careNotesDeleteConfirm => 'Delete';

  @override
  String get careNotesActorYou => 'you';

  @override
  String get careNotesActorGuardian => 'Guardian';

  @override
  String get careNotesSaveError => 'Could not save the care note.';

  @override
  String get careNotesAddPrepError => 'Could not add the prep item.';

  @override
  String get careNotesAddSupplyError => 'Could not add the supply item.';

  @override
  String get careNotesUpdatePrepError => 'Could not update the prep item.';

  @override
  String get careNotesRemovePrepError => 'Could not remove the prep item.';

  @override
  String get careNotesRemoveNoteError => 'Could not remove the care note.';

  @override
  String get careNotesClearCheckedError => 'Could not clear the checked items.';

  @override
  String get careNotesClearStockedError => 'Could not clear the stocked items.';

  @override
  String get careVisitPrepSectionTitle => 'Visit prep';

  @override
  String get careVisitPrepEmpty => 'No prep items yet.';

  @override
  String careVisitPrepClearChecked(int count) {
    return 'Clear checked ($count)';
  }

  @override
  String get careVisitPrepAddLabel => 'Add a prep item';

  @override
  String get careVisitPrepAddHint =>
      'A question or to-bring for the next appointment';

  @override
  String get careVisitPrepAddButton => 'Add item';

  @override
  String get careVisitPrepCheckedVerb => 'Checked by';

  @override
  String get careSuppliesSectionTitle => 'Supplies';

  @override
  String get careSuppliesEmpty => 'No supplies tracked yet.';

  @override
  String careSuppliesClearStocked(int count) {
    return 'Clear stocked ($count)';
  }

  @override
  String get careSuppliesAddLabel => 'Add a supply item';

  @override
  String get careSuppliesAddHint => 'Something to keep stocked, e.g. liners';

  @override
  String get careSuppliesAddButton => 'Add supply';

  @override
  String get careSuppliesStockedVerb => 'Stocked by';

  @override
  String careRestockBefore(String date) {
    return 'Restock before $date';
  }

  @override
  String get guardianNotesFieldLabel => 'Your note for this day';

  @override
  String get guardianNotesGuardianFallback => 'Guardian';

  @override
  String get webBannerDevCopy => 'Development build — not for real data.';

  @override
  String get webBannerSyncedCopy =>
      'Browser build — this browser stores a copy of the signed-in profiles\' data unencrypted, plus your sign-in. Signing out clears it.';

  @override
  String get webBrowserNoticeDismissTooltip => 'Dismiss';

  @override
  String get webWipeAction => 'Wipe local data';

  @override
  String get webWipeConfirmTitle => 'Erase all local data?';

  @override
  String get webWipeConfirmDevBody =>
      'Erases all data stored in this browser. This cannot be undone.';

  @override
  String get webWipeConfirmSyncedBody =>
      'Erases all data stored in this browser and signs out. This cannot be undone here; data already in your account stays there.';

  @override
  String get webWipeCancel => 'Cancel';

  @override
  String get webWipeConfirmAction => 'Erase everything';

  @override
  String get webWipeDone => 'All local data erased.';

  @override
  String get webFirstRunDevTitle => 'Development build';

  @override
  String get webFirstRunDevBody =>
      'This is a development build, not for real data. Data in this browser is not encrypted and not backed up.';

  @override
  String get webFirstRunSyncedTitle => 'Using lunarlog in this browser';

  @override
  String get webFirstRunSyncedBody =>
      'This browser keeps an unencrypted copy of the profiles you can see — including synced family data — and your sign-in. Anyone who uses this browser can read it. Signing out removes the copy from this browser; your account\'s data stays in your account and can sync again later.';

  @override
  String get webFirstRunAcknowledge => 'I understand';

  @override
  String get accountMismatchTitle => 'Different account';

  @override
  String get accountMismatchBodyNoEmail =>
      'This device holds data that belongs to a different account than the one you just signed in to.';

  @override
  String accountMismatchBodyWithEmail(String email) {
    return 'This device holds data that belongs to a different account than $email.';
  }

  @override
  String get accountMismatchExplainer =>
      'This device is set up for a different account. This happens when Apple\'s Hide My Email created a new account, or when you chose a different Google account. Nothing has been uploaded or changed.';

  @override
  String get accountMismatchSwitchAccount => 'Switch account';

  @override
  String get accountMismatchSwitchAccountSubtitle =>
      'Signs out and keeps everything on this device.';

  @override
  String get accountMismatchRemoveData => 'Remove this device\'s data';

  @override
  String get accountMismatchRemoveDialogTitle => 'Remove this device\'s data?';

  @override
  String get accountMismatchRemoveDialogBody =>
      'Erases every profile and entry stored on this device and signs out. The data stays in the account it belongs to; it is not deleted there.';

  @override
  String get accountMismatchCancel => 'Cancel';

  @override
  String get accountMismatchRemoveConfirm => 'Remove and sign out';

  @override
  String get accountMismatchSwitchError =>
      'Could not switch accounts. Please try again.';

  @override
  String get accountMismatchRemoveError =>
      'Could not remove this device\'s data. Please try again.';

  @override
  String get accountUploadConsentTitle => 'Upload to your account?';

  @override
  String accountUploadConsentBody(int profileCount, int entryCount) {
    String _temp0 = intl.Intl.pluralLogic(
      profileCount,
      locale: localeName,
      other: '$profileCount profiles',
      one: '1 profile',
    );
    String _temp1 = intl.Intl.pluralLogic(
      entryCount,
      locale: localeName,
      other: '$entryCount entries',
      one: '1 entry',
    );
    return 'This device holds $_temp0 and $_temp1 that are not in your account yet. Uploading copies them to the account, deletions included, and keeps this device in sync from now on.';
  }

  @override
  String get accountUploadConsentLoadingBody =>
      'This device holds data that is not in your account yet.';

  @override
  String get accountUploadConsentDuplicateNote =>
      'If another device also created the same person while offline, you will see two profiles after the upload; archive the one you do not want.';

  @override
  String get accountUploadConsentUploadAction => 'Upload to my account';

  @override
  String get accountUploadConsentNotNow => 'Not now';

  @override
  String get accountRestoringScreenBody => 'Restoring your data…';

  @override
  String get accountRestoreErrorTitle => 'Unable to restore data';

  @override
  String get accountRestoreErrorBody =>
      'We could not restore your account data from the cloud. Please check your internet connection and try again.';

  @override
  String get accountRestoreErrorRetry => 'Retry';

  @override
  String get accountRestoreErrorContinue => 'Continue without syncing';

  @override
  String get accountRestoreErrorSignOut => 'Sign out';

  @override
  String get accountPasswordRecoveryTitle => 'Set a new password';

  @override
  String get accountPasswordRecoveryIntro =>
      'You opened a password reset link. Choose a new password for your account.';

  @override
  String get accountPasswordRecoveryNewLabel => 'New password';

  @override
  String accountPasswordRecoveryLengthHelper(int length) {
    return 'At least $length characters';
  }

  @override
  String get accountPasswordRecoveryConfirmLabel => 'Confirm password';

  @override
  String get accountPasswordRecoveryShow => 'Show password';

  @override
  String get accountPasswordRecoveryHide => 'Hide password';

  @override
  String accountPasswordRecoveryLengthError(int length) {
    return 'Use at least $length characters for the password.';
  }

  @override
  String get accountPasswordRecoveryMismatchError => 'Passwords do not match.';

  @override
  String get accountPasswordRecoverySave => 'Save password';

  @override
  String get accountPasswordRecoveryNotNow => 'Not now';

  @override
  String get accountMfaSettingsCancel => 'Cancel';

  @override
  String get accountMfaStepUpCancel => 'Cancel';

  @override
  String get accountSyncStatusTapToRetry => 'Tap to retry';

  @override
  String get accountSyncStatusSettingsAction => 'Settings';

  @override
  String get accountSignInEmbeddedIntro =>
      'An account keeps a copy of this device\'s data so it can be restored on another device. You can also keep everything on this device only.';

  @override
  String get accountSignInPasskeyAction => 'Sign in with a passkey';

  @override
  String get accountSignInOr => 'or';

  @override
  String get accountSignInEmailLabel => 'Email';

  @override
  String get accountSignInEmailRequired => 'Enter your email address.';

  @override
  String get accountSignInEmailInvalid =>
      'That doesn\'t look like an email address.';

  @override
  String get accountSignInPasswordLabel => 'Password';

  @override
  String get accountSignInCreateAccountAction => 'Create account';

  @override
  String get accountSignInAction => 'Sign in';

  @override
  String get accountSignInForgotPasswordAction => 'Forgot password';

  @override
  String get accountSignInCodeLabel => 'Code from the email';

  @override
  String get accountSignInCodeHint => '6-10 digits';

  @override
  String get accountSignInVerifyCodeAction => 'Sign in with code';

  @override
  String get accountSignInNotNow => 'Not now';

  @override
  String get accountSignInTitle => 'Sign in';

  @override
  String get accountSignInTitleCreate => 'Create an account';

  @override
  String accountSignInUseAtLeast(int length) {
    return 'Use at least $length characters for the password.';
  }

  @override
  String get accountSignInConfirmEmailInfo =>
      'Check your email to confirm the account, then open the link on this device.';

  @override
  String get accountSignInResetInfo =>
      'If an account exists for that email, a reset link is on its way. Open it on this device. If you request another email, only the newest link works — an earlier one stops working (issue #32).';

  @override
  String get accountSignInMagicLinkInfo =>
      'Check your email for a sign-in link or code.';

  @override
  String accountSignInPasswordLengthHelper(int length) {
    return 'At least $length characters';
  }

  @override
  String get accountSignInShowPassword => 'Show password';

  @override
  String get accountSignInHidePassword => 'Hide password';

  @override
  String get accountSignInToggleHaveAccount => 'I already have an account';

  @override
  String get accountSignInToggleCreateInstead => 'Create an account instead';

  @override
  String get accountSignInMagicLinkCreate =>
      'Email me a link to create my account';

  @override
  String get accountSignInMagicLinkSignIn => 'Email me a sign-in link';

  @override
  String get accountDeleteDialogTitle => 'Delete account?';

  @override
  String get accountDeleteDialogGuardianNote =>
      'Entries you logged as a guardian on someone else\'s profile are kept and re-attributed to its owner, not deleted. Apple Health / Health Connect writes this device already made stay in the device\'s own health store - account deletion does not remove them.';

  @override
  String get accountDeleteDialogAck =>
      'I understand this removes access for other guardians and deletes any minor profiles I own.';

  @override
  String get accountDeleteDialogCancel => 'Cancel';

  @override
  String get accountDeleteDialogTransferFirst => 'Transfer ownership first';

  @override
  String get accountDeleteDialogExportFirst => 'Export first';

  @override
  String get accountDeleteDialogConfirm => 'Delete account';

  @override
  String get accountDeleteDialogExportError =>
      'Could not export your data. Please try again.';

  @override
  String accountDeleteDialogBlastRadiusProfiles(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profiles',
      one: '1 profile',
    );
    return 'This will also permanently delete $_temp0 you own ($names).';
  }

  @override
  String accountDeleteDialogBlastRadiusGuardians(
    int count,
    String names,
    int guardianCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profiles',
      one: '1 profile',
    );
    String _temp1 = intl.Intl.pluralLogic(
      guardianCount,
      locale: localeName,
      other: '$guardianCount other guardians',
      one: '1 other guardian',
    );
    return 'This will also permanently delete $_temp0 you own ($names) and remove access for $_temp1.';
  }

  @override
  String get accountSectionTitle => 'Account';

  @override
  String accountSectionSignInMethods(String methods) {
    return 'Sign-in methods: $methods';
  }

  @override
  String get accountSectionSignedIn => 'Signed in';

  @override
  String accountSectionSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get accountSectionAddApple => 'Add Apple';

  @override
  String get accountSectionAddGoogle => 'Add Google';

  @override
  String get accountSectionAddPasskey => 'Add a passkey';

  @override
  String get accountSectionSyncSubtitle =>
      'Sync this device\'s data to an account.';

  @override
  String get accountSectionSignInAgain => 'Sign in again';

  @override
  String get accountSectionSignIn => 'Sign in';

  @override
  String get accountSectionSyncNow => 'Sync now';

  @override
  String get accountSectionSignOut => 'Sign out';

  @override
  String get accountSectionSignOutSubtitle =>
      'Removes the data from this device.';

  @override
  String get accountSectionSignOutEverywhere => 'Sign out everywhere';

  @override
  String get accountSectionSignOutEverywhereSubtitle =>
      'Signs out all devices, though others may take up to an hour to notice.';

  @override
  String get accountSectionDelete => 'Delete account';

  @override
  String get accountSectionLinkSubtitle =>
      'Sign in to this account another way.';

  @override
  String accountSectionRemoveProvider(String provider) {
    return 'Remove $provider';
  }

  @override
  String get accountSectionRemoveSubtitle =>
      'Stop using this to sign in to this account.';

  @override
  String accountSectionRemoveTitle(String provider) {
    return 'Remove $provider?';
  }

  @override
  String accountSectionRemoveBody(String provider) {
    return 'You will no longer be able to sign in to this account with $provider. Your data and your other sign-in methods are unchanged.';
  }

  @override
  String get accountSectionCancel => 'Cancel';

  @override
  String get accountSectionRemove => 'Remove';

  @override
  String get accountSectionUnsyncedTitle => 'Unsynced changes';

  @override
  String accountSectionUnsyncedBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes on this device have not been uploaded yet, deletions included. Sync first, or discard them and sign out.',
      one: '1 change on this device has not been uploaded yet, deletions included. Sync first, or discard it and sign out.',
    );
    return '$_temp0';
  }

  @override
  String get accountSectionDiscardAndSignOut =>
      'Discard unsynced changes and sign out';

  @override
  String get accountSectionSignOutTitle => 'Sign out?';

  @override
  String get accountSectionSignOutEverywhereTitle => 'Sign out everywhere?';

  @override
  String get accountSectionSignOutBody =>
      'This removes the data from this device. It stays in your account.';

  @override
  String accountSectionOtherDevicesNotSignedOut(String failureCopy) {
    return '$failureCopy Other devices were not signed out.';
  }

  @override
  String get settingsExportRangeTitle => 'Export range';

  @override
  String get settingsExportRangeCancel => 'Cancel';

  @override
  String get settingsExportRangeConfirm => 'Export';

  @override
  String get settingsExportRangeStartDate => 'Start date';

  @override
  String get settingsExportRangeEndDate => 'End date';

  @override
  String get settingsClinicalExportFhirTitle =>
      'Export clinical summary (FHIR)';

  @override
  String get settingsCsvExportTitle => 'Export as CSV';

  @override
  String get settingsCsvExportForTitle => 'Export CSV data for';

  @override
  String healthSyncBindTitle(String name) {
    return 'Sync $name to this phone?';
  }

  @override
  String healthSyncBindWriteBody(String name, String source) {
    return 'Only $name\'s data will ever be written to $source. This phone can sync one profile at a time — choosing a different profile later replaces this one.';
  }

  @override
  String healthSyncBindImportBody(String name, String source) {
    return 'Only $name\'s data will ever be imported from $source. This phone can sync one profile at a time — choosing a different profile later replaces this one.';
  }

  @override
  String get healthSyncBindCancel => 'Cancel';

  @override
  String healthSyncSyncFailed(String name) {
    return 'Couldn\'t sync $name — try again.';
  }

  @override
  String get healthSyncImportFailed =>
      'Couldn\'t finish the import. Please try again.';

  @override
  String get healthSyncLoadFailed => 'Couldn\'t load profiles for health sync.';

  @override
  String get healthSyncRetry => 'Retry';

  @override
  String healthSyncImporting(String source) {
    return 'Importing from $source…';
  }

  @override
  String get healthSyncFlowCollapseNote =>
      'Super heavy days are written to the Health app as Heavy. Spotting logged inside a period is written as Light bleeding; spotting between periods is written as intermenstrual bleeding.';

  @override
  String get healthSyncRevocationNote =>
      'Turning sync off, or later revoking this phone\'s Health app permission, leaves everything already written in the Health app in place. To remove it, delete it in the Health app itself.';

  @override
  String healthSyncImportFrom(String source) {
    return 'Import from $source';
  }

  @override
  String get healthSyncUnbindAction => 'Stop syncing to this phone';

  @override
  String get importScreenTitle => 'Import from file';

  @override
  String get importScreenPickBody =>
      'Choose a file: a JSON backup this app exported (Settings > Your data > Export my data), or the .zip Clue emailed you. Your data is added to this device — nothing already here is ever deleted.';

  @override
  String get importScreenChooseFileAction => 'Choose file';

  @override
  String get importScreenImportAction => 'Import';

  @override
  String get importScreenCancel => 'Cancel';

  @override
  String get importScreenDone => 'Done';

  @override
  String get reminderNoProfile => 'Create a profile to set up reminders.';

  @override
  String get reminderPrivacyNote =>
      'Reminders never show a name, date, or any health detail on the lock screen. Logging from a notification waits until the app is unlocked.';

  @override
  String get reminderProfileLabel => 'Profile';

  @override
  String get reminderCadenceLabel => 'Cadence';

  @override
  String get reminderTimeLabel => 'Time';

  @override
  String get reminderQuietHoursTitle => 'Quiet hours';

  @override
  String get reminderQuietHoursSubtitle =>
      'A reminder that lands inside the window waits until it ends';

  @override
  String get reminderQuietStart => 'Starts';

  @override
  String get reminderQuietEnd => 'Ends';

  @override
  String get yourDataExportTitle => 'Export my data';

  @override
  String get yourDataExportSubtitleSignedIn =>
      'Save your profiles, day entries, care notes, and visit-prep lists as a JSON file, including your account\'s server data.';

  @override
  String get yourDataExportSubtitleLocal =>
      'Save your profiles, day entries, care notes, and visit-prep lists as a JSON file.';

  @override
  String get yourDataImportTitle => 'Import from file';

  @override
  String get yourDataImportSubtitle =>
      'Restore from a JSON backup, or bring in a Clue export (.zip).';

  @override
  String get yourDataPurgeTitle => 'Purge imported data';

  @override
  String get yourDataPurgeSubtitle =>
      'Remove only the entries a specific import brought in — manually logged data is never touched.';

  @override
  String yourDataPurgedSnack(String source) {
    return 'Purged $source data';
  }

  @override
  String get yourDataPurgeDialogBody =>
      'Only entries and observations tagged with the chosen import source are removed. Manually logged data, and the profile itself, are never touched. If this purge leaves the profile with no entries at all, its saved cycle details (last period start and typical cycle length) are cleared too, since they may have come from the import.';

  @override
  String get yourDataPurgeProfileLabel => 'Profile';

  @override
  String get yourDataPurgeCancel => 'Cancel';

  @override
  String get yourDataPurgeConfirm => 'Purge';

  @override
  String get yourDataImportSourceLabel => 'Import source';

  @override
  String cycleLiteracyReadingTimeMinutes(int minutes) {
    return '$minutes min read';
  }

  @override
  String get cycleLiteracySourceHeading => 'Source & Review';

  @override
  String cycleLiteracySourceLine(String source) {
    return 'Source: $source';
  }

  @override
  String cycleLiteracyLastReviewedLine(String date) {
    return 'Last reviewed: $date';
  }

  @override
  String get cycleLiteracyLibraryTitle => 'Cycle Literacy Library';

  @override
  String get cycleLiteracyLibraryIntro =>
      'Evidence-based educational guides to understand your body, hormones, and cycle rhythms.';

  @override
  String helpCardSourceLine(String source) {
    return 'Source: $source';
  }

  @override
  String helpCardReviewedLine(String date) {
    return 'Reviewed: $date';
  }

  @override
  String get failClosedAppTitle => 'lunarlog';

  @override
  String get failClosedClose => 'Close';

  @override
  String get failClosedTechnicalDetail =>
      'Technical detail (for the device owner):';

  @override
  String get failClosedQuarantineTitle => 'lunarlog could not open your data';

  @override
  String get failClosedQuarantineBody =>
      'The data saved on this device could not be opened. Nothing was changed and nothing was deleted — the data file was left exactly as it was, untouched.';

  @override
  String get failClosedStartTitle => 'lunarlog could not start';

  @override
  String get failClosedStartBody =>
      'Something went wrong before any data was opened. Nothing on this device was changed.';

  @override
  String get daySheetDiscardFailedBody =>
      'The last change couldn\'t be saved. Discarding removes it from this device.';

  @override
  String monthCalendarFertileWindowExplainer(String label) {
    return '$label — the days around estimated ovulation, back-calculated from the estimated period date.';
  }

  @override
  String get mergeNoticeDismissTooltip => 'Dismiss';

  @override
  String get mergeNoticeAnotherGuardian => 'another guardian';

  @override
  String get mergeNoticeAnotherGuardianPossessive => 'another guardian\'s';

  @override
  String get mergeNoticeYou => 'you';

  @override
  String get mergeNoticeYour => 'your';

  @override
  String mergeNoticeNoteBody(String winner, String loser) {
    return 'Two entries for this date were merged; $winner note was kept and $loser note was discarded.';
  }

  @override
  String mergeNoticeFlowBody(String winner, String loser) {
    return 'Two entries for this date were merged; $winner flow level was kept and $loser was discarded.';
  }

  @override
  String get mergeNoticeGuardianNoteBody =>
      'A guardian note for this date was replaced on sync.';

  @override
  String get mergeNoticeRestoreNote => 'Restore my note';

  @override
  String get mergeNoticeRestoreFlow => 'Restore my flow level';

  @override
  String get caregiverAttributionYou => 'you';

  @override
  String get caregiverAttributionGuardianFallback => 'Guardian';

  @override
  String caregiverAttributionLoggedBy(String name) {
    return 'Logged by $name';
  }

  @override
  String caregiverAttributionModifiedBy(String name) {
    return 'Modified by $name';
  }

  @override
  String get caregiverAttributionImportedClue => 'Imported from Clue';

  @override
  String get caregiverAttributionImportedHealth => 'Imported from Health';

  @override
  String get caregiverAttributionImportedHealthConnect =>
      'Imported from Health Connect';

  @override
  String get caregiverAttributionImportedFile => 'Imported from file';

  @override
  String get caregiverAttributionImportedWearable => 'Imported from wearable';

  @override
  String get caregiverAttributionImportedGeneric => 'Imported';

  @override
  String get commonRetry => 'Retry';

  @override
  String get appShellTabToday => 'Today';

  @override
  String get appShellTabCalendar => 'Calendar';

  @override
  String get appShellTabInsights => 'Insights';

  @override
  String get appShellTabMore => 'More';

  @override
  String get appShellSyncBannerGoToSettings => 'Go to Settings';

  @override
  String todayCardLogsFlowTooltip(String level) {
    return 'Logs a $level-flow period start for today';
  }

  @override
  String get cycleHistoryTitle => 'Cycle history';

  @override
  String get cycleHistorySyncNote => 'Omissions sync across your devices.';

  @override
  String get cycleHistoryAvgCycle => 'Avg cycle';

  @override
  String get cycleHistoryAvgPeriod => 'Avg period';

  @override
  String get cycleHistoryVariation => 'Variation';

  @override
  String get cycleHistoryOutlier => 'Outlier — never averaged';

  @override
  String cycleHistoryCurrentCycleStarted(String date) {
    return 'Current cycle — started $date';
  }

  @override
  String get cycleHistorySkippedExcluded => 'Skipped — excluded from averages';

  @override
  String get cycleHistoryInclude => 'Include';

  @override
  String get cycleHistoryOmit => 'Omit';

  @override
  String get cycleHistoryUndo => 'Undo';

  @override
  String lateResolverSnoozedUntil(String date) {
    return 'We will check back on $date.';
  }

  @override
  String get lateResolverShowOptions => 'Show options';

  @override
  String lateResolverDaysLate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days late',
      one: '1 day late',
    );
    return '$_temp0';
  }

  @override
  String lateResolverNoPeriodLoggedFor(String days) {
    return 'No period logged for $days';
  }

  @override
  String get lateResolverPromptStillNothing =>
      'Still nothing logged — what would you like to do?';

  @override
  String get lateResolverPrompt => 'What would you like to do?';

  @override
  String get lateResolverLogIt => 'Log it';

  @override
  String get lateResolverSkipCycle => 'Skip this cycle';

  @override
  String get lateResolverRemindMe => 'Remind me in 3 days';

  @override
  String get lateResolverWhyLate => 'Why is it late?';

  @override
  String get overviewWhyThreeCompletedCycles => 'Why three completed cycles?';

  @override
  String get analysisLoadError => 'Could not load your cycle analysis.';

  @override
  String get analysisTitle => 'Analysis';

  @override
  String get analysisBbtChartTitle => 'BBT by cycle day';

  @override
  String get analysisStatsTitle => 'Cycle statistics';

  @override
  String get analysisMeanCycleLength => 'Average cycle length';

  @override
  String get analysisMeanPeriodLength => 'Average period length';

  @override
  String get analysisVariability => 'Variability';

  @override
  String analysisSpreadDays(int days) {
    return '±$days days';
  }

  @override
  String get bbtChartEmptyTitle => 'No BBT logged yet';

  @override
  String get bbtChartEmptyBody =>
      'Log a basal body temperature reading in the day sheet to see your curve here, plotted against cycle day.';

  @override
  String bbtChartCaption(int count, String range) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cycles shown',
      one: '1 cycle shown',
    );
    return '$_temp0 · $range';
  }

  @override
  String get phaseInsightsHelpfulToTrack => 'Helpful to track:';

  @override
  String phaseInsightsReadArticle(String title) {
    return 'Read: $title';
  }

  @override
  String phaseInsightsSource(String source, String date) {
    return 'Source: $source · Rev: $date';
  }

  @override
  String get symptomTrendsTitle => 'Symptom Trends & Patterns';

  @override
  String get symptomTrendsRecurring => 'Recurring Symptoms';

  @override
  String get symptomTrendsEmpty =>
      'Log symptoms across at least 3 completed cycles to uncover recurring patterns and trends.';

  @override
  String get symptomTrendsDisclaimer =>
      'Patterns reflect descriptive logs only and are not clinical diagnostics.';

  @override
  String get symptomTrendsFlowTitle => 'Typical Bleed Rhythm';

  @override
  String symptomTrendsFlowSubtitle(int day, String flow) {
    return 'Peak flow typically falls on Cycle Day $day ($flow).';
  }

  @override
  String get symptomTrendsLibraryTitle => 'Cycle Literacy Library';

  @override
  String get symptomTrendsLibrarySubtitle =>
      'Evidence-based guides on hormones, cycle phases, and body signals.';

  @override
  String get crampPredictionTitle => 'Anticipated Cramp Window';

  @override
  String crampPredictionDates(String dates) {
    return 'Estimated dates: $dates';
  }

  @override
  String crampPredictionObserved(int observed, int total) {
    return 'Observed in $observed of $total recorded cycles.';
  }

  @override
  String symptomTrendsLogged(int occurrences, int cycles) {
    return 'Logged $occurrences times across $cycles cycles';
  }
}
