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
  String get cyclePredictionLoadError => 'Could not load the cycle estimate.';

  @override
  String get cycleHistoryLoadError => 'Could not load cycle history.';

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
  String get daySheetTagSearchHint => 'Search';

  @override
  String get daySheetTagSearchSemanticsLabel => 'Search tags';

  @override
  String get daySheetTagSearchClearTooltip => 'Clear search';

  @override
  String get daySheetTagRecentLabel => 'Recent';

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
      'It has run well past a typical cycle for this profile. You can exclude it from future averages, or turn off predictions if long cycles are common for this profile.';

  @override
  String get overviewLongCycleExclude => 'Exclude this cycle';

  @override
  String get overviewLongCyclePredictionsOff => 'Turn off predictions';

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
      'LunarLog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind biometric authentication.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Minimum-Age Policy: Licensed for ages 13 and older; household profiles managed by adult guardians (18+).\n• Caregiver Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md';

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
  String get firstRunAgeAcknowledgementLabel =>
      'I am 13 or older, or a guardian managing a family profile';

  @override
  String get firstRunAgeAcknowledgementHint =>
      'LunarLog requires users to be at least 13 years old, or managed by a parent or legal guardian.';

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
      'Enter a number between 15 and 60';

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
  String get predictionsSuppressedTitle => 'Predictions are suppressed';

  @override
  String predictionsSuppressedBody(String method) {
    return 'Because $method typically stops or irregularly affects periods, period predictions are turned off while it is active. The method will resume ordinary prediction once it is switched or cleared.';
  }

  @override
  String predictionsSuppressedByModeBody(String mode) {
    return 'Because this profile is set to $mode mode, period predictions are turned off — the ordinary cycle averages this app estimates from don\'t apply right now. Switch back to Period Tracking mode in profile settings to resume ordinary prediction.';
  }

  @override
  String get predictionsDisabledTitle => 'Predictions turned off';

  @override
  String get predictionsDisabledBody =>
      'Estimates, calendar prediction bands, and prediction reminders are paused for this profile. Your cycle history and tracking continue unchanged.';

  @override
  String get predictionsDisabledAction => 'Manage in Settings';

  @override
  String get settingsPredictionsTitle => 'Show predictions';

  @override
  String settingsPredictionsProfileTitle(String profileName) {
    return 'Show predictions ($profileName)';
  }

  @override
  String get settingsPredictionsSubtitle =>
      'Show cycle estimates, fertile window, and prediction reminders';

  @override
  String get overviewIrregularSuggestionTitle => 'Cycles vary a lot';

  @override
  String get overviewIrregularSuggestionBody =>
      'Predictions may be less useful when cycles vary widely. You can turn off cycle estimates while continuing to track normally.';

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
      'Waits for a start date on the recorded method — re-record the method in profile settings to set one';

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
  String get sharingFailureOther =>
      'Failed to accept invitation. Please try again.';

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
      'New accounts for this app are set up by the account owner.';

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
  String get manageGuardiansRemoveCaregiverTooltip => 'Remove caregiver';

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
  String get profilePickerSharedWithMeTooltip => 'Shared with me';

  @override
  String get profileDetailSwitchProfileTooltip => 'Switch profile';

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
}
