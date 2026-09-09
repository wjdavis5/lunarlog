import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Tooltip on the month calendar's back-month chevron.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get calendarPreviousMonthTooltip;

  /// Tooltip on the month calendar's jump-to-today button.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calendarTodayTooltip;

  /// Tooltip on the month calendar's forward-month chevron.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get calendarNextMonthTooltip;

  /// The month calendar's header label, e.g. 'September 2026'.
  ///
  /// In en, this message translates to:
  /// **'{month} {year}'**
  String calendarMonthYearLabel(String month, int year);

  /// Title of the empty-month banner above the calendar grid.
  ///
  /// In en, this message translates to:
  /// **'No entries this month'**
  String get calendarNoEntriesTitle;

  /// Body of the empty-month banner above the calendar grid.
  ///
  /// In en, this message translates to:
  /// **'Tap a day to log it'**
  String get calendarNoEntriesBody;

  /// Snackbar shown when a fourth symptom layer is selected.
  ///
  /// In en, this message translates to:
  /// **'Up to three symptom layers at once'**
  String get calendarLayerLimitSnack;

  /// Semantics label expanding the calendar's legend strip.
  ///
  /// In en, this message translates to:
  /// **'Show legend'**
  String get calendarShowLegend;

  /// Semantics label collapsing the calendar's legend strip.
  ///
  /// In en, this message translates to:
  /// **'Hide legend'**
  String get calendarHideLegend;

  /// The collapsed label of the calendar's legend strip.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get calendarLegend;

  /// Legend entry for a spotting-level logged bleed day.
  ///
  /// In en, this message translates to:
  /// **'Spotting flow'**
  String get calendarLegendSpotting;

  /// Legend entry for a light-level logged bleed day.
  ///
  /// In en, this message translates to:
  /// **'Light flow'**
  String get calendarLegendLight;

  /// Legend entry for a medium-level logged bleed day.
  ///
  /// In en, this message translates to:
  /// **'Medium flow'**
  String get calendarLegendMedium;

  /// Legend entry for a heavy-level logged bleed day.
  ///
  /// In en, this message translates to:
  /// **'Heavy flow'**
  String get calendarLegendHeavy;

  /// Legend entry for a super-heavy logged bleed day; the parenthetical names its non-colour dot-count channel.
  ///
  /// In en, this message translates to:
  /// **'Super heavy flow (5 marks)'**
  String get calendarLegendSuperHeavy;

  /// Legend entry for a logged symptom-only day.
  ///
  /// In en, this message translates to:
  /// **'Symptom day'**
  String get calendarLegendSymptom;

  /// Legend entry for today's ring marker.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calendarLegendToday;

  /// Legend entry for a predicted (hatched) day band.
  ///
  /// In en, this message translates to:
  /// **'Predicted day'**
  String get calendarLegendPredicted;

  /// Legend entry for the predicted premenstrual badge.
  ///
  /// In en, this message translates to:
  /// **'PMS window'**
  String get calendarLegendPms;

  /// Legend entry for the predicted cramps badge.
  ///
  /// In en, this message translates to:
  /// **'Cramps window'**
  String get calendarLegendCramps;

  /// Legend entry keying the symptom-layer colour channel.
  ///
  /// In en, this message translates to:
  /// **'Symptom layer dots'**
  String get calendarLegendLayerDots;

  /// The symptom-layers summary row when no layer is active.
  ///
  /// In en, this message translates to:
  /// **'Symptom layers'**
  String get calendarSymptomLayers;

  /// The symptom-layers summary row, listing the active layers.
  ///
  /// In en, this message translates to:
  /// **'Layers: {tags}'**
  String calendarLayersSummary(String tags);

  /// Tooltip expanding the symptom-layers chip panel.
  ///
  /// In en, this message translates to:
  /// **'Show symptom layers'**
  String get calendarShowSymptomLayers;

  /// Tooltip collapsing the symptom-layers chip panel.
  ///
  /// In en, this message translates to:
  /// **'Hide symptom layers'**
  String get calendarHideSymptomLayers;

  /// Strip shown on quiet months while no estimate is active.
  ///
  /// In en, this message translates to:
  /// **'Keep logging — predicted bands appear once a few cycles are recorded.'**
  String get calendarKeepLogging;

  /// The date half of a calendar day cell's screen-reader label, e.g. 'Wednesday, September 9'.
  ///
  /// In en, this message translates to:
  /// **'{weekday}, {month} {day}'**
  String calendarCellDateLabel(String weekday, String month, int day);

  /// Screen-reader fragment naming a logged day's bleed level, e.g. 'Medium flow'.
  ///
  /// In en, this message translates to:
  /// **'{level} flow'**
  String calendarCellFlowState(String level);

  /// Screen-reader fragment for a logged day that also carries tags or a note.
  ///
  /// In en, this message translates to:
  /// **'symptoms logged'**
  String get calendarCellSymptomsLogged;

  /// Screen-reader fragment for a logged day with no tags and no note.
  ///
  /// In en, this message translates to:
  /// **'no symptoms'**
  String get calendarCellNoSymptoms;

  /// Screen-reader fragment for a symptom-only logged day (no bleed).
  ///
  /// In en, this message translates to:
  /// **'logged symptoms'**
  String get calendarCellLoggedSymptoms;

  /// Screen-reader fragment for a logged day with no bleed and no symptoms.
  ///
  /// In en, this message translates to:
  /// **'logged'**
  String get calendarCellLogged;

  /// Screen-reader fragment for a past or present day with no entry.
  ///
  /// In en, this message translates to:
  /// **'not logged'**
  String get calendarCellNotLogged;

  /// Screen-reader fragment marking the calendar's today cell.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get calendarCellToday;

  /// Screen-reader fragment explaining why a future calendar cell opens an explainer instead of the log sheet.
  ///
  /// In en, this message translates to:
  /// **'future date, not yet loggable'**
  String get calendarCellFuture;

  /// Screen-reader fragment marking a past calendar cell whose day sheet opens read-only (viewer role).
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get calendarCellReadOnly;

  /// Screen-reader fragment for a forecast bleed day — deliberately distinct from any logged-day fragment so predicted and logged never sound alike.
  ///
  /// In en, this message translates to:
  /// **'predicted period day'**
  String get calendarCellPredictedPeriod;

  /// Screen-reader fragment for a predicted bleed day's cycle-day numeral.
  ///
  /// In en, this message translates to:
  /// **'cycle day {day}'**
  String calendarCellCycleDay(int day);

  /// Screen-reader fragment for a non-bleed future day counted within the first predicted cycle.
  ///
  /// In en, this message translates to:
  /// **'cycle day {day} of the first predicted cycle'**
  String calendarCellCycleDayFirstCycle(int day);

  /// Screen-reader fragment for a day carrying the PMS badge.
  ///
  /// In en, this message translates to:
  /// **'predicted premenstrual window'**
  String get calendarCellPmsWindow;

  /// Screen-reader fragment for a day carrying the cramps badge.
  ///
  /// In en, this message translates to:
  /// **'predicted cramps window'**
  String get calendarCellCrampsWindow;

  /// Screen-reader fragment for a future day whose forecast cell carries no marker.
  ///
  /// In en, this message translates to:
  /// **'no prediction for this date'**
  String get calendarCellNoPrediction;

  /// Tooltip on the month/year picker's back-year chevron.
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get monthPickerPreviousYear;

  /// Tooltip on the month/year picker's forward-year chevron.
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get monthPickerNextYear;

  /// Future-day explainer body when no estimate exists at all.
  ///
  /// In en, this message translates to:
  /// **'No estimates yet — keep logging. Predicted bands appear on the calendar once a few cycles are recorded.'**
  String get futureExplainerNoEstimate;

  /// Future-day explainer body when nothing is predicted for the date.
  ///
  /// In en, this message translates to:
  /// **'No prediction for this date. Days can be logged once they arrive.'**
  String get futureExplainerNone;

  /// Future-day explainer body for a predicted bleed day with no cycle-day numeral.
  ///
  /// In en, this message translates to:
  /// **'Predicted period day. The date may shift by about {count} {count, plural, =1{day} other{days}} either way as new periods are logged.'**
  String futureExplainerBand(int count);

  /// Future-day explainer body for a predicted bleed day inside the first predicted cycle.
  ///
  /// In en, this message translates to:
  /// **'Predicted period day — cycle day {day} of the first predicted cycle. The date may shift by about {count} {count, plural, =1{day} other{days}} either way as new periods are logged.'**
  String futureExplainerBandWithCycleDay(int day, int count);

  /// Future-day explainer body for a day in the predicted PMS window.
  ///
  /// In en, this message translates to:
  /// **'Inside the predicted premenstrual window — symptoms like mood shifts and bloating often show up in the week before a period.'**
  String get futureExplainerPms;

  /// Future-day explainer body for a day in the predicted cramps window.
  ///
  /// In en, this message translates to:
  /// **'Inside the predicted cramps window — cramps commonly occur within two days of a period start.'**
  String get futureExplainerCramps;

  /// Future-day explainer body for a counted future cycle day that is not a predicted bleed day.
  ///
  /// In en, this message translates to:
  /// **'Cycle day {day} of the first predicted cycle. Only the first predicted cycle is counted day by day — estimates compound too much further out.'**
  String futureExplainerNumeral(int day);

  /// Future-day explainer confidence line, e.g. 'Estimate confidence: high.'.
  ///
  /// In en, this message translates to:
  /// **'Estimate confidence: {tier}.'**
  String futureExplainerConfidence(String tier);

  /// Day sheet flow chip label for no flow.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get flowLevelNone;

  /// Day sheet flow chip label for spotting.
  ///
  /// In en, this message translates to:
  /// **'Spotting'**
  String get flowLevelSpotting;

  /// Day sheet flow chip label for light flow.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get flowLevelLight;

  /// Day sheet flow chip label for medium flow.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get flowLevelMedium;

  /// Day sheet flow chip label for heavy flow.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get flowLevelHeavy;

  /// Day sheet flow chip label for an explicit no-bleed assertion (issue #247).
  ///
  /// In en, this message translates to:
  /// **'Not bleeding'**
  String get flowLevelNotBleeding;

  /// Day sheet flow chip label for super-heavy flow (issue #247).
  ///
  /// In en, this message translates to:
  /// **'Super heavy'**
  String get flowLevelSuperHeavy;

  /// Title of the day entry delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get daySheetDeleteTitle;

  /// Body of the day entry delete confirmation dialog; {date} is an ISO date string.
  ///
  /// In en, this message translates to:
  /// **'The entry for {date} is removed from the calendar.'**
  String daySheetDeleteBody(String date);

  /// Cancel action of the day entry delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get daySheetCancel;

  /// Confirm action of the day entry delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get daySheetDelete;

  /// Day sheet body when opened for a future date.
  ///
  /// In en, this message translates to:
  /// **'Future dates can\'t be logged.'**
  String get daySheetFutureDate;

  /// Label of the day sheet's free-text note field.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get daySheetNoteLabel;

  /// Inline retry error shown when a day entry save fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save — try again'**
  String get daySheetSaveError;

  /// Inline retry error shown when a day entry delete fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete — try again'**
  String get daySheetDeleteError;

  /// Tooltip on the day sheet's delete affordance.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get daySheetDeleteTooltip;

  /// The day sheet's save button label.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get daySheetSave;

  /// No description provided for @daySheetDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get daySheetDiscardTitle;

  /// No description provided for @daySheetKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get daySheetKeepEditing;

  /// No description provided for @daySheetDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get daySheetDiscard;

  /// No description provided for @daySheetSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get daySheetSaving;

  /// No description provided for @daySheetSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get daySheetSaved;

  /// No description provided for @daySheetRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Changes are kept — retry or close.'**
  String get daySheetRetryHint;

  /// Heading above inert chips for tags this build does not recognise.
  ///
  /// In en, this message translates to:
  /// **'Unrecognised'**
  String get daySheetUnrecognised;

  /// Caption under a taxonomy category whose option set is not yet attested (issue #249): the category exists but ships no options until a real Clue export pins them.
  ///
  /// In en, this message translates to:
  /// **'Unverified — pin before shipping'**
  String get daySheetUnverifiedPin;

  /// Read-only day sheet body when the day has no entry.
  ///
  /// In en, this message translates to:
  /// **'No entry for this day.'**
  String get daySheetNoEntry;

  /// Heading above the flow value in the read-only day sheet.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get daySheetFlowLabel;

  /// Heading above the tag chips in the read-only day sheet.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get daySheetTagsLabel;

  /// Placeholder shown for an empty note in the read-only day sheet.
  ///
  /// In en, this message translates to:
  /// **'No note'**
  String get daySheetNoNote;

  /// Confidence-tier label: steady recent cycles (issue #213). Character-identical to CycleConfidence.high's domain label it replaces in rendered copy.
  ///
  /// In en, this message translates to:
  /// **'High confidence'**
  String get cycleConfidenceHigh;

  /// Confidence-tier label: still building history (issue #213).
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get cycleConfidenceLearning;

  /// Confidence-tier label: cycles vary a lot (issue #213).
  ///
  /// In en, this message translates to:
  /// **'Irregular'**
  String get cycleConfidenceIrregular;

  /// Confidence-tier label: estimate seeded from onboarding answers, not logged history (issue #218).
  ///
  /// In en, this message translates to:
  /// **'Provisional'**
  String get cycleConfidenceProvisional;

  /// Confidence-tier summary under a high-confidence estimate. Matches CycleConfidence.high.summary exactly.
  ///
  /// In en, this message translates to:
  /// **'Recent cycles are steady — estimates are at their most reliable.'**
  String get cycleConfidenceSummaryHigh;

  /// Confidence-tier summary under a learning estimate. Matches CycleConfidence.learning.summary exactly.
  ///
  /// In en, this message translates to:
  /// **'Still learning — estimates improve after a few more cycles.'**
  String get cycleConfidenceSummaryLearning;

  /// Confidence-tier summary under an irregular estimate. Matches CycleConfidence.irregular.summary exactly.
  ///
  /// In en, this message translates to:
  /// **'Cycles vary a lot — treat estimates as rough guides.'**
  String get cycleConfidenceSummaryIrregular;

  /// Confidence-tier summary under a provisional (onboarding-seeded) estimate (issue #218). Matches CycleConfidence.provisional.summary exactly.
  ///
  /// In en, this message translates to:
  /// **'Based on your onboarding answers — estimates improve once real cycles are logged.'**
  String get cycleConfidenceSummaryProvisional;

  /// Link from the overview panel to the Insights cycle history.
  ///
  /// In en, this message translates to:
  /// **'See cycle history'**
  String get overviewSeeHistory;

  /// Snackbar confirming the today card's quick-log action.
  ///
  /// In en, this message translates to:
  /// **'Recorded a medium-flow period start for today.'**
  String get overviewLoggedSnackbar;

  /// Snackbar action undoing the today card's quick log.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get overviewUndo;

  /// Snackbar confirming the long-cycle exclude action.
  ///
  /// In en, this message translates to:
  /// **'This cycle is excluded from future averages.'**
  String get overviewExcludedSnackbar;

  /// Title of the overview's unusually-long-cycle prompt.
  ///
  /// In en, this message translates to:
  /// **'This cycle is unusually long'**
  String get overviewLongCycleTitle;

  /// Body of the overview's unusually-long-cycle prompt.
  ///
  /// In en, this message translates to:
  /// **'It has run well past a typical cycle for this profile. You can exclude it from future averages, or turn off predictions if long cycles are common for this profile.'**
  String get overviewLongCycleBody;

  /// Action excluding the open cycle from future averages.
  ///
  /// In en, this message translates to:
  /// **'Exclude this cycle'**
  String get overviewLongCycleExclude;

  /// Disabled placeholder action for turning predictions off (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Turn off predictions (coming soon)'**
  String get overviewLongCyclePredictionsOff;

  /// Hint line shown when notification permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Reminders unavailable — notifications are off'**
  String get overviewReminderHint;

  /// Action on the denied-permission reminder hint.
  ///
  /// In en, this message translates to:
  /// **'Turn on reminders'**
  String get overviewTurnOnReminders;

  /// The overview wheel's centre label mid-cycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle day {day}'**
  String cycleWheelCenterCycleDay(int day);

  /// The overview wheel's centre label during a logged bleed episode.
  ///
  /// In en, this message translates to:
  /// **'Period · day {day}'**
  String cycleWheelCenterPeriodDay(int day);

  /// The phase half of the overview wheel's screen-reader label during a bleed episode.
  ///
  /// In en, this message translates to:
  /// **'Period, day {day}'**
  String cycleWheelPhasePeriodDay(int day);

  /// The overview wheel's screen-reader label; {phase} is a cycleWheelCenter*/cycleWheelPhase* fragment.
  ///
  /// In en, this message translates to:
  /// **'{phase} of about {cycleDays} days. Period usually runs about {periodDays} days.'**
  String cycleWheelSemanticsBody(String phase, int cycleDays, int periodDays);

  /// The settings screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings tile opening the in-app feedback form.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get settingsSendFeedback;

  /// Subtitle of the send-feedback tile.
  ///
  /// In en, this message translates to:
  /// **'Report a bug, ask a question, or share an idea'**
  String get settingsSendFeedbackSubtitle;

  /// Settings tile (and dialog title) for the email support fallback.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get settingsContactSupport;

  /// Subtitle of the contact-support tile.
  ///
  /// In en, this message translates to:
  /// **'Email us with a bug or question'**
  String get settingsContactSupportSubtitle;

  /// Body of the contact-support dialog, above the address.
  ///
  /// In en, this message translates to:
  /// **'Email us with a bug report, question, or idea:'**
  String get settingsContactSupportDialogBody;

  /// Settings tile opening past feedback conversations.
  ///
  /// In en, this message translates to:
  /// **'Support history'**
  String get settingsSupportHistory;

  /// Subtitle of the support-history tile.
  ///
  /// In en, this message translates to:
  /// **'See replies and continue a conversation'**
  String get settingsSupportHistorySubtitle;

  /// Settings switch controlling the inactivity auto-relock.
  ///
  /// In en, this message translates to:
  /// **'Relock after inactivity'**
  String get settingsRelockTitle;

  /// Subtitle of the inactivity auto-relock switch.
  ///
  /// In en, this message translates to:
  /// **'Locks the app after 2 minutes without input. Backgrounding relocks immediately. A sign-in or unlock prompt this app opened is the one exception: the app stays covered while it is on screen, and relocks as soon as it closes if you have left.'**
  String get settingsRelockSubtitle;

  /// Section header above the health-sync settings tile.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get settingsHealthHeader;

  /// Settings tile opening per-profile Health app sync.
  ///
  /// In en, this message translates to:
  /// **'Health app sync'**
  String get settingsHealthSyncTitle;

  /// Subtitle of the health-sync tile.
  ///
  /// In en, this message translates to:
  /// **'Choose which profile\'s data may sync to this phone\'s Health app'**
  String get settingsHealthSyncSubtitle;

  /// Settings tile opening the in-app privacy policy dialog.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacyTitle;

  /// Subtitle of the privacy policy tile.
  ///
  /// In en, this message translates to:
  /// **'Sync & family sharing, protected at rest, zero tracking'**
  String get settingsPrivacySubtitle;

  /// Title of the in-app privacy policy dialog.
  ///
  /// In en, this message translates to:
  /// **'LunarLog Privacy Policy'**
  String get settingsPrivacyDialogTitle;

  /// Body of the in-app privacy policy dialog; mirrors PRIVACY.md's summary.
  ///
  /// In en, this message translates to:
  /// **'LunarLog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind biometric authentication.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Caregiver Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md'**
  String get settingsPrivacyDialogBody;

  /// Close action of the settings dialogs.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsClose;

  /// Headline of the first onboarding card (identity/value).
  ///
  /// In en, this message translates to:
  /// **'A private cycle log for your family'**
  String get firstRunValueHeadline;

  /// Body of the identity/value card: the differentiators stated plainly (family co-management, offline-first, no ads/tracking, no paywalled predictions).
  ///
  /// In en, this message translates to:
  /// **'Guardians can share a profile and log it together. Everything works offline. No ads, no data selling, no behavioral tracking — and predictions are never paywalled.'**
  String get firstRunValueBody;

  /// Title of the second onboarding card (what a profile and a guardian are).
  ///
  /// In en, this message translates to:
  /// **'Profiles and guardians'**
  String get firstRunGuardiansTitle;

  /// Body of the profiles/guardians card.
  ///
  /// In en, this message translates to:
  /// **'Each profile holds one person\'s cycle log. After signing in, you can invite another guardian — a co-parent or caregiver — to view or help log it.'**
  String get firstRunGuardiansBody;

  /// Heading of the minor-checkbox explanation inside the second onboarding card.
  ///
  /// In en, this message translates to:
  /// **'About the minor checkbox'**
  String get firstRunMinorExplainerTitle;

  /// The truthful explanation of what 'This profile is for a minor' changes (#131 made mode chosen-not-derived; the health-sync binding is the one real gate).
  ///
  /// In en, this message translates to:
  /// **'It\'s a label with one real effect today: the profile is kept out of this phone\'s Health app sync. It doesn\'t restrict anything else — wording and reminders come from the care mode picked on the next screen, not from this checkbox.'**
  String get firstRunMinorExplainerBody;

  /// The third onboarding card: today's data/sync notice, kept verbatim from the pre-#216 first run (the #334 repositioned copy).
  ///
  /// In en, this message translates to:
  /// **'Signing in syncs this profile across your devices and lets you share it with other guardians. Until then, everything you log stays on this device.'**
  String get firstRunNoticeBody;

  /// Advance-one-card button on the onboarding cards.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get firstRunNext;

  /// Skip button on the onboarding cards; skips the whole introduction.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get firstRunSkip;

  /// Advance button on the data/sync notice card (today's label, kept).
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get firstRunUnderstand;

  /// App bar title of the first-run name form and cycle-questions steps.
  ///
  /// In en, this message translates to:
  /// **'Create a profile'**
  String get firstRunCreateTitle;

  /// Label of the profile display-name field in the first-run form.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get firstRunNameLabel;

  /// The minor checkbox label in the first-run form (kept from the pre-#216 form).
  ///
  /// In en, this message translates to:
  /// **'This profile is for a minor'**
  String get firstRunMinorLabel;

  /// One-line hint under the minor checkbox in the first-run form.
  ///
  /// In en, this message translates to:
  /// **'A label with one effect: this profile is kept out of this phone\'s Health app sync.'**
  String get firstRunMinorHint;

  /// Label above the care-mode dropdown in the first-run form (kept).
  ///
  /// In en, this message translates to:
  /// **'Care mode'**
  String get firstRunCareModeLabel;

  /// Submit button of the first-run name form; validates and moves to the cycle questions.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get firstRunContinue;

  /// Caption at the top of the cycle-questions step; states skippability and (truthfully, for the two persisted answers) later editability.
  ///
  /// In en, this message translates to:
  /// **'A few optional questions to set this profile up — every one can be skipped. The goal and birth-control answers can be changed later when editing the profile.'**
  String get firstRunCycleCaption;

  /// Label of the last-period-start question.
  ///
  /// In en, this message translates to:
  /// **'Last period start'**
  String get firstRunCycleLastPeriodLabel;

  /// Button opening the last-period-start date picker when no date is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get firstRunCycleChooseDate;

  /// Button re-opening the last-period-start date picker once a date is chosen.
  ///
  /// In en, this message translates to:
  /// **'Change date'**
  String get firstRunCycleChangeDate;

  /// Button clearing the chosen last-period-start date (skips the question).
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get firstRunCycleClearDate;

  /// Label of the typical-cycle-length question.
  ///
  /// In en, this message translates to:
  /// **'Typical cycle length (days)'**
  String get firstRunCycleTypicalCycleLabel;

  /// Hint inside the typical-cycle-length field.
  ///
  /// In en, this message translates to:
  /// **'e.g. 28'**
  String get firstRunCycleTypicalCycleHint;

  /// Label of the typical-period-length question.
  ///
  /// In en, this message translates to:
  /// **'Typical period length (days)'**
  String get firstRunCycleTypicalPeriodLabel;

  /// Hint inside the typical-period-length field.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5'**
  String get firstRunCycleTypicalPeriodHint;

  /// Validation error for an out-of-range typical cycle length.
  ///
  /// In en, this message translates to:
  /// **'Enter a number between 10 and 90'**
  String get firstRunCycleLengthRangeError;

  /// Validation error for an out-of-range typical period length.
  ///
  /// In en, this message translates to:
  /// **'Enter a number between 1 and 14'**
  String get firstRunPeriodLengthRangeError;

  /// Label of the birth-control-method question.
  ///
  /// In en, this message translates to:
  /// **'Birth-control method'**
  String get firstRunCycleBirthControlLabel;

  /// Label of the goal/life-stage-mode question.
  ///
  /// In en, this message translates to:
  /// **'Goal / mode'**
  String get firstRunCycleGoalLabel;

  /// Final button of the cycle-questions step; creates the profile (today's label, kept).
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get firstRunCreateButton;

  /// Label above the life-stage-mode dropdown in the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Life-stage mode'**
  String get lifeStageModeLabel;

  /// Birth-control selector option meaning the question was skipped; stores nothing.
  ///
  /// In en, this message translates to:
  /// **'Not answered'**
  String get birthControlNotAnswered;

  /// Birth-control selector option: no method in use.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get birthControlNone;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get birthControlPill;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Hormonal IUD'**
  String get birthControlHormonalIud;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Copper IUD'**
  String get birthControlCopperIud;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Implant'**
  String get birthControlImplant;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Injection'**
  String get birthControlInjection;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Vaginal ring'**
  String get birthControlRing;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Patch'**
  String get birthControlPatch;

  /// Birth-control selector option.
  ///
  /// In en, this message translates to:
  /// **'Condom'**
  String get birthControlCondom;

  /// Birth-control selector option for a method not listed.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get birthControlOther;

  /// Day-sheet toggle for the first-class PMS marker (Issue #220) — deliberately not one of the taxonomy chips, mirroring Clue's own separation of the PMS phase from the individual symptoms that may co-occur with it.
  ///
  /// In en, this message translates to:
  /// **'PMS'**
  String get daySheetPmsChip;

  /// Accessibility group label for the day-sheet PMS toggle (Issue #220).
  ///
  /// In en, this message translates to:
  /// **'PMS'**
  String get daySheetPmsGroup;

  /// Overview line naming the predicted PMS band (Issue #220); range is the localized start-end date span. Only rendered once at least three PMS intervals have been logged.
  ///
  /// In en, this message translates to:
  /// **'Predicted PMS: {range}'**
  String overviewPmsBandLabel(String range);

  /// Overview copy under the predicted PMS band stating the 6-cycle averages behind it (Issue #220).
  ///
  /// In en, this message translates to:
  /// **'usually starts about {days} days before your period and lasts about {length} days'**
  String overviewPmsDaysBeforePeriod(int days, int length);

  /// Reminder settings header for the cycle reminders group (Issue #178), matching Clue's information architecture.
  ///
  /// In en, this message translates to:
  /// **'Your cycle'**
  String get reminderSectionCycle;

  /// Reminder settings header for the birth-control reminders group (Issue #178), matching Clue's information architecture.
  ///
  /// In en, this message translates to:
  /// **'Your birth control'**
  String get reminderSectionBirthControl;

  /// Reminder settings header for the other-reminders group (Issue #178), matching Clue's information architecture.
  ///
  /// In en, this message translates to:
  /// **'Other reminders'**
  String get reminderSectionOther;

  /// The period-starting-soon reminder's settings row title (Issue #178; Clue catalogue item 1).
  ///
  /// In en, this message translates to:
  /// **'Period starting soon'**
  String get reminderKindPeriodStartingSoon;

  /// The period-starting-soon reminder's settings row subtitle (Issue #178).
  ///
  /// In en, this message translates to:
  /// **'An earlier heads-up than the due reminder'**
  String get reminderKindPeriodStartingSoonSubtitle;

  /// The period-due reminder's settings row title (the existing upcoming kind, now localized; Issue #178).
  ///
  /// In en, this message translates to:
  /// **'Period due'**
  String get reminderKindPeriodDue;

  /// The period-due reminder's settings row subtitle (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'A heads-up before the predicted period starts'**
  String get reminderKindPeriodDueSubtitle;

  /// The PMS-watch reminder's settings row title (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'PMS watch'**
  String get reminderKindPmsWatch;

  /// The PMS-watch reminder's settings row subtitle (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'An earlier heads-up for pre-period days'**
  String get reminderKindPmsWatchSubtitle;

  /// The late-window reminder's settings row title (Issue #178 localization, aligned with Clue's 'Period late' naming).
  ///
  /// In en, this message translates to:
  /// **'Period late'**
  String get reminderKindPeriodLate;

  /// The late-window reminder's settings row subtitle (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'A daily nudge while the cycle runs late'**
  String get reminderKindPeriodLateSubtitle;

  /// The fertile-window-soon reminder's settings row title (Issue #178; Clue catalogue item 4).
  ///
  /// In en, this message translates to:
  /// **'Fertile window soon'**
  String get reminderKindFertileWindowSoon;

  /// The fertile-window-soon reminder's settings row subtitle (Issue #178).
  ///
  /// In en, this message translates to:
  /// **'A heads-up before the predicted fertile window'**
  String get reminderKindFertileWindowSoonSubtitle;

  /// The cycle-statistic-change reminder's settings row title (Issue #178; Clue catalogue item 5).
  ///
  /// In en, this message translates to:
  /// **'Cycle statistic changes'**
  String get reminderKindCycleStats;

  /// The cycle-statistic-change reminder's settings row subtitle (Issue #178).
  ///
  /// In en, this message translates to:
  /// **'A note when your displayed averages shift meaningfully'**
  String get reminderKindCycleStatsSubtitle;

  /// The daily log nudge's settings row title (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'Daily log nudge'**
  String get reminderKindLogNudge;

  /// The daily log nudge's settings row subtitle (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'A daily prompt to log the day'**
  String get reminderKindLogNudgeSubtitle;

  /// Lead-days row title for the period-anchored reminder types (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'Days before predicted start'**
  String get reminderLeadDaysBeforeStart;

  /// Lead-days row title for the PMS-watch reminder (Issue #178 localization of the existing copy).
  ///
  /// In en, this message translates to:
  /// **'Days before predicted PMS window'**
  String get reminderLeadDaysBeforePms;

  /// Lead-days row title for the fertile-window-soon reminder (Issue #178).
  ///
  /// In en, this message translates to:
  /// **'Days before predicted fertile window'**
  String get reminderLeadDaysBeforeFertileWindow;

  /// The disabled birth-control reminders placeholder row title (Issue #178; the reminder itself is issue #183's scope).
  ///
  /// In en, this message translates to:
  /// **'Birth-control reminders'**
  String get reminderBirthControlTitle;

  /// The disabled birth-control reminders placeholder row subtitle (Issue #178).
  ///
  /// In en, this message translates to:
  /// **'Coming in a future update'**
  String get reminderBirthControlComingSoon;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
