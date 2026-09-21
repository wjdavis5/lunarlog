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

  /// InlineError message (announced as a screen-reader live region) when the calendar's prediction stream errors. Issue #602.
  ///
  /// In en, this message translates to:
  /// **'Could not load the cycle estimate.'**
  String get cyclePredictionLoadError;

  /// InlineError message (announced as a screen-reader live region) when a cycle-history stream errors. Shared by the calendar's history badge (MonthCalendar) and CycleHistorySection, since both show the same failure for the same underlying stream shape. Issue #602.
  ///
  /// In en, this message translates to:
  /// **'Could not load cycle history.'**
  String get cycleHistoryLoadError;

  /// Issue #816: subtitle on the cycle-history list's open ('Current cycle') row, making it visible that the in-progress cycle is not part of the completed-cycle tally shown in the section header. Replaced by a skip-specific subtitle when the open cycle is omitted.
  ///
  /// In en, this message translates to:
  /// **'Not counted yet — your next period completes it'**
  String get cycleHistoryOpenCycleNotCounted;

  /// Issue #235: CycleHistorySection's header button that enters selection mode, letting the operator pick exactly two cycles to compare side by side.
  ///
  /// In en, this message translates to:
  /// **'Compare cycles'**
  String get cycleComparisonToggleButton;

  /// Issue #235: replaces cycleComparisonToggleButton while cycle-comparison selection mode is active, exiting it and clearing the current selection.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cycleComparisonCancelButton;

  /// Issue #235: selection-mode progress hint in the cycle-history list ("0 of 2 selected", "1 of 2 selected", "2 of 2 selected") -- always exactly two are required, so this is a bare count, not a pluralized noun.
  ///
  /// In en, this message translates to:
  /// **'{count} of 2 selected'**
  String cycleComparisonSelectedCount(int count);

  /// Issue #235: the button that opens the comparison screen once exactly two cycles are selected; disabled otherwise.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get cycleComparisonOpenButton;

  /// Issue #235: accessibility label on a completed cycle's selection checkbox in the cycle-history list, naming what the checkbox is for (a bare Checkbox otherwise announces only checked/unchecked state).
  ///
  /// In en, this message translates to:
  /// **'Select cycle starting {date} for comparison'**
  String cycleComparisonSelectCycleSemantic(String date);

  /// Issue #235: same as cycleComparisonSelectCycleSemantic, for the still-open cycle's own selection checkbox.
  ///
  /// In en, this message translates to:
  /// **'Select current cycle for comparison'**
  String get cycleComparisonSelectCurrentCycleSemantic;

  /// Issue #235: app-bar title of the side-by-side cycle comparison screen.
  ///
  /// In en, this message translates to:
  /// **'Compare cycles'**
  String get cycleComparisonScreenTitle;

  /// Issue #235: honest empty-state title when the comparison screen has no valid pair of cycles to show (e.g. reached with a stale selection).
  ///
  /// In en, this message translates to:
  /// **'Nothing to compare yet'**
  String get cycleComparisonNotEnoughTitle;

  /// Issue #235: body copy paired with cycleComparisonNotEnoughTitle.
  ///
  /// In en, this message translates to:
  /// **'Select two cycles from your cycle history to compare them side by side.'**
  String get cycleComparisonNotEnoughBody;

  /// Issue #235: header above a completed cycle's column in the comparison screen.
  ///
  /// In en, this message translates to:
  /// **'Cycle starting {date}'**
  String cycleComparisonSideHeading(String date);

  /// Issue #235: header above the still-open cycle's column in the comparison screen, when one side of the comparison is the open cycle.
  ///
  /// In en, this message translates to:
  /// **'Current cycle (started {date})'**
  String cycleComparisonCurrentCycleHeading(String date);

  /// Issue #235 AC4: marks a compared cycle that is in the operator's cycle_overrides exclusion set, so an excluded cycle reads as excluded within the comparison rather than being silently included as if it were a normal one.
  ///
  /// In en, this message translates to:
  /// **'Excluded from averages'**
  String get cycleComparisonExcludedBadge;

  /// Issue #235: row label above a compared cycle's length (rendered as a day count, or cycleComparisonOngoingLabel for the open cycle).
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get cycleComparisonLengthLabel;

  /// Issue #235: the still-open cycle's length value, replacing a day count it does not have yet.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get cycleComparisonOngoingLabel;

  /// Issue #235: row label above a compared cycle's logged bleed-day count (so far, for the open cycle).
  ///
  /// In en, this message translates to:
  /// **'Bleed days'**
  String get cycleComparisonBleedDaysLabel;

  /// Issue #235: label for the compared statistic showing how many days the two cycle lengths differ by (an unsigned day count -- this view names both cycles by their own start date above it rather than by "longer"/"shorter" wording).
  ///
  /// In en, this message translates to:
  /// **'Length difference'**
  String get cycleComparisonLengthDifferenceLabel;

  /// Issue #235: same as cycleComparisonLengthDifferenceLabel, for the bleed-day count difference.
  ///
  /// In en, this message translates to:
  /// **'Bleed days difference'**
  String get cycleComparisonBleedDaysDifferenceLabel;

  /// Issue #235: replaces the length-difference value whenever either compared cycle is still open (its final length isn't known yet, so no difference can be stated).
  ///
  /// In en, this message translates to:
  /// **'Not yet known'**
  String get cycleComparisonLengthDifferenceUnknown;

  /// Issue #235: the shared cycle-day label each aligned row starts with ("Day 1", "Day 2", ...), and the leading fragment of that row's accessibility label for each side.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String cycleComparisonDayHeading(int day);

  /// Issue #235: a compared day within a cycle's own length that has no day entry logged at all (distinct from an explicit "not bleeding" assertion, and distinct from cycleComparisonCycleEndedLabel).
  ///
  /// In en, this message translates to:
  /// **'Not logged'**
  String get cycleComparisonNoEntryLabel;

  /// Issue #235: fills a side's cell past that cycle's own last day, when the two compared cycles differ in length -- text, not a blank cell or a bare dash, so the shorter cycle's end reads as a fact rather than missing data (R9/no information by colour alone).
  ///
  /// In en, this message translates to:
  /// **'Cycle ended'**
  String get cycleComparisonCycleEndedLabel;

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

  /// Hint text in the day sheet's free-text note field (issue #812), in the voice guide's register — an invitation, not an instruction.
  ///
  /// In en, this message translates to:
  /// **'Anything worth remembering about today?'**
  String get daySheetNoteHint;

  /// The day sheet's pinned affirmative control (issue #812). It dismisses the sheet only; autosave has already persisted the edit, so it never means "save".
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get daySheetDoneLabel;

  /// Inline retry error shown when a day entry save fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save — try again'**
  String get daySheetSaveError;

  /// Issue #923: the day sheet's save-error copy when the storage layer rejected the date as more than a day in the future (the shared #848 date-bounds policy), distinct from the generic daySheetSaveError so the cause is named and the rejection is never reported as a bug.
  ///
  /// In en, this message translates to:
  /// **'This day is more than a day in the future, so it can\'t be saved.'**
  String get daySheetSaveErrorFutureDate;

  /// Issue #923: the day sheet's save-error copy when the storage layer rejected the date as before the profile's birth year (the shared #848 date-bounds policy); points at the profile setting that fixes it.
  ///
  /// In en, this message translates to:
  /// **'This day is before the profile\'s birth year, so it can\'t be saved. Update the birth year in the profile\'s settings.'**
  String get daySheetSaveErrorBeforeBirthYear;

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

  /// Snackbar confirming a day entry was deleted, shown with an Undo action (issue #856).
  ///
  /// In en, this message translates to:
  /// **'Entry deleted.'**
  String get daySheetDeletedSnackbar;

  /// Snackbar action that restores a just-deleted day entry (issue #856), mirroring overviewUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get daySheetUndo;

  /// Issue #887: title of the confirmation shown when a flow-chip tap would start a new cycle earlier than the profile's history expects.
  ///
  /// In en, this message translates to:
  /// **'Start a new cycle?'**
  String get daySheetCycleStartDialogTitle;

  /// Issue #887: body of the early-cycle-start confirmation. {cycleDay} is the 1-based day in the cycle being closed ('cycle day 17'), {flow} the tapped bleed level's label, {cycleLength} the length the closed cycle would end up with (16 for a day-17 start).
  ///
  /// In en, this message translates to:
  /// **'This looks early — you\'re on cycle day {cycleDay}. Logging {flow} flow starts a new cycle, closes the current one after {cycleLength} days, and updates your averages and estimates. Spotting never starts a cycle.'**
  String daySheetCycleStartDialogBody(
    int cycleDay,
    String flow,
    int cycleLength,
  );

  /// Issue #887: the confirmation action — proceed with the flow log that starts the new cycle.
  ///
  /// In en, this message translates to:
  /// **'Start new cycle'**
  String get daySheetCycleStartConfirm;

  /// Issue #887: the alternative action — record the day as spotting (its own observation row), the mid-cycle bleed that never starts a cycle.
  ///
  /// In en, this message translates to:
  /// **'Log spotting instead'**
  String get daySheetCycleStartSpotting;

  /// Issue #887: snackbar shown when a day-sheet session changed the cycle-start set by starting a new cycle at the logged day; carries an Undo action restoring the pre-session entry.
  ///
  /// In en, this message translates to:
  /// **'New cycle started — history and estimates updated.'**
  String get daySheetCycleStartSnackbar;

  /// Issue #887: snackbar shown when a day-sheet session changed the cycle-start set without starting a cycle at the logged day (a cleared cycle-starting bleed, or a bridging edit); carries an Undo action restoring the pre-session entry.
  ///
  /// In en, this message translates to:
  /// **'Cycle history updated.'**
  String get daySheetCycleHistorySnackbar;

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

  /// Chip label for an imported datapoint whose stored raw payload could not be described (not JSON, or an empty object).
  ///
  /// In en, this message translates to:
  /// **'Unrecognised data'**
  String get daySheetUnmappedFallback;

  /// Heading above inert chips for datapoints an import kept as-is because they mapped to no field in this app.
  ///
  /// In en, this message translates to:
  /// **'Imported, not recognised'**
  String get daySheetUnmappedImported;

  /// Caption under a taxonomy category whose option set is not yet attested (issue #249): the category exists but ships no options until a real Clue export pins them.
  ///
  /// In en, this message translates to:
  /// **'Unverified — pin before shipping'**
  String get daySheetUnverifiedPin;

  /// Issue #234: visible hint text in CategoryPicker's search field above the tag chip grid.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get daySheetTagSearchHint;

  /// Issue #234: screen-reader label for CategoryPicker's search field (distinct from the shorter visible hint).
  ///
  /// In en, this message translates to:
  /// **'Search tags'**
  String get daySheetTagSearchSemanticsLabel;

  /// Issue #234: tooltip/semantics for the button that clears CategoryPicker's search text.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get daySheetTagSearchClearTooltip;

  /// Issue #234: heading above CategoryPicker's Recent row, seeded from the profile's most-used tags.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get daySheetTagRecentLabel;

  /// Issue #257: heading above the profile's custom-tag registry section in the tag picker.
  ///
  /// In en, this message translates to:
  /// **'Custom tags'**
  String get daySheetCustomTagsLabel;

  /// Issue #257: tooltip for the tag picker's custom-tags manage affordance (create, rename, retire).
  ///
  /// In en, this message translates to:
  /// **'Manage custom tags'**
  String get daySheetCustomTagsManageTooltip;

  /// Issue #257: empty-state note under the custom-tags heading when the profile has no live, non-retired custom tags.
  ///
  /// In en, this message translates to:
  /// **'None yet — tap manage to add one'**
  String get daySheetCustomTagsNone;

  /// Issue #257: title of the custom-tag manager sheet.
  ///
  /// In en, this message translates to:
  /// **'Custom tags'**
  String get customTagsSheetTitle;

  /// Issue #257: body copy in the manager sheet when the registry is empty.
  ///
  /// In en, this message translates to:
  /// **'No custom tags yet — add one below.'**
  String get customTagsEmptyList;

  /// Issue #257: visible hint in the manager sheet's create field.
  ///
  /// In en, this message translates to:
  /// **'New tag name'**
  String get customTagsAddHint;

  /// Issue #257: tooltip/semantics for the manager sheet's add button.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get customTagsAddTooltip;

  /// Issue #257: create-field error for an empty custom-tag label.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get customTagsErrorEmpty;

  /// Issue #257: create-field error for a label past the 40-character CHECK.
  ///
  /// In en, this message translates to:
  /// **'Names are at most 40 characters.'**
  String get customTagsErrorTooLong;

  /// Issue #257: create-field error for a label no code can be derived from (e.g. only punctuation).
  ///
  /// In en, this message translates to:
  /// **'Include a letter or digit.'**
  String get customTagsErrorNoLetters;

  /// Issue #257: create-field error for a label deriving a code another live registry entry already owns (case-insensitive).
  ///
  /// In en, this message translates to:
  /// **'You already have a tag like this.'**
  String get customTagsErrorDuplicate;

  /// Issue #257: create-field error for a label deriving a code the static taxonomy owns (shadowing it would make one chip mean two things).
  ///
  /// In en, this message translates to:
  /// **'That name is already a built-in tag.'**
  String get customTagsErrorTaxonomy;

  /// Issue #257: create-field error at the per-profile registry cap (100 live rows).
  ///
  /// In en, this message translates to:
  /// **'This profile already has {max} custom tags — retire one first.'**
  String customTagsErrorCap(int max);

  /// Issue #257: tooltip for a registry row's rename affordance.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get customTagsRenameTooltip;

  /// Issue #257: title of the rename dialog.
  ///
  /// In en, this message translates to:
  /// **'Rename tag'**
  String get customTagsRenameTitle;

  /// Issue #257: tooltip for a registry row's retire affordance (hidden_at — removed from the picker, never deleted).
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get customTagsRetireTooltip;

  /// Issue #257: status label on a retired registry row in the manager sheet.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get customTagsRetiredLabel;

  /// Issue #257: title of the retire confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Retire “{label}”?'**
  String customTagsRetireTitle(String label);

  /// Issue #257: body of the retire confirmation dialog — retirement never deletes stored entries.
  ///
  /// In en, this message translates to:
  /// **'It leaves the tag picker. Days that already use it keep showing it.'**
  String get customTagsRetireBody;

  /// Issue #257: confirm button of the retire dialog.
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get customTagsRetireConfirm;

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

  /// Issue #642, LLA-011: heading above the spotting marker in the read-only day sheet, mirroring daySheetPmsGroup's own label+value shape (the value line reuses flowLevelSpotting, the same 'Spotting' string the editable chip already shows).
  ///
  /// In en, this message translates to:
  /// **'Spotting'**
  String get daySheetSpottingGroup;

  /// Issue #642, LLA-011: shown in the read-only day sheet while spotting/pain-intensity (child `observations` rows, not on the day entry itself) are still loading.
  ///
  /// In en, this message translates to:
  /// **'Loading additional details…'**
  String get daySheetChildObservationsLoading;

  /// Issue #642, LLA-011: shown in the read-only day sheet when loading spotting/pain-intensity (child `observations` rows) fails. No exception detail, matching this file's other failure copy.
  ///
  /// In en, this message translates to:
  /// **'Could not load additional details.'**
  String get daySheetChildObservationsError;

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

  /// InlineError message (announced as a screen-reader live region) when OverviewPanel's prediction stream errors. Issue #602.
  ///
  /// In en, this message translates to:
  /// **'Could not load your cycle estimate.'**
  String get overviewEstimateLoadError;

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

  /// Action navigating to Settings to manage or turn off predictions (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Turn off predictions'**
  String get overviewLongCyclePredictionsOff;

  /// Issue #859: title of the overview card shown when the last logged period is far too old for predictions to mean anything.
  ///
  /// In en, this message translates to:
  /// **'Your history is out of date'**
  String get overviewStaleHistoryTitle;

  /// Issue #859: calm, non-alarming body of the stale-history overview card.
  ///
  /// In en, this message translates to:
  /// **'It has been a long time since you logged a period, so cycle estimates would not be reliable. Log a period when it starts to pick predictions back up. You can also turn predictions off.'**
  String get overviewStaleHistoryBody;

  /// Issue #859: primary action on the stale-history card, logging a period start for today.
  ///
  /// In en, this message translates to:
  /// **'Log a period'**
  String get overviewStaleHistoryLog;

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

  /// Label for the expandable section on the Today card explaining the estimate tier and PMS.
  ///
  /// In en, this message translates to:
  /// **'About this estimate'**
  String get overviewAboutThisEstimate;

  /// Button label on the Today card to quickly log that a period started today.
  ///
  /// In en, this message translates to:
  /// **'Period started today'**
  String get todayCardLogPeriodStartedToday;

  /// Error message shown on the Today card when recording today's entry fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record today\'s entry — try again.'**
  String get todayCardRecordEntryError;

  /// Unit label beneath the days-until count in the cycle wheel centre.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String cycleWheelDaysUntilUnit(int count);

  /// Unit label beneath the days-late count in the cycle wheel centre when overdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day late} other{days late}}'**
  String cycleWheelDaysLateUnit(int count);

  /// Issue #853: unit label beneath the overdue count in the cycle wheel centre when the composed irregular framing is in effect - names the estimate, never 'late'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day past estimate} other{days past estimate}}'**
  String cycleWheelDaysPastEstimateUnit(int count);

  /// Issue #853: the overview wheel's screen-reader label when overdue and the composed irregular framing is in effect - never says 'late'.
  ///
  /// In en, this message translates to:
  /// **'{daysPast, plural, =1{1 day past the estimate.} other{{daysPast} days past the estimate.}} Cycle day {cycleDay} of about {cycleDays} days. Period usually runs about {periodDays} days.'**
  String cycleWheelSemanticsPastEstimate(
    int daysPast,
    int cycleDay,
    int cycleDays,
    int periodDays,
  );

  /// Top line in the cycle wheel centre during a bleed episode.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String cycleWheelBleedDayHero(int day);

  /// Bottom line in the cycle wheel centre during a bleed episode.
  ///
  /// In en, this message translates to:
  /// **'of period'**
  String get cycleWheelBleedOfPeriod;

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

  /// The overview wheel's screen-reader label during a bleed episode.
  ///
  /// In en, this message translates to:
  /// **'Day {day} of period. Cycle of about {cycleDays} days. Period usually runs about {periodDays} days.'**
  String cycleWheelSemanticsBleed(int day, int cycleDays, int periodDays);

  /// The overview wheel's screen-reader label mid-cycle, leading with the days-until figure.
  ///
  /// In en, this message translates to:
  /// **'{daysUntil, plural, =1{About 1 day until next period.} other{About {daysUntil} days until next period.}} Cycle day {cycleDay} of about {cycleDays} days. Period usually runs about {periodDays} days.'**
  String cycleWheelSemanticsMidCycle(
    int daysUntil,
    int cycleDay,
    int cycleDays,
    int periodDays,
  );

  /// The overview wheel's screen-reader label when overdue.
  ///
  /// In en, this message translates to:
  /// **'{daysLate, plural, =1{1 day late.} other{{daysLate} days late.}} Cycle day {cycleDay} of about {cycleDays} days. Period usually runs about {periodDays} days.'**
  String cycleWheelSemanticsLate(
    int daysLate,
    int cycleDay,
    int cycleDays,
    int periodDays,
  );

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

  /// Subtitle of the inactivity auto-relock switch; {duration} is the selected timeout label (e.g. 1 hour).
  ///
  /// In en, this message translates to:
  /// **'Locks the app after {duration} without input. Backgrounding relocks immediately. A sign-in or unlock prompt this app opened is the one exception: the app stays covered while it is on screen, and relocks as soon as it closes if you have left.'**
  String settingsRelockSubtitle(String duration);

  /// Title of the relock-duration picker tile (issue #762).
  ///
  /// In en, this message translates to:
  /// **'Inactivity timeout'**
  String get settingsRelockTimeoutTitle;

  /// Relock-duration picker option: 2 minutes (issue #762).
  ///
  /// In en, this message translates to:
  /// **'2 minutes'**
  String get settingsRelockTimeout2Minutes;

  /// Relock-duration picker option: 15 minutes (issue #762).
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get settingsRelockTimeout15Minutes;

  /// Relock-duration picker option: 1 hour, the default (issue #762).
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get settingsRelockTimeout1Hour;

  /// Settings tile and picker-dialog title for the appearance override (issue #137).
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceTitle;

  /// Subtitle of the appearance tile, naming the three override options.
  ///
  /// In en, this message translates to:
  /// **'Follow your device\'s setting, or choose light or dark'**
  String get settingsAppearanceSubtitle;

  /// Picker option: use the OS light/dark setting (the default).
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get appearanceOptionSystem;

  /// Picker option: always use the light theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceOptionLight;

  /// Picker option: always use the dark theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceOptionDark;

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

  /// Android-only health-sync copy (Issue #238): Health Connect has no symptom category types, so symptom tags are never exported there. This documents the permanent platform limitation rather than hiding it.
  ///
  /// In en, this message translates to:
  /// **'Symptoms (cramps, headaches, mood, and more) can\'t be written to Health Connect — it has no symptom categories. Days logged with symptoms still sync their flow and spotting; the symptoms themselves stay in lunarlog.'**
  String get settingsHealthSyncSymptomsAndroidLimitation;

  /// Health sync screen OS-permission status line (Issue #959): the OS write permission for the platform's health store is granted. {source} is 'Apple Health' or 'Health Connect'.
  ///
  /// In en, this message translates to:
  /// **'{source} access: granted'**
  String healthSyncPermissionGranted(String source);

  /// Health sync screen OS-permission status line (Issue #959): the OS permission sheet has not been answered yet.
  ///
  /// In en, this message translates to:
  /// **'{source} access: not yet asked'**
  String healthSyncPermissionNotAsked(String source);

  /// Health sync screen OS-permission status line (Issue #959): the OS write permission was denied. Shown with the settings deep link.
  ///
  /// In en, this message translates to:
  /// **'{source} access: denied — open Settings to change'**
  String healthSyncPermissionDenied(String source);

  /// Health sync screen OS-permission status line (Issue #959): there is no health store or permission surface on this device.
  ///
  /// In en, this message translates to:
  /// **'{source} access is not available on this device.'**
  String healthSyncPermissionUnavailable(String source);

  /// The deep link offered on the health-sync status line only when the OS permission is denied (Issue #959).
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get healthSyncPermissionOpenSettings;

  /// Health import summary: days that gained or refreshed an imported flow value (Issues #217/#458).
  ///
  /// In en, this message translates to:
  /// **'Updated {count, plural, =1{1 day} other{{count} days}} from {source}.'**
  String healthSyncImportUpdatedDays(int count, String source);

  /// Health import summary: days that gained an imported spotting observation (Issue #458).
  ///
  /// In en, this message translates to:
  /// **'Added spotting to {count, plural, =1{1 day} other{{count} days}} from {source}.'**
  String healthSyncImportAddedSpotting(int count, String source);

  /// Health import summary: days already at the same imported value.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}} already matched.'**
  String healthSyncImportAlreadyMatched(int count);

  /// Health import summary: days whose hand-logged flow differed and was deliberately kept.
  ///
  /// In en, this message translates to:
  /// **'Kept your own logged value on {count, plural, =1{1 day} other{{count} days}}.'**
  String healthSyncImportKeptManual(int count);

  /// Health import summary (Issue #902): samples the source recorded no zone for, placed on a civil date from this phone's own offset. Deliberately says placed, never skipped, so an inferred date is not reported as one the source recorded.
  ///
  /// In en, this message translates to:
  /// **'Placed {count, plural, =1{1 sample} other{{count} samples}} using the time zone of this phone.'**
  String healthSyncImportPlacedDeviceZone(int count);

  /// Health import summary: samples that could not be placed at all (no zone and no device-zone fallback).
  ///
  /// In en, this message translates to:
  /// **'Skipped {count, plural, =1{1 sample} other{{count} samples}} with no recorded time zone.'**
  String healthSyncImportSkippedNoZone(int count);

  /// Health import summary: samples whose flow value has no lunarlog equivalent.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count, plural, =1{1 sample} other{{count} samples}} with no matching flow level.'**
  String healthSyncImportSkippedUnsupported(int count);

  /// Confirm dialog title for unbinding a health-sync profile (Issue #893), mirroring the bind confirmation.
  ///
  /// In en, this message translates to:
  /// **'Stop syncing {name} to this phone?'**
  String healthSyncUnbindDialogTitle(String name);

  /// Confirm dialog body for unbinding on a platform where both write and import are wired (iOS, Issue #893).
  ///
  /// In en, this message translates to:
  /// **'This phone will stop writing data for {name} to its Health app and stop importing from it. Nothing already logged in lunarlog, or already written to the Health app, is deleted.'**
  String healthSyncUnbindDialogWriteBody(String name);

  /// Confirm dialog body for unbinding on an import-only platform (Android, Issue #893).
  ///
  /// In en, this message translates to:
  /// **'This phone will stop importing data for {name} from its Health app. Nothing already logged is deleted.'**
  String healthSyncUnbindDialogImportBody(String name);

  /// Confirm action of the health-sync unbind dialog (Issue #893).
  ///
  /// In en, this message translates to:
  /// **'Stop syncing'**
  String get healthSyncUnbindConfirm;

  /// Cancel action of the health-sync unbind dialog (Issue #893).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get healthSyncUnbindCancel;

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
  /// **'lunarlog Privacy Policy'**
  String get settingsPrivacyDialogTitle;

  /// Body of the in-app privacy policy dialog; mirrors PRIVACY.md's summary.
  ///
  /// In en, this message translates to:
  /// **'lunarlog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind biometric authentication.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Minimum-Age Policy: Licensed for ages 13 and older; household profiles managed by adult guardians (18+).\n• Guardian Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md'**
  String get settingsPrivacyDialogBody;

  /// Close action of the settings dialogs.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsClose;

  /// Header of the Settings 'Your data' section (Issue #226): export, import, CSV/clinical export, purge.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get settingsSectionYourData;

  /// Settings 'Your data' tile that opens the on-device PDF clinician cycle summary export (Issue #154).
  ///
  /// In en, this message translates to:
  /// **'Export clinical summary (PDF)'**
  String get clinicalPdfExportTitle;

  /// Profile chooser dialog title shown before the PDF clinical summary export when several live profiles exist (Issue #154).
  ///
  /// In en, this message translates to:
  /// **'Export clinical summary for'**
  String get clinicalPdfExportForProfileTitle;

  /// Header of the Settings 'Appearance' section (Issue #226): the theme-mode picker.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// Tile title inside the Appearance section (Issue #226 retitled from 'Appearance' once the section header carried that word): opens the system/light/dark picker; the subtitle names the current mode.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// Header of the Settings 'Reminders' section (Issue #226): reminder scheduling and caregiver alert preferences.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsSectionReminders;

  /// Header of the Settings 'Calendar' section (Issue #226): week start, date format, predictions, measurement units.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get settingsSectionCalendar;

  /// Header of the Settings 'Home-screen widget' section (Issue #141): which profile the widget shows. iOS/Android only.
  ///
  /// In en, this message translates to:
  /// **'Home-screen widget'**
  String get settingsSectionHomeWidget;

  /// Tile title (Issue #141): which profile the home-screen widget renders; the subtitle names the current choice.
  ///
  /// In en, this message translates to:
  /// **'Widget profile'**
  String get settingsHomeWidgetProfileTitle;

  /// Picker option (Issue #141): the widget tracks whatever profile the app currently has open, instead of pinning one.
  ///
  /// In en, this message translates to:
  /// **'Follow the app\'s current profile'**
  String get settingsHomeWidgetFollowActive;

  /// Privacy disclosure under the picker (Issue #141): the discreet default render, the gated quick-log behavior, and the viewer-role exclusion.
  ///
  /// In en, this message translates to:
  /// **'The widget shows only a discreet state: a cycle-day count, never a name, a date, or flow details. When the profile is one you can log for, tapping it records a period started today — the entry applies only after you unlock the app, and logging it twice changes nothing. Profiles you can only view are not offered here.'**
  String get settingsHomeWidgetDisclosure;

  /// Header of the Settings 'Family & sharing' section (Issue #226/#126): one row per profile, routing to Manage Guardians.
  ///
  /// In en, this message translates to:
  /// **'Family & sharing'**
  String get settingsSectionFamilySharing;

  /// Header of the Settings 'Privacy & security' section (Issue #226): relock, app PIN, privacy policy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & security'**
  String get settingsSectionPrivacySecurity;

  /// Header of the Settings 'Help' section (Issue #226): help library, feedback/support, support history.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsSectionHelp;

  /// Header of the Settings 'About' section (Issue #226): version, build number, licences.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Tile (inside the Reminders section) opening the per-profile reminder configuration screen (Issue #136).
  ///
  /// In en, this message translates to:
  /// **'Reminder settings'**
  String get settingsReminderSettingsTitle;

  /// Subtitle of the reminder-settings tile.
  ///
  /// In en, this message translates to:
  /// **'Choose which reminders fire, when, and for whom'**
  String get settingsReminderSettingsSubtitle;

  /// Tile (inside the Reminders section, one per profile) opening the caregiver alert preferences screen (Issue #226 promoting it from Manage Guardians); the tile's subtitle is the profile's name.
  ///
  /// In en, this message translates to:
  /// **'Guardian alerts'**
  String get settingsCaregiverAlertsTitle;

  /// Calendar-section tile (Issue #226) choosing which day the month grid's weeks start on.
  ///
  /// In en, this message translates to:
  /// **'First day of week'**
  String get settingsFirstDayTitle;

  /// Week-start option: weeks start on Sunday (the historical default).
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get settingsFirstDaySunday;

  /// Week-start option: weeks start on Monday (ISO 8601).
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get settingsFirstDayMonday;

  /// Calendar-section tile (Issue #226) choosing the month/day order of compact dates.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get settingsDateFormatTitle;

  /// Date-format option: follow the locale's own month/day order (Issue #226). The example is resolved live from the active locale (issue #884) so it never advertises an order the device will not render.
  ///
  /// In en, this message translates to:
  /// **'System default ({example})'**
  String settingsDateFormatSystemOption(String example);

  /// Date-format option: day before month, e.g. '5 Sep'.
  ///
  /// In en, this message translates to:
  /// **'Day first (5 Sep)'**
  String get settingsDateFormatDayMonthOption;

  /// Date-format option: month before day, e.g. 'Sep 5'.
  ///
  /// In en, this message translates to:
  /// **'Month first (Sep 5)'**
  String get settingsDateFormatMonthDayOption;

  /// Tile (inside the Help section) opening the offline help library (Issue #139).
  ///
  /// In en, this message translates to:
  /// **'Help & explanations'**
  String get settingsHelpTitle;

  /// Subtitle of the help library tile.
  ///
  /// In en, this message translates to:
  /// **'Plain-language answers about estimates, logging, sync, and sharing — works offline'**
  String get settingsHelpSubtitle;

  /// About-section tile title (Issue #226); the subtitle carries the actual version and build number.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsAboutVersionTitle;

  /// The version line shown in Settings → About and on the licence page (Issue #226).
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {build})'**
  String settingsAboutVersion(String version, String build);

  /// Shown in place of the version line when the platform package-info read failed (Issue #226).
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get settingsAboutVersionUnavailable;

  /// About-section tile opening Flutter's licence page (Issue #226).
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsAboutLicensesTitle;

  /// Subtitle of the licences tile.
  ///
  /// In en, this message translates to:
  /// **'The packages and terms this app builds on'**
  String get settingsAboutLicensesSubtitle;

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

  /// The truthful explanation of what 'This profile is for a minor' changes (#131 made mode chosen-not-derived; #882 made health-sync apply to minors on the same terms as adults, so the checkbox is a label only).
  ///
  /// In en, this message translates to:
  /// **'It\'s a label used across the app to describe the profile. It doesn\'t restrict anything: health app sync is off for every profile by default and, when you turn it on, works the same way for any profile you choose — minors included. Wording and reminders come from the care mode picked on the next screen, not from this checkbox.'**
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

  /// One-line hint under the minor checkbox in the first-run form (#882: the checkbox no longer excludes a profile from health sync).
  ///
  /// In en, this message translates to:
  /// **'A label used across the app — health sync works the same for every profile.'**
  String get firstRunMinorHint;

  /// Checkbox label acknowledging the 13+ minimum-age statement on first-run profile creation.
  ///
  /// In en, this message translates to:
  /// **'I am 13 or older, or a guardian managing a family profile'**
  String get firstRunAgeAcknowledgementLabel;

  /// One-line hint under the minimum-age acknowledgement checkbox in the first-run form.
  ///
  /// In en, this message translates to:
  /// **'lunarlog requires users to be at least 13 years old, or managed by a parent or legal guardian.'**
  String get firstRunAgeAcknowledgementHint;

  /// Validation error shown when the minimum-age acknowledgement is not checked.
  ///
  /// In en, this message translates to:
  /// **'Please acknowledge the minimum-age policy to continue.'**
  String get firstRunAgeAcknowledgementRequired;

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

  /// Action on first run allowing user to restore profiles and cycle history from an existing backup or Clue export.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup or Clue export'**
  String get firstRunRestore;

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
  /// **'Enter a number between 15 and 60'**
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

  /// The household-setup question at the top of the first-run name form (issue #804). 'Me' is preselected, so today's single-profile path never answers it.
  ///
  /// In en, this message translates to:
  /// **'Who is this profile for?'**
  String get firstRunWhoLabel;

  /// Household-setup answer: the operator's own profile (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get firstRunWhoMe;

  /// Household-setup answer: a profile for a family member (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Someone I care for'**
  String get firstRunWhoSomeone;

  /// Household-setup answer: the operator's own profile plus family members (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get firstRunWhoBoth;

  /// Label above the relationship dropdown on a first-run card for someone other than the operator (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Relationship'**
  String get firstRunRelationshipLabel;

  /// Hint under the care-mode dropdown when Teen was preselected as a suggestion for a minor (issue #804; suggested, never forced — #131).
  ///
  /// In en, this message translates to:
  /// **'Teen mode is suggested for a minor — change it any time.'**
  String get firstRunTeenSuggestedHint;

  /// Caption on the shortened cycle step for a family member's profile: the last-period question only, visibly skippable (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Optional: if you know when her last period started, add it below. Not sure? Just continue.'**
  String get firstRunCycleShortCaption;

  /// Title of the household wrap-up step after a profile was created (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Add another person?'**
  String get firstRunWrapUpTitle;

  /// Body of the household wrap-up step; states that the loop is optional (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Everyone you set up now is ready to log. You can also add profiles later from the profile picker.'**
  String get firstRunWrapUpBody;

  /// Button looping back to a fresh person card on the household wrap-up step (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Add another person'**
  String get firstRunWrapUpAddAnother;

  /// Title of the first-run invite step (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Does someone else help?'**
  String get firstRunInviteTitle;

  /// Body of the first-run invite step; states skippability and the later path (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Invite a co-parent or a caregiver to any profile you just created. You can skip this and send invites later from Manage guardians.'**
  String get firstRunInviteBody;

  /// Shown on the invite step when there is no session: why an account is required here and only here (issue #804 AC3).
  ///
  /// In en, this message translates to:
  /// **'Invites travel through your lunarlog account so the link reaches the other person\'s device. Sign in or create an account to send one now.'**
  String get firstRunInviteWhyAccount;

  /// Button on the invite step opening the embedded sign-in screen (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Sign in or create account'**
  String get firstRunInviteSignInAction;

  /// Per-profile button opening the invite dialog with the guardian presets (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Invite a co-parent'**
  String get firstRunInviteCoParent;

  /// Button ending the household flow without any invite (issue #804; always available).
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get firstRunInviteSkip;

  /// Button ending the household flow after (possibly zero) invites (issue #804).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get firstRunInviteDone;

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

  /// Per-day pill-intake value (Issue #260): the dose was taken on time. Option strings are pending pre-ship verification against a real Clue export (A1-29); the stored wire value is the stable id 'taken', never this label.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get birthControlIntakeTaken;

  /// Per-day pill-intake value (Issue #260): the dose was taken late. Option strings are pending pre-ship verification against a real Clue export (A1-29); the stored wire value is the stable id 'late', never this label.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get birthControlIntakeLate;

  /// Per-day pill-intake value (Issue #260): the dose was missed. Option strings are pending pre-ship verification against a real Clue export (A1-29); the stored wire value is the stable id 'missed', never this label.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get birthControlIntakeMissed;

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

  /// Heading and accessibility group label for the graded 1-5 intensity selectors under a pain code in the day sheet (Issue #256). Clue grades each option inside its own option set; here the grade rides the option's observations row.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get daySheetIntensityGroup;

  /// The clear affordance on a pain-code intensity selector (Issue #256): removes the recorded intensity, leaving the row ungraded ('no severity recorded'), never 'low'.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get daySheetIntensityClear;

  /// Overview line naming the predicted PMS band and the 6-cycle averages behind it as one sentence (Issue #220; merged into one line by Issue #874). range is the localized start-end date span. Only rendered once at least three PMS intervals have been logged.
  ///
  /// In en, this message translates to:
  /// **'Predicted PMS: {range} — usually starts about {days} days before your period and lasts about {length} days.'**
  String overviewPmsBandLabel(String range, int days, int length);

  /// Overview line naming the predicted PMS band's confidence tier when it differs from the period estimate's own tier (Issue #874). The subject ('PMS estimate:') distinguishes it from the period estimate's tier caption above; the line is omitted entirely when the two tiers are equal, which is the common case.
  ///
  /// In en, this message translates to:
  /// **'PMS estimate: {tier}'**
  String overviewPmsTierLabel(String tier);

  /// Title of the overview/Analysis state shown when a profile's in-effect birth-control method is a continuous one (IUD, implant, shot, continuous pill): period prediction is deliberately off (Issue #233).
  ///
  /// In en, this message translates to:
  /// **'Predictions are suppressed'**
  String get predictionsSuppressedTitle;

  /// Body of the suppressed-prediction state naming the recorded continuous method ({method}) and explaining why predictions are off (Issue #233).
  ///
  /// In en, this message translates to:
  /// **'Because {method} typically stops or irregularly affects periods, period predictions are turned off while it is active. The method will resume ordinary prediction once it is switched or cleared.'**
  String predictionsSuppressedBody(String method);

  /// Body of the suppressed-prediction state naming the profile's current life-stage mode ({mode}: Pregnancy, Postpartum, or Perimenopause) and explaining why period predictions are off (Issue #528). Shares predictionsSuppressedTitle with the birth-control reason.
  ///
  /// In en, this message translates to:
  /// **'Because this profile is set to {mode} mode, period predictions are turned off — the ordinary cycle averages this app estimates from don\'t apply right now. Switch back to Period Tracking mode in profile settings to resume ordinary prediction.'**
  String predictionsSuppressedByModeBody(String mode);

  /// Title of the card displayed when predictions are disabled for the profile (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Predictions turned off'**
  String get predictionsDisabledTitle;

  /// Body of the card explaining that predictions are disabled while tracking remains active (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Estimates, calendar prediction bands, and prediction reminders are paused for this profile. Your cycle history and tracking continue unchanged.'**
  String get predictionsDisabledBody;

  /// Button on predictions-disabled card opening Settings (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Manage in Settings'**
  String get predictionsDisabledAction;

  /// Title of the prediction toggle in Settings when only one profile exists (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Show predictions'**
  String get settingsPredictionsTitle;

  /// Title of the prediction toggle in Settings for a specific profile (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Show predictions ({profileName})'**
  String settingsPredictionsProfileTitle(String profileName);

  /// Subtitle describing the predictions toggle in Settings (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Show cycle estimates, fertile window, and prediction reminders'**
  String get settingsPredictionsSubtitle;

  /// Subtitle of the settings predictions toggle when the profile's life-stage mode suppresses predictions ({mode}: Pregnancy, Postpartum, or Perimenopause); the toggle is disabled and the mode name comes from LifecycleMode.label, the same source the suppressed-prediction card uses (Issue #877).
  ///
  /// In en, this message translates to:
  /// **'Turned off by {mode} mode — change the life-stage mode to resume.'**
  String settingsPredictionsSuppressedByModeSubtitle(String mode);

  /// Subtitle of the settings predictions toggle when an active continuous birth-control method ({method}) suppresses predictions; the toggle is disabled and the method name comes from the shared birth-control picker vocabulary (Issue #877).
  ///
  /// In en, this message translates to:
  /// **'Turned off by {method} — change or clear the birth-control method to resume.'**
  String settingsPredictionsSuppressedByMethodSubtitle(String method);

  /// Title of the suggestion banner offered when cycle variation is irregular (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Cycles vary a lot'**
  String get overviewIrregularSuggestionTitle;

  /// Body of the dismissible suggestion banner for irregular cycles (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Predictions may be less useful when cycles vary widely. You can turn off cycle estimates while continuing to track normally.'**
  String get overviewIrregularSuggestionBody;

  /// Action on the irregular suggestion banner opening Settings (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Manage in Settings'**
  String get overviewIrregularSuggestionSettings;

  /// Action dismissing the irregular suggestion banner (issue #225).
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get overviewIrregularSuggestionDismiss;

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

  /// The birth-control reminders explainer row title, shown when the profile has no method-cadence reminder to configure (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Birth-control reminders'**
  String get reminderBirthControlTitle;

  /// The birth-control reminders explainer row subtitle (Issue #183): no adherence reminder applies because no tracked method is in effect (none recorded, a non-tracked answer, or an implant/IUD, which are not user-administered on a schedule).
  ///
  /// In en, this message translates to:
  /// **'Follows the birth-control method recorded in this profile\'s settings.'**
  String get reminderBirthControlFollowsMethod;

  /// The daily pill adherence reminder's settings row title (Issue #183; Clue's 'Your Birth Control' catalogue).
  ///
  /// In en, this message translates to:
  /// **'Pill reminder'**
  String get reminderKindBirthControlPill;

  /// The pill reminder's settings row subtitle (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Daily, at the chosen time'**
  String get reminderKindBirthControlPillSubtitle;

  /// The weekly patch-change reminder's settings row title (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Patch reminder'**
  String get reminderKindBirthControlPatch;

  /// The patch reminder's settings row subtitle (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Weekly, on change day'**
  String get reminderKindBirthControlPatchSubtitle;

  /// The monthly ring-change reminder's settings row title (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Ring reminder'**
  String get reminderKindBirthControlRing;

  /// The ring reminder's settings row subtitle (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Monthly, on change day'**
  String get reminderKindBirthControlRingSubtitle;

  /// The 12-weekly injection reminder's settings row title (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Injection reminder'**
  String get reminderKindBirthControlShot;

  /// The injection reminder's settings row subtitle (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Every 12 weeks'**
  String get reminderKindBirthControlShotSubtitle;

  /// Row subtitle shown when an anchor-based birth-control reminder (patch, ring, shot) is enabled for a method with no recorded start date: without one there is no knowable due date, so nothing fires (Issue #183).
  ///
  /// In en, this message translates to:
  /// **'Waits for a start date on the recorded method — re-record the method in profile settings to set one'**
  String get reminderBirthControlNeedsStartDate;

  /// Issue #545: shared failure copy reused by every …FailureCopy mapper under lib/ui/l10n/ whose domain sealed failure has a plain network-error case (sharing, ownership transfer, prediction connections, notification preferences).
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection.'**
  String get commonNetworkError;

  /// Issue #545: shared failure copy reused by the auth and feedback failure mappers, whose network case names the server rather than the connection generically.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and try again.'**
  String get commonServerUnreachable;

  /// Issue #545: shared failure copy reused by every …FailureCopy mapper for an unauthorized/forbidden case.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission for this action.'**
  String get commonUnauthorized;

  /// Issue #545: shared catch-all failure copy reused by every …FailureCopy mapper's 'other'/unknown case.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get commonSomethingWentWrong;

  /// SharingFailure.notFound copy, rendered by sharingFailureCopy (lib/ui/l10n/sharing_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Invitation not found or invalid link.'**
  String get sharingFailureNotFound;

  /// SharingFailure.expired copy.
  ///
  /// In en, this message translates to:
  /// **'This invitation has expired.'**
  String get sharingFailureExpired;

  /// SharingFailure.alreadyAccepted copy.
  ///
  /// In en, this message translates to:
  /// **'This invitation was already accepted.'**
  String get sharingFailureAlreadyAccepted;

  /// SharingFailure.alreadyGuardian copy.
  ///
  /// In en, this message translates to:
  /// **'You are already an active guardian for this child.'**
  String get sharingFailureAlreadyGuardian;

  /// SharingFailure.invalidToken copy.
  ///
  /// In en, this message translates to:
  /// **'Invalid invitation link.'**
  String get sharingFailureInvalidToken;

  /// SharingFailure.notSignedIn copy, rendered by sharingFailureCopy (lib/ui/l10n/sharing_failure_copy.dart). A no-session refusal at a sharing surface, distinct from commonUnauthorized (issue #885).
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account to manage sharing.'**
  String get sharingFailureNotSignedIn;

  /// Calm state shown in place of a failed pending-invitations load when the device has no session (issue #885).
  ///
  /// In en, this message translates to:
  /// **'Sharing needs an account. Sign in to invite a guardian.'**
  String get sharingNeedsAccount;

  /// Action button beside sharingNeedsAccount, routing to the existing sign-in screen (issue #885).
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get sharingSignInAction;

  /// SharingFailure.other copy — distinct from the generic commonSomethingWentWrong because this failure is always an accept-invite attempt.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept invitation. Please try again.'**
  String get sharingFailureOther;

  /// ProfileErasureFailure.network copy at the purge surface, rendered by profileErasureFailureCopy (lib/ui/l10n/profile_erasure_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Can\'t purge while offline. Check your connection and try again.'**
  String get profileErasureFailureNetwork;

  /// ProfileErasureFailure.unauthorized copy at the purge surface. Only ever shown to a signed-in caller who genuinely lacks the role (issue #883); a signed-out caller never sees it.
  ///
  /// In en, this message translates to:
  /// **'Only that profile\'s primary guardian can purge its data.'**
  String get profileErasureFailureUnauthorized;

  /// ProfileErasureFailure.notSignedIn copy, rendered by profileErasureFailureCopy (lib/ui/l10n/profile_erasure_failure_copy.dart). A no-session refusal at a purge surface, distinct from profileErasureFailureUnauthorized (issue #883).
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account to purge imported data.'**
  String get profileErasureFailureNotSignedIn;

  /// ProfileErasureFailure.invalidSource copy at the purge surface.
  ///
  /// In en, this message translates to:
  /// **'That import source isn\'t supported. Nothing was purged.'**
  String get profileErasureFailureInvalidSource;

  /// ProfileErasureFailure.other copy at the purge surface.
  ///
  /// In en, this message translates to:
  /// **'Failed to purge imported data. Check connection and try again.'**
  String get profileErasureFailureOther;

  /// Shown in the purge dialog when the selected profile has no imported rows for any source valid on this platform, instead of offering a no-op purge (issue #883).
  ///
  /// In en, this message translates to:
  /// **'This profile has no imported data from a supported source.'**
  String get purgeImportedDataNoRows;

  /// The purge dialog's count preview (issue #883): how many local rows the selected profile+source purge would remove, e.g. '109 entries from File import'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}} from {source}'**
  String purgeImportedDataPreview(int count, String source);

  /// Issue #925: the restore-from-file preview's warning before the user commits, naming how many of the file's day entries are out of bounds and why (reasons). Shown only when count > 0.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day entry falls} other{{count} day entries fall}} outside this profile\'s date range and will be skipped when you import ({reasons}).'**
  String importEntryDatesRejectedPreview(int count, String reasons);

  /// Issue #925: the restore-from-file result summary's skipped-by-date clause, counted in the same sentence as the other outcomes rather than leaving '0 skipped' misleading. Shown only when count > 0.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day entry} other{{count} day entries}} skipped by date ({reasons})'**
  String importEntryDatesRejectedResult(int count, String reasons);

  /// Issue #925: the 'future-dated' half of a rejected-entry reason breakdown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more than a day in the future} other{{count} more than a day in the future}}'**
  String importEntryDatesRejectionFuture(int count);

  /// Issue #925: the 'before the birth year' half of a rejected-entry reason breakdown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 before the birth year} other{{count} before the birth year}}'**
  String importEntryDatesRejectionBeforeBirthYear(int count);

  /// Issue #925: joins the two non-zero rejected-entry reasons into one phrases, e.g. '1 more than a day in the future and 2 before the birth year'.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String importEntryDatesRejectionReasonsJoin(String first, String second);

  /// InviteCancellation.revoked copy, rendered by inviteCancellationCopy (lib/ui/l10n/sharing_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Invitation cancelled'**
  String get inviteCancellationRevoked;

  /// InviteCancellation.alreadyAccepted copy.
  ///
  /// In en, this message translates to:
  /// **'That invitation was already accepted'**
  String get inviteCancellationAlreadyAccepted;

  /// InviteCancellation.alreadyRevoked copy.
  ///
  /// In en, this message translates to:
  /// **'That invitation was already cancelled'**
  String get inviteCancellationAlreadyRevoked;

  /// InviteCancellation.expired copy.
  ///
  /// In en, this message translates to:
  /// **'That invitation had already expired'**
  String get inviteCancellationExpired;

  /// TransferFailure.notFound copy, rendered by transferFailureCopy (lib/ui/l10n/transfer_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Transfer not found or invalid link.'**
  String get transferFailureNotFound;

  /// TransferFailure.expired copy.
  ///
  /// In en, this message translates to:
  /// **'This transfer link has expired.'**
  String get transferFailureExpired;

  /// TransferFailure.cancelled copy.
  ///
  /// In en, this message translates to:
  /// **'This transfer was cancelled.'**
  String get transferFailureCancelled;

  /// TransferFailure.alreadyAccepted copy.
  ///
  /// In en, this message translates to:
  /// **'This transfer was already accepted.'**
  String get transferFailureAlreadyAccepted;

  /// TransferFailure.selfTransfer copy.
  ///
  /// In en, this message translates to:
  /// **'You can\'t claim a transfer you created yourself.'**
  String get transferFailureSelfTransfer;

  /// TransferFailure.staleOwner copy.
  ///
  /// In en, this message translates to:
  /// **'Your role on this profile has changed, so this transfer is no longer valid.'**
  String get transferFailureStaleOwner;

  /// TransferFailure.alreadyArmed copy.
  ///
  /// In en, this message translates to:
  /// **'A transfer is already pending for this profile. Cancel it before starting a new one.'**
  String get transferFailureAlreadyArmed;

  /// TransferFailure.invalidToken copy.
  ///
  /// In en, this message translates to:
  /// **'Invalid transfer link.'**
  String get transferFailureInvalidToken;

  /// PredictionConnectionFailure.notFound copy, rendered by predictionConnectionFailureCopy (lib/ui/l10n/prediction_connection_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'That code is not valid.'**
  String get predictionConnectionFailureNotFound;

  /// PredictionConnectionFailure.expired copy.
  ///
  /// In en, this message translates to:
  /// **'That code has expired.'**
  String get predictionConnectionFailureExpired;

  /// PredictionConnectionFailure.alreadyAccepted copy.
  ///
  /// In en, this message translates to:
  /// **'That code was already used.'**
  String get predictionConnectionFailureAlreadyAccepted;

  /// PredictionConnectionFailure.alreadyGuardian copy.
  ///
  /// In en, this message translates to:
  /// **'You already have full guardian access to this profile.'**
  String get predictionConnectionFailureAlreadyGuardian;

  /// PredictionConnectionFailure.invalidToken copy.
  ///
  /// In en, this message translates to:
  /// **'Invalid connection code.'**
  String get predictionConnectionFailureInvalidToken;

  /// PredictionConnectionFailure.pregnancyMode copy.
  ///
  /// In en, this message translates to:
  /// **'Prediction sharing is unavailable while this profile is in Pregnancy mode.'**
  String get predictionConnectionFailurePregnancyMode;

  /// PredictionConnectionFailure.alreadyConnected copy.
  ///
  /// In en, this message translates to:
  /// **'This profile already has a prediction connection. Revoke it before sharing with someone else.'**
  String get predictionConnectionFailureAlreadyConnected;

  /// PredictionConnectionFailure.oneDirectional copy.
  ///
  /// In en, this message translates to:
  /// **'You cannot share and view predictions with the same person at the same time.'**
  String get predictionConnectionFailureOneDirectional;

  /// PredictionConnectionFailure.minorProfile copy.
  ///
  /// In en, this message translates to:
  /// **'Prediction sharing is not available for a minor\'s profile.'**
  String get predictionConnectionFailureMinorProfile;

  /// FeedbackFailure.rateLimited copy, rendered by feedbackFailureCopy (lib/ui/l10n/feedback_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent a few reports already — please try again in a bit.'**
  String get feedbackFailureRateLimited;

  /// FeedbackFailure.invalidInput copy.
  ///
  /// In en, this message translates to:
  /// **'Check your message and try again.'**
  String get feedbackFailureInvalidInput;

  /// FeedbackFailure.attachmentTooLarge copy.
  ///
  /// In en, this message translates to:
  /// **'That image is too large. Choose one under 5 MB.'**
  String get feedbackFailureAttachmentTooLarge;

  /// FeedbackFailure.attachmentRejected copy.
  ///
  /// In en, this message translates to:
  /// **'That file type is not supported. Choose a PNG, JPEG, or WebP image.'**
  String get feedbackFailureAttachmentRejected;

  /// FeedbackFailure.notFound copy.
  ///
  /// In en, this message translates to:
  /// **'That ticket could not be found.'**
  String get feedbackFailureNotFound;

  /// FeedbackAttachmentUploadFailedFailure copy; {attachmentReason} is the nested attachment failure's own copy.
  ///
  /// In en, this message translates to:
  /// **'Your message was sent — no need to resend it. The attachment did not upload ({attachmentReason}) You can find your ticket in Support history.'**
  String feedbackFailureAttachmentUploadFailed(String attachmentReason);

  /// NotificationPreferencesFailure.invalidTimeZone copy, rendered by notificationPreferencesFailureCopy (lib/ui/l10n/notification_preferences_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Your device\'s time zone isn\'t recognised by the server yet — quiet hours will use UTC until it is'**
  String get notificationPreferencesFailureInvalidTimeZone;

  /// NotificationPreferencesFailure.other copy — distinct from the generic commonSomethingWentWrong because this failure is always a preferences-save attempt.
  ///
  /// In en, this message translates to:
  /// **'Failed to save notification preferences. Please try again.'**
  String get notificationPreferencesFailureOther;

  /// GuardianRole.primaryGuardian's display label, rendered by guardianRoleLabel (lib/ui/l10n/guardian_role_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Primary Guardian'**
  String get guardianRoleLabelPrimaryGuardian;

  /// GuardianRole.coParent's display label.
  ///
  /// In en, this message translates to:
  /// **'Co-Parent'**
  String get guardianRoleLabelCoParent;

  /// GuardianRole.caregiver's display label.
  ///
  /// In en, this message translates to:
  /// **'Caregiver'**
  String get guardianRoleLabelCaregiver;

  /// GuardianRole.viewer's display label.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get guardianRoleLabelViewer;

  /// Why a viewer's day sheet (and other write surfaces) is read-only, rendered by guardianRoleReadOnlyReason.
  ///
  /// In en, this message translates to:
  /// **'You have view-only access to this profile.'**
  String get guardianRoleReadOnlyReasonViewer;

  /// Issue #545: moved from lib/domain/activity/activity_feed.dart's activityActorLabel (now lib/ui/l10n/activity_actor_copy.dart) — the current operator's own name in an activity feed row.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get activityActorYou;

  /// Issue #545: moved from activityActorLabel — fallback name for an actor whose guardian row is not (or no longer) known.
  ///
  /// In en, this message translates to:
  /// **'a guardian'**
  String get activityActorGuardianFallback;

  /// Issue #545: moved from SharingProfileInfo.roleSubtitle (lib/domain/sharing/sharing_overview.dart) — a profile row's subtitle for a profile shared with the operator, naming their role. Rendered by sharingProfileRoleSubtitle (lib/ui/l10n/guardian_role_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'Shared with me · {role}'**
  String profilePickerSharedRoleSubtitle(String role);

  /// AuthWrongPasswordFailure copy, rendered by authFailureCopy (lib/ui/l10n/auth_failure_copy.dart).
  ///
  /// In en, this message translates to:
  /// **'That email and password combination was not accepted.'**
  String get authFailureWrongPassword;

  /// AuthWeakPasswordFailure copy.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password of at least {minLength} characters.'**
  String authFailureWeakPassword(int minLength);

  /// AuthProviderUnavailableFailure copy — deliberately generic (also covers a passkey ceremony that could not run), so it must never name Google, Apple, or "passkey" specifically.
  ///
  /// In en, this message translates to:
  /// **'That sign-in method isn\'t available on this device. Use email instead.'**
  String get authFailureProviderUnavailable;

  /// AuthRateLimitedFailure copy.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a little while, then try again.'**
  String get authFailureRateLimited;

  /// AuthMisconfiguredFailure copy.
  ///
  /// In en, this message translates to:
  /// **'That sign-in method is not set up for this app right now. Try another way to sign in.'**
  String get authFailureMisconfigured;

  /// AuthExpiredLinkFailure copy.
  ///
  /// In en, this message translates to:
  /// **'That sign-in link is no longer valid. Request a new one.'**
  String get authFailureExpiredLink;

  /// AuthInvalidCodeFailure copy.
  ///
  /// In en, this message translates to:
  /// **'That code was not accepted. Check it or request a new email.'**
  String get authFailureInvalidCode;

  /// AuthIdentityTakenFailure copy.
  ///
  /// In en, this message translates to:
  /// **'That sign-in method already belongs to another account.'**
  String get authFailureIdentityTaken;

  /// AuthSignUpClosedFailure copy.
  ///
  /// In en, this message translates to:
  /// **'New accounts for this app are set up by the account owner.'**
  String get authFailureSignUpClosed;

  /// AuthLastSignInMethodFailure copy.
  ///
  /// In en, this message translates to:
  /// **'That is the only way left to sign in to this account. Add another method first.'**
  String get authFailureLastSignInMethod;

  /// Tooltip on a care note's delete icon button.
  ///
  /// In en, this message translates to:
  /// **'Remove note'**
  String get careNotesRemoveNoteTooltip;

  /// Tooltip on a visit-prep item's delete icon button.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get careNotesRemoveItemTooltip;

  /// Tooltip on the profile app bar's care notes entry point.
  ///
  /// In en, this message translates to:
  /// **'Care notes & visit prep'**
  String get careNotesButtonTooltip;

  /// Tooltip on the activity feed app bar action.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityFeedTooltip;

  /// InlineError message (announced as a screen-reader live region) when ActivityFeedScreen's feed stream errors. Issue #602.
  ///
  /// In en, this message translates to:
  /// **'Could not load the activity feed.'**
  String get activityFeedLoadError;

  /// Tooltip on a pending invitation's cancel icon button.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation'**
  String get manageGuardiansCancelInviteTooltip;

  /// Tooltip on Manage Guardians' guardian-roles help action.
  ///
  /// In en, this message translates to:
  /// **'About roles'**
  String get manageGuardiansAboutRolesTooltip;

  /// Tooltip on Manage Guardians' transfer-ownership app bar action.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get manageGuardiansTransferOwnershipTooltip;

  /// Tooltip on Manage Guardians' notification-preferences app bar action.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get manageGuardiansNotificationsTooltip;

  /// Tooltip on the prediction-connection tile's revoke icon button.
  ///
  /// In en, this message translates to:
  /// **'End prediction sharing'**
  String get manageGuardiansEndSharingTooltip;

  /// Tooltip on a guardian row's role-change menu button.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get manageGuardiansChangeRoleTooltip;

  /// Tooltip on a guardian row's revoke button when the row is the caller's own.
  ///
  /// In en, this message translates to:
  /// **'Leave profile'**
  String get manageGuardiansLeaveProfileTooltip;

  /// Tooltip on a guardian row's revoke button when the row belongs to someone else.
  ///
  /// In en, this message translates to:
  /// **'Remove guardian'**
  String get manageGuardiansRemoveCaregiverTooltip;

  /// Tooltip on the feedback form's attachment-remove icon button.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get feedbackRemoveAttachmentTooltip;

  /// Tooltip on the prediction connection calendar's refresh action.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get predictionCalendarRefreshTooltip;

  /// Tooltip on a Settings icon button, shared by the app shell's bottom nav and the profile picker's app bar action.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// Tooltip on the profile picker's add-profile action.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get profilePickerAddProfileTooltip;

  /// Tooltip on an archived profile row's unarchive icon button.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get profilePickerUnarchiveTooltip;

  /// Tooltip on a profile row's overflow-actions icon button.
  ///
  /// In en, this message translates to:
  /// **'Profile actions'**
  String get profilePickerActionsTooltip;

  /// Issue #860: the profile row's overflow-menu item and the profile edit dialog's title. The dialog edits the name plus Life-stage mode, Care mode, Relationship and Birth control, so it is labelled for everything it does rather than only the rename it used to be labelled for.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileAction;

  /// Tooltip on the profile picker's shared-predictions entry point.
  ///
  /// In en, this message translates to:
  /// **'Shared with me'**
  String get profilePickerSharedWithMeTooltip;

  /// Tooltip on the profile detail screen's switch-profile action.
  ///
  /// In en, this message translates to:
  /// **'Switch profile'**
  String get profileDetailSwitchProfileTooltip;

  /// Issue #241: tooltip on the app shell's quick profile switcher (the app-bar profile title, a popup listing active profiles).
  ///
  /// In en, this message translates to:
  /// **'Switch profile'**
  String get appShellProfileSwitcherTooltip;

  /// Issue #241: the quick profile switcher menu's entry that opens the full profile picker.
  ///
  /// In en, this message translates to:
  /// **'Manage profiles…'**
  String get quickSwitcherManageProfiles;

  /// Issue #241: the one-line cycle status on a ProfileCard row for a profile with too little history to estimate from (the CyclePredictionService's NotEnoughHistory state).
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get profileStatusNoHistory;

  /// Issue #241: the one-line cycle status on a ProfileCard row for a profile whose predictions are suppressed (a continuous birth-control method in effect, or a pregnancy/postpartum/perimenopause life-stage mode).
  ///
  /// In en, this message translates to:
  /// **'Period predictions off'**
  String get profileStatusPredictionsSuppressed;

  /// Issue #241: the one-line cycle status on a ProfileCard row for a profile whose operator turned predictions off in settings (issue #225's PredictionsDisabled state).
  ///
  /// In en, this message translates to:
  /// **'Period predictions off'**
  String get profileStatusPredictionsOff;

  /// Issue #545: a bare integer day count, correctly pluralized (fixes 'N days' rendering as '1 days'). Shared by the cycle-history section's variation/period-length stats and the late-resolver's fallback line.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{day} other{days}}'**
  String daysCount(int count);

  /// Issue #545: a possibly-fractional day value (e.g. '3.5 days') with its plural word chosen from the underlying numeric count. {value} is the already-formatted display string; {count} is only used to select 'day' vs 'days'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{value} day} other{{value} days}}'**
  String daysValue(num count, String value);

  /// Day-sheet section heading above the BBT and weight numeric-entry fields (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Measurements'**
  String get daySheetMeasurementsHeading;

  /// Label (and accessibility label) for the day sheet's BBT text field (Issue #457); {unit} is the profile's current display-unit symbol ('°C'/'°F', from measurement_unit.dart's bbtUnitSymbol — a universal symbol, not itself translated).
  ///
  /// In en, this message translates to:
  /// **'BBT ({unit})'**
  String daySheetBbtFieldLabel(String unit);

  /// Label (and accessibility label) for the day sheet's weight text field (Issue #457); {unit} is the profile's current display-unit symbol ('kg'/'lb').
  ///
  /// In en, this message translates to:
  /// **'Weight ({unit})'**
  String daySheetWeightFieldLabel(String unit);

  /// Inline validation error under the BBT field when the entered value is outside the sanity range (Issue #457); {min}/{max} are already formatted in the profile's current display unit.
  ///
  /// In en, this message translates to:
  /// **'Enter a BBT between {min} and {max}'**
  String daySheetBbtRangeError(String min, String max);

  /// Inline validation error under the weight field when the entered value is outside the sanity range (Issue #457); {min}/{max} are already formatted in the profile's current display unit.
  ///
  /// In en, this message translates to:
  /// **'Enter a weight between {min} and {max}'**
  String daySheetWeightRangeError(String min, String max);

  /// Inline validation error under a measurement field when the entered text does not parse as a number at all (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get daySheetMeasurementInvalidNumber;

  /// Label for the per-measurement exclusion toggle (Issue #457, the BBT per-point 'excluded' flag, A1-44) — used for both the BBT and weight fields, distinguished by the group name each toggle's own accessibility wrapper supplies.
  ///
  /// In en, this message translates to:
  /// **'Exclude from charts'**
  String get daySheetMeasurementExcludeLabel;

  /// The exclusion toggle's label once a measurement is already excluded (Issue #457) — tapping it un-excludes, mirroring the cycle-history list's own Omit/Include button pair.
  ///
  /// In en, this message translates to:
  /// **'Include in charts'**
  String get daySheetMeasurementIncludeLabel;

  /// Accessibility group name for the BBT field and its exclude toggle (Issue #457), read by groupedChipSemantics-style wrappers alongside the control's own label.
  ///
  /// In en, this message translates to:
  /// **'BBT'**
  String get daySheetBbtGroup;

  /// Accessibility group name for the weight field and its exclude toggle (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get daySheetWeightGroup;

  /// Heading of the per-profile BBT/weight display-unit section in Settings when only one profile exists (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Measurement units'**
  String get settingsMeasurementUnitsTitle;

  /// Heading of the measurement-units section in Settings for a specific profile, when more than one profile exists (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Measurement units ({profileName})'**
  String settingsMeasurementUnitsProfileTitle(String profileName);

  /// Row label for the BBT display-unit selector in Settings (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'BBT unit'**
  String get settingsMeasurementUnitsBbtLabel;

  /// Row label for the weight display-unit selector in Settings (Issue #457).
  ///
  /// In en, this message translates to:
  /// **'Weight unit'**
  String get settingsMeasurementUnitsWeightLabel;

  /// Heading of the Account section's TOTP MFA tile group (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication'**
  String get mfaSectionTitle;

  /// Tile offering to start TOTP enrolment when the account has no factor yet (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Set up two-factor authentication'**
  String get mfaEnrollTileTitle;

  /// Subtitle under mfaEnrollTileTitle (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Add an authenticator app as a second sign-in factor.'**
  String get mfaEnrollTileSubtitle;

  /// Title of the row for an enrolled TOTP factor (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Authenticator app'**
  String get mfaFactorTileTitle;

  /// Subtitle for a verified TOTP factor row (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get mfaFactorTileSubtitleVerified;

  /// Subtitle for a still-unverified TOTP factor row, e.g. after an interrupted enrolment (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Setup not finished — remove and try again'**
  String get mfaFactorTileSubtitlePending;

  /// Confirmation dialog title for removing the account's TOTP factor (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Remove two-factor authentication?'**
  String get mfaRemoveFactorTitle;

  /// Confirmation dialog body for removing the account's TOTP factor (issue #268).
  ///
  /// In en, this message translates to:
  /// **'You will only need your password to sign in and to confirm account actions.'**
  String get mfaRemoveFactorBody;

  /// Confirm button for removing a TOTP factor (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get mfaRemoveFactorConfirm;

  /// Generic inline error for an MFA action (enroll/verify/remove) that failed (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get mfaErrorGeneric;

  /// Title of the TOTP enrolment screen (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Set up two-factor authentication'**
  String get mfaEnrollScreenTitle;

  /// Instructions above the manual-entry setup key on the TOTP enrolment screen (issue #268). No in-app QR code today — flutter_svg is not a project dependency, and gotrue's enrolment response encodes it only as an SVG data URI, which Image.network/Image.memory cannot rasterize; see mfa_enroll_screen.dart's doc comment.
  ///
  /// In en, this message translates to:
  /// **'Add this setup key to your authenticator app (Google Authenticator, 1Password, Authy, and similar apps all accept manual entry).'**
  String get mfaEnrollInstructions;

  /// Label above the manual-entry TOTP secret (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Setup key'**
  String get mfaEnrollSecretLabel;

  /// Label for the verification-code field on the TOTP enrolment screen (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your app'**
  String get mfaEnrollCodeLabel;

  /// Hint text for a TOTP code entry field, shared by enrolment and step-up (issue #268).
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get mfaCodeHint;

  /// Confirm button on the TOTP enrolment screen (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get mfaEnrollConfirmButton;

  /// Snackbar shown after a TOTP enrolment completes (issue #268).
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication is on.'**
  String get mfaEnrollSuccessMessage;

  /// Title of the AAL2 step-up dialog shown before a destructive account action (issue #268 D-6).
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get mfaStepUpTitle;

  /// Body of the AAL2 step-up dialog (issue #268 D-6).
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code from your authenticator app to continue.'**
  String get mfaStepUpBody;

  /// Confirm button on the AAL2 step-up dialog (issue #268 D-6).
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get mfaStepUpConfirmButton;

  /// Heading of the optional in-app PIN settings row (issue #271).
  ///
  /// In en, this message translates to:
  /// **'App PIN'**
  String get pinSettingsSectionTitle;

  /// Title of the in-app PIN settings tile (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Require a PIN to open lunarlog'**
  String get pinSettingsToggleTitle;

  /// Subtitle of the PIN settings tile when a PIN is set (issue #271).
  ///
  /// In en, this message translates to:
  /// **'On — an additional lock layer on top of your device credential.'**
  String get pinSettingsToggleSubtitleOn;

  /// Subtitle of the PIN settings tile when no PIN is set (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get pinSettingsToggleSubtitleOff;

  /// Title of the screen for setting a brand-new in-app PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get pinSetScreenTitle;

  /// Title of the screen for changing an existing in-app PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get pinChangeScreenTitle;

  /// Field label for the current PIN, required to change or remove one (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get pinCurrentPinLabel;

  /// Field label for the new PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'New PIN (4-8 digits)'**
  String get pinNewPinLabel;

  /// Field label for re-entering the new PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get pinConfirmPinLabel;

  /// Inline error when the new-PIN and confirm-PIN fields differ (issue #271).
  ///
  /// In en, this message translates to:
  /// **'PINs don\'t match.'**
  String get pinMismatchError;

  /// Inline error when the new PIN is shorter than 4 digits (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Enter at least 4 digits.'**
  String get pinTooShortError;

  /// Inline error when the current-PIN field does not match the stored PIN, while changing or removing it (issue #271).
  ///
  /// In en, this message translates to:
  /// **'That PIN is incorrect.'**
  String get pinWrongCurrentError;

  /// Save button on the set/change-PIN screen (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get pinSaveButton;

  /// Confirmation dialog title for removing the in-app PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Turn off PIN?'**
  String get pinRemoveConfirmTitle;

  /// Confirmation dialog body for removing the in-app PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'You can still use your device credential to unlock lunarlog.'**
  String get pinRemoveConfirmBody;

  /// Confirm button for removing the in-app PIN (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get pinRemoveConfirmButton;

  /// Prompt shown above the PIN field on the lock screen (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get pinLockScreenPrompt;

  /// Submit button on the lock screen's PIN entry (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get pinLockScreenUnlockButton;

  /// Inline error on the lock screen after a wrong PIN, naming how many attempts remain before the next lockout tier (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN. {count} attempt(s) remaining before a short lockout.'**
  String pinLockScreenIncorrect(int count);

  /// Inline error on the lock screen while the PIN is locked out, naming the local time it unlocks again (issue #271).
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again after {time}.'**
  String pinLockScreenLockedOut(String time);

  /// Row title for a reminder type's custom notification text editor entry (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Notification text'**
  String get reminderTextTileTitle;

  /// Row subtitle shown when a reminder type has no custom notification text and falls back to the generic default (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Using the default text'**
  String get reminderTextTileDefaultSubtitle;

  /// App bar title of the per-type notification text editor (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Notification text'**
  String get reminderTextEditorAppBarTitle;

  /// Section header above the live notification preview in the text editor (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get reminderTextPreviewSection;

  /// The app name shown in the OS-notification-styled preview, matching what the OS banner header shows (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'lunarlog'**
  String get reminderTextPreviewAppName;

  /// The timestamp label in the OS-notification-styled preview, imitating the OS banner's relative time (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get reminderTextPreviewNow;

  /// Label above the notification title field in the text editor (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get reminderTextTitleLabel;

  /// Label above the notification body field in the text editor (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get reminderTextBodyLabel;

  /// Save action in the notification text editor (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get reminderTextSaveButton;

  /// Action in the notification text editor that clears the custom text so the type falls back to the generic default (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get reminderTextResetButton;

  /// Explainer under the editor fields stating the discretion posture: manual text only, no auto-inserted names or dates (Issue #184).
  ///
  /// In en, this message translates to:
  /// **'The preview is exactly what the notification will show — nothing more. lunarlog never adds a profile name, date, or health detail to notification text.'**
  String get reminderTextDiscretionNote;

  /// Pregnancy-mode Cycle View headline: the week-of-pregnancy counter derived from the estimated due date (Issue #192). Week is the 0-based gestational week (floor of gestational days / 7), so the due date itself reads week 40.
  ///
  /// In en, this message translates to:
  /// **'Week {week} of pregnancy'**
  String pregnancyWeekTitle(int week);

  /// Pregnancy card line naming the estimated due date (Issue #192); date is the localized month-day-year.
  ///
  /// In en, this message translates to:
  /// **'Estimated due date: {date}'**
  String pregnancyDueOn(String date);

  /// Pregnancy card quiet line when the mode is pregnancy but no due date was recorded (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'No due date recorded yet. Edit this profile and set the life-stage mode to Pregnancy to add one.'**
  String get pregnancyDueDateMissing;

  /// Label for the due-date field shown in the profile edit dialog while the life-stage mode is Pregnancy (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Estimated due date'**
  String get pregnancyDueDateLabel;

  /// Hint under the due-date field when the shown value was derived rather than manually picked (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Derived from the last recorded period start (280 days). Tap the date to change it.'**
  String get pregnancyDueDateDerivedHint;

  /// Hint under the due-date field when no last period start could be derived from, so only a manual pick can set it (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Pick the estimated due date — the last period start is unknown.'**
  String get pregnancyDueDateManualHint;

  /// Title of the dialog offered when leaving Pregnancy mode (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Exclude this pregnancy from cycle averages?'**
  String get pregnancyExitExclusionTitle;

  /// Body of the pregnancy-exit exclusion dialog (Issue #192); deliberately states data is kept, only the average skips it.
  ///
  /// In en, this message translates to:
  /// **'Cycles logged during the pregnancy can distort the averages future predictions use. Excluding them keeps your cycle history intact — the pregnancy span is just left out of the math. You can also exclude individual cycles later from cycle history.'**
  String get pregnancyExitExclusionBody;

  /// Accept action of the pregnancy-exit exclusion dialog: writes the cycle_overrides exclusion rows (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Exclude pregnancy'**
  String get pregnancyExitExclusionAccept;

  /// Decline action of the pregnancy-exit exclusion dialog: nothing is written; the cycles stay excludable later from cycle history (Issue #192 AC5).
  ///
  /// In en, this message translates to:
  /// **'Keep in averages'**
  String get pregnancyExitExclusionDecline;

  /// Snackbar confirming the exclusion rows were written (Issue #192).
  ///
  /// In en, this message translates to:
  /// **'Pregnancy excluded from cycle averages'**
  String get pregnancyExitExclusionDone;

  /// Postpartum-mode Cycle View headline: the whole-day counter since the profile entered Postpartum mode (Issue #455). Deliberately framed as 'of postpartum' rather than 'since birth' because the mode start is the app's only recorded proxy for that date — used only when no birth date was supplied (Issue #861).
  ///
  /// In en, this message translates to:
  /// **'Day {days} of postpartum'**
  String postpartumDayTitle(int days);

  /// Postpartum-mode Cycle View headline when the operator supplied a birth date (Issue #861): the whole-day counter runs from that date, so 'since birth' is the honest framing.
  ///
  /// In en, this message translates to:
  /// **'Day {days} since birth'**
  String postpartumDaySinceBirth(int days);

  /// Label for the birth-date field shown in the profile edit dialog while the life-stage mode is Postpartum (Issue #861).
  ///
  /// In en, this message translates to:
  /// **'Birth date'**
  String get postpartumBirthDateLabel;

  /// Hint under the Postpartum birth-date field explaining the field is optional and what a blank value means (Issue #861).
  ///
  /// In en, this message translates to:
  /// **'Optional. Pick the date to count from, or leave it blank to count from today.'**
  String get postpartumBirthDateHint;

  /// Postpartum card quiet line when the mode is postpartum but no mode-start date was stamped (a row entered before #188 stamped the column), matching the pregnancy card's honest no-data state (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Postpartum mode is on. The start date wasn\'t recorded, so there\'s no day count yet.'**
  String get postpartumStartMissing;

  /// Title of the postpartum overview offer shown once a bleed has been logged during Postpartum mode (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Cycles have returned?'**
  String get postpartumReturnTitle;

  /// Body of the postpartum cycles-have-returned offer: explains the switch, and that leaving the mode offers to exclude the postpartum interval (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'You logged a period during Postpartum mode. Switching to Period Tracking resumes ordinary predictions and lets the app start rebuilding cycle averages from your new cycles.'**
  String get postpartumReturnBody;

  /// Action of the postpartum cycles-have-returned offer; switches the profile's life-stage mode to tracking and then offers the interval exclusion (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Switch to Period Tracking'**
  String get postpartumReturnAction;

  /// Title of the dialog offered when leaving Postpartum mode (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Exclude this postpartum interval from cycle averages?'**
  String get postpartumExitExclusionTitle;

  /// Body of the postpartum-exit exclusion dialog (Issue #455); deliberately states data is kept, only the average skips it.
  ///
  /// In en, this message translates to:
  /// **'Bleeding logged during the postpartum interval can distort the averages future predictions use. Excluding it keeps your cycle history intact — the postpartum span is just left out of the math. You can also exclude individual cycles later from cycle history.'**
  String get postpartumExitExclusionBody;

  /// Accept action of the postpartum-exit exclusion dialog: writes the cycle_overrides exclusion rows (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Exclude postpartum interval'**
  String get postpartumExitExclusionAccept;

  /// Decline action of the postpartum-exit exclusion dialog: nothing is written; the cycles stay excludable later from cycle history (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Keep in averages'**
  String get postpartumExitExclusionDecline;

  /// Snackbar confirming the postpartum exclusion rows were written (Issue #455).
  ///
  /// In en, this message translates to:
  /// **'Postpartum interval excluded from cycle averages'**
  String get postpartumExitExclusionDone;

  /// Heading of the Conceive-mode Cycle View card, shown while profile_modes.mode is conceive (Issue #204).
  ///
  /// In en, this message translates to:
  /// **'Conceive mode'**
  String get conceiveTitle;

  /// Label above the estimated fertile-window date range on the Conceive-mode card (Issue #204).
  ///
  /// In en, this message translates to:
  /// **'Estimated fertile window'**
  String get conceiveWindowLabel;

  /// Conceive-mode card line naming the peak conception-likelihood day from the cited population-average study (Issue #204). Deliberately says 'in one study' so the number never reads as a personal probability.
  ///
  /// In en, this message translates to:
  /// **'Most likely day: {date} (about {percent}% in one study)'**
  String conceivePeakDay(String date, int percent);

  /// Heading of the Perimenopause-mode Cycle View card, shown while profile_modes.mode is perimenopause (Issue #196).
  ///
  /// In en, this message translates to:
  /// **'Cycle changes'**
  String get perimenopauseTitle;

  /// Introductory line of the Perimenopause-mode Cycle View card, explaining why it leads with comparison rather than a lateness countdown (Issue #196). Issue #862: names the comparison as cycle-to-cycle rather than claiming the still-open cycle is the one shown.
  ///
  /// In en, this message translates to:
  /// **'In perimenopause, cycle lengths vary from one to the next. Comparing each cycle with the one before it is how change shows up — not a count of days late.'**
  String get perimenopauseBody;

  /// Heading of the Perimenopause-mode Cycle View card's honest empty state, shown with fewer than two logged cycles (Issue #196).
  ///
  /// In en, this message translates to:
  /// **'Nothing to compare yet'**
  String get perimenopauseNotEnoughTitle;

  /// Body of the Perimenopause-mode Cycle View card's empty state (Issue #196).
  ///
  /// In en, this message translates to:
  /// **'Keep logging — once a second cycle is recorded, this view compares them so you can spot changes. Irregular cycles are expected around perimenopause.'**
  String get perimenopauseNotEnoughBody;

  /// Perimenopause comparison line when the compared cycle is longer than the one before it (Issue #196). {days} is an already-formatted, pluralized day count. Issue #862: the card compares the two most recent COMPLETED cycles (an open cycle has no length yet), so the copy names those rather than saying 'this cycle' — which every other surface uses for the still-open one.
  ///
  /// In en, this message translates to:
  /// **'Your last completed cycle was {days} longer than the one before it'**
  String perimenopauseLengthLonger(String days);

  /// Perimenopause comparison line when the compared cycle is shorter than the one before it (Issue #196). {days} is an already-formatted, pluralized day count. Issue #862: names the completed cycles the card actually compares, never 'this cycle'.
  ///
  /// In en, this message translates to:
  /// **'Your last completed cycle was {days} shorter than the one before it'**
  String perimenopauseLengthShorter(String days);

  /// Perimenopause comparison line when the two compared cycles are the same length (Issue #196). Issue #862: names the completed cycles the card actually compares, never 'this cycle'.
  ///
  /// In en, this message translates to:
  /// **'Your last completed cycle was the same length as the one before it'**
  String get perimenopauseLengthSame;

  /// Perimenopause comparison line when the current cycle has not finished, so no length difference can honestly be stated (Issue #196).
  ///
  /// In en, this message translates to:
  /// **'This cycle is still in progress — compare it once it ends'**
  String get perimenopauseLengthUnknown;

  /// Perimenopause comparison line giving each compared cycle's bleed-day count (Issue #196). Both are already-formatted, pluralized day counts. Issue #862: 'the newer cycle' / 'the one before it' stays true whether the card is comparing two completed cycles or (with only two starts) the open one against the last completed one, where 'this cycle' would misname the pair.
  ///
  /// In en, this message translates to:
  /// **'Bleeding days: {current} in the newer cycle, {previous} in the one before it'**
  String perimenopauseBleedDays(String current, String previous);

  /// Button on the Perimenopause-mode Cycle View card that opens the full side-by-side cycle comparison (Issue #196, reusing Issue #235's screen).
  ///
  /// In en, this message translates to:
  /// **'Compare cycles'**
  String get perimenopauseCompareButton;

  /// Import > Clue path: prompt for the one-time password Clue emails with an export (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Clue emails a one-time password with the export. Enter it to open the file.'**
  String get importCluePasswordPrompt;

  /// Import > Clue path: label of the export-password field (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Export password'**
  String get importClueExportPasswordLabel;

  /// Import > Clue path: button that decrypts and parses the picked export (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Open export'**
  String get importClueOpenExport;

  /// Import > Clue path: shown when no profile exists yet, so the import creates one (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'A new profile will be created for this import.'**
  String get importClueNewProfileNote;

  /// Import > Clue path: label of the new-profile name field (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get importClueProfileNameLabel;

  /// Import > Clue path: cancel button returning to the pick step (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get importClueCancel;

  /// Import > Clue path: confirm button that writes the prepared export (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importClueImport;

  /// Import > Clue path: closes the screen after a successful import (Issue #452).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get importClueDone;

  /// Day sheet: heading of the per-guardian dated notes section (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'Notes from guardians'**
  String get guardianNotesSectionTitle;

  /// Day sheet: shown to a read-only guardian when no guardian note exists for the day (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'No guardian notes for this day yet.'**
  String get guardianNotesEmpty;

  /// Day sheet: author label above the reader's own editable guardian note (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get guardianNotesYou;

  /// Day sheet: button that removes the reader's own guardian note (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get guardianNotesRemove;

  /// Day sheet: button that saves a new guardian note (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get guardianNotesAdd;

  /// Day sheet: button that saves an edit to an existing guardian note (Issue #801).
  ///
  /// In en, this message translates to:
  /// **'Update note'**
  String get guardianNotesUpdate;

  /// Invite dialog (Issue #802): the 'her own profile' preset choice, offered when the profile's relationship is daughter/son/child or the profile is a minor's. Grants the caregiver role plus the subject marker.
  ///
  /// In en, this message translates to:
  /// **'Invite {name} to log her own profile'**
  String inviteSubjectOption(String name);

  /// Invite dialog (Issue #802): the consequence line under the subject preset choice, naming what it grants without the caregiver mislabel.
  ///
  /// In en, this message translates to:
  /// **'Caregiver access - this is {name}\'s own profile, listed as hers on her device'**
  String inviteSubjectOptionDetail(String name);

  /// Invite dialog, generated state: what to do with a helper invitation link.
  ///
  /// In en, this message translates to:
  /// **'Share this single-use link with the guardian for {profile}:'**
  String inviteCreatedShareGuardian(String profile);

  /// Invite dialog, generated state (Issue #802): what to do with a 'her own profile' invitation link.
  ///
  /// In en, this message translates to:
  /// **'Share this single-use link with {name} - she\'ll use it to join and log her own profile:'**
  String inviteCreatedShareSubject(String name);

  /// Accept sheet (Issue #802, per #800's plain-language decision): the intro shown when the invitation carries the 'her own profile' preset.
  ///
  /// In en, this message translates to:
  /// **'This is your profile. {profile}\'s cycle calendar and health logs will sync to this device - the guardians already sharing it can see and log it too.'**
  String acceptInviteSubjectIntro(String profile);

  /// Profile picker / sharing subtitle (Issue #802): the operator's own profile held via a subject membership - never the caregiver role label the preset granted.
  ///
  /// In en, this message translates to:
  /// **'This is your profile'**
  String get profilePickerSubjectSubtitle;

  /// Manage guardians row (Issue #802): badge marking the member who is the profile's subject, distinguishing her row from every guardian's without reading a uuid.
  ///
  /// In en, this message translates to:
  /// **'(her profile)'**
  String get manageGuardiansSubjectBadge;

  /// Manage guardians pending-invitation row (Issue #802): replaces the role label for an invitation created with the 'her own profile' preset.
  ///
  /// In en, this message translates to:
  /// **'Her own profile'**
  String get manageGuardiansPendingSubjectLabel;

  /// Manage guardians (Issue #802): title of the one-time suggestion shown when a minor subject joins a profile still in Standard care mode. Suggested, never forced.
  ///
  /// In en, this message translates to:
  /// **'Switch {name} to Teen mode?'**
  String subjectTeenModeDialogTitle(String name);

  /// Manage guardians (Issue #802): body of the Teen-mode suggestion dialog.
  ///
  /// In en, this message translates to:
  /// **'{name} is logging her own profile now. Teen mode frames things for someone building body literacy for the first time - same data, same honesty. You can change it any time from profile settings.'**
  String subjectTeenModeDialogBody(String name);

  /// Manage guardians (Issue #802): accepting button of the Teen-mode suggestion dialog - writes the profile's care mode to teen.
  ///
  /// In en, this message translates to:
  /// **'Switch to Teen'**
  String get subjectTeenModeDialogAccept;

  /// Manage guardians (Issue #802): declining button of the Teen-mode suggestion dialog - leaves the care mode untouched.
  ///
  /// In en, this message translates to:
  /// **'Keep Standard'**
  String get subjectTeenModeDialogDecline;

  /// Manage guardians (Issue #802): confirmation snackbar after accepting the Teen-mode suggestion.
  ///
  /// In en, this message translates to:
  /// **'Switched to Teen mode'**
  String get subjectTeenModeDoneSnack;

  /// Issue #853: the composed irregular-framing toggle in the profile edit dialog and first-run form.
  ///
  /// In en, this message translates to:
  /// **'Irregular cycles'**
  String get profileIrregularFramingLabel;

  /// Issue #853: the composed irregular-framing toggle's hint, shown under the label.
  ///
  /// In en, this message translates to:
  /// **'Treats variation as expected, not late: ranges instead of dates, no late banner, no late nudges. On by default for teen profiles until cycles are steady.'**
  String get profileIrregularFramingHint;

  /// Issue #852: title of the cycle-end recap card. {cycleNumber} is the 1-based ordinal of the cycle that just closed.
  ///
  /// In en, this message translates to:
  /// **'Cycle {cycleNumber} wrapped up'**
  String cycleRecapTitle(int cycleNumber);

  /// Issue #852: the recap's one certain fact -- the logged length of the cycle that just closed. {days} is already pluralized by formatDays (e.g. '29 days').
  ///
  /// In en, this message translates to:
  /// **'This cycle lasted {days}.'**
  String cycleRecapLength(String days);

  /// Issue #852: the recap's estimate-backed range line, shown only when the engine has an estimate. {range} is a formatted span such as '27-31 days'. Never rendered in irregular framing.
  ///
  /// In en, this message translates to:
  /// **'Your usual range is {range}.'**
  String cycleRecapUsualRange(String range);

  /// Issue #852: this-cycle-vs-previous comparison, shown only when both cycles are complete. Never rendered in irregular framing.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{One day longer than the cycle before it.} other{{days} days longer than the cycle before it.}}'**
  String cycleRecapLongerThanPrevious(int days);

  /// Issue #852: this-cycle-vs-previous comparison, shown only when both cycles are complete. Never rendered in irregular framing.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{One day shorter than the cycle before it.} other{{days} days shorter than the cycle before it.}}'**
  String cycleRecapShorterThanPrevious(int days);

  /// Issue #852: this-cycle-vs-previous comparison when the two lengths are equal. Never rendered in irregular framing.
  ///
  /// In en, this message translates to:
  /// **'About the same length as the cycle before it.'**
  String get cycleRecapSameAsPrevious;

  /// Issue #852: a confidence-tier transition upward, detected with the #178 statistic-change thresholds only when a previous recap's snapshot exists. Uses the app's own CycleConfidence vocabulary, never invented encouragement.
  ///
  /// In en, this message translates to:
  /// **'Your estimates are now more confident.'**
  String get cycleRecapEstimatesMoreConfident;

  /// Issue #852: a confidence-tier transition downward, detected with the #178 statistic-change thresholds only when a previous recap's snapshot exists.
  ///
  /// In en, this message translates to:
  /// **'Your estimates are a little less certain now.'**
  String get cycleRecapEstimatesLessConfident;

  /// Issue #852: a meaningful displayed mean-cycle-length shift detected with the #178 statistic-change thresholds. {days} is the pluralized absolute shift.
  ///
  /// In en, this message translates to:
  /// **'Your average cycle length moved by {days}.'**
  String cycleRecapAverageMoved(String days);

  /// Issue #852: a recurring-symptom fact from the Analysis tab's own report (#135). {symptom} is the tag code with underscores turned into spaces, sentence-cased; {days} is a formatted cycle-day list such as '1-2'.
  ///
  /// In en, this message translates to:
  /// **'{symptom}: most often around cycle day {days}.'**
  String cycleRecapRecurringSymptom(String symptom, String days);

  /// Issue #852: the cramp forecast's own recurring-day fact (#229), shown only when the engine produced one. {days} is a formatted cycle-day list such as '1, 2'.
  ///
  /// In en, this message translates to:
  /// **'Cramps most often land around cycle day {days}.'**
  String cycleRecapCrampDays(String days);

  /// Issue #852: the recap's honest thin-history line, shown instead of any estimate-backed fact while the engine is below its estimate threshold. Mirrors the app's 'Estimates not ready' voice rule.
  ///
  /// In en, this message translates to:
  /// **'Still learning — estimates appear once a few cycles are recorded.'**
  String get cycleRecapStillLearning;

  /// Issue #852: action opening the #235 side-by-side comparison for the recap's two cycles, shown only when both are complete.
  ///
  /// In en, this message translates to:
  /// **'Compare with the cycle before'**
  String get cycleRecapCompareAction;

  /// Issue #852: tooltip and accessibility label for the recap card's dismiss affordance (reused by the irregular suggestion banner's own copy).
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get cycleRecapDismissLabel;

  /// Issue #803: the household row's log-for-her action label. The row itself names the profile, so the visible label stays short; the full 'Log today for <name>' phrasing (householdLogTodayFor) is the action's tooltip/semantics.
  ///
  /// In en, this message translates to:
  /// **'Log today'**
  String get householdLogToday;

  /// Issue #803: the household row's log-for-her action announced with the profile's name (tooltip and screen-reader label for the short on-row button).
  ///
  /// In en, this message translates to:
  /// **'Log today for {name}'**
  String householdLogTodayFor(String name);

  /// Issue #803: household-row timing line when the next-period estimate falls on today (never rendered for an irregular-framed profile, #853).
  ///
  /// In en, this message translates to:
  /// **'Period expected today'**
  String get householdTimingExpectedToday;

  /// Issue #803: household-row timing line when the next-period estimate falls within the upcoming window (never rendered for an irregular-framed profile, #853).
  ///
  /// In en, this message translates to:
  /// **'Period expected in {count, plural, =1{1 day} other{{count} days}}'**
  String householdTimingExpectedIn(int count);

  /// Issue #803: household-row timing line for an open cycle past its estimate — the late resolver's own vocabulary (issue #221), never rendered for an irregular-framed profile (#853: variation is expected, not late).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day late} other{{count} days late}}'**
  String householdTimingLate(int count);

  /// Issue #803: the quiet, factual open-cycle line for an irregular-framed (#853) or stale-history (#859) profile — informative without the overdue framing.
  ///
  /// In en, this message translates to:
  /// **'Last period {count, plural, =1{1 day ago} other{{count} days ago}}'**
  String householdTimingLastLogged(int count);

  /// Issue #803: household-row silence line — the profile has history but nothing logged for at least its reminder-preference threshold. Counts only, never content.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged for {count, plural, =1{1 day} other{{count} days}}'**
  String householdSilence(int count);

  /// Issue #803: household-row changes line from the activity feed's unread count (issue #124 baseline). Counts only — the feed's content discretion applies here too.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}} since you last looked'**
  String householdChanges(int count);

  /// Issue #984: shown under the identity tile when a device-credential re-auth for adding or removing a sign-in method fails (declined, unavailable, or a genuine walk-away). The failing action used to return with no copy at all, which read as an endless Face ID loop.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t confirm it\'s you — try again'**
  String get accountReauthFailed;
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
