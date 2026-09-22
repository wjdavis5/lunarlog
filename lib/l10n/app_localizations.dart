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

  /// Issue #816: subtitle on the cycle-history list's open ('Current cycle') row, making it visible that the in-progress cycle is not part of the completed-cycle tally shown in the section header. Replaced by a skip-specific subtitle when the open cycle is omitted. Issue #1005: third person, so a guardian reading this for someone else's profile is not told 'your period'.
  ///
  /// In en, this message translates to:
  /// **'Not counted yet — the next period completes it'**
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

  /// Short confidence tier label for inline composition, e.g. in 'Estimate confidence: high.' (Issue #1000).
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get cycleConfidenceShortHigh;

  /// Short confidence tier label for inline composition, e.g. in 'Estimate confidence: learning.' (Issue #1000).
  ///
  /// In en, this message translates to:
  /// **'learning'**
  String get cycleConfidenceShortLearning;

  /// Short confidence tier label for inline composition, e.g. in 'Estimate confidence: rough.' (Issue #1000).
  ///
  /// In en, this message translates to:
  /// **'rough'**
  String get cycleConfidenceShortIrregular;

  /// Short confidence tier label for inline composition, e.g. in 'Estimate confidence: provisional.' (Issue #1000).
  ///
  /// In en, this message translates to:
  /// **'provisional'**
  String get cycleConfidenceShortProvisional;

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

  /// Issue #853, #1000: unit label beneath the overdue count in the cycle wheel centre across all framings - names the estimate, never 'late'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day past estimate} other{days past estimate}}'**
  String cycleWheelDaysPastEstimateUnit(int count);

  /// Issue #853, #1000: the overview wheel's screen-reader label when overdue across all framings - never says 'late'.
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

  /// Health import completion summary headline (Issue #992): {imported} days gained or refreshed an imported value, {skipped} days were left alone because a value was already there (hand-logged or already imported).
  ///
  /// In en, this message translates to:
  /// **'Imported {imported, plural, =1{1 day} other{{imported} days}}, skipped {skipped, plural, =1{1 already logged} other{{skipped} already logged}}.'**
  String healthSyncImportSummaryHeadline(int imported, int skipped);

  /// Health import completion headline (Issue #1017) for a pass that imported no days: says plainly that nothing was new because the days were already logged, rather than the pre-#1017 'Imported 0 days'.
  ///
  /// In en, this message translates to:
  /// **'Nothing new — {skipped, plural, =1{1 day} other{{skipped} days}} already logged.'**
  String healthSyncImportSummaryNothingNew(int skipped);

  /// Health sync screen import tile subtitle (Issue #992): the import is no longer bounded to a recent window, it reads the whole available history.
  ///
  /// In en, this message translates to:
  /// **'Bring in all available menstrual flow and spotting.'**
  String get healthSyncImportTileSubtitle;

  /// Shown while a full-history health import runs (Issue #992): the running sample count, so a long pass shows progress rather than a bare spinner.
  ///
  /// In en, this message translates to:
  /// **'Importing… {samples, plural, =1{1 sample} other{{samples} samples}} read so far.'**
  String healthSyncImportProgress(int samples);

  /// Health sync screen scope note (Issue #992): reads are full-history now; background reads remain deferred.
  ///
  /// In en, this message translates to:
  /// **'Imports everything the health store makes available, not a recent window. Background sync is not available yet.'**
  String get healthSyncFullHistoryNote;

  /// Health import summary (Issue #992): the pass hit the page cap or saw a repeated cursor, so it stopped rather than spin. Days read so far were still merged; re-running continues safely.
  ///
  /// In en, this message translates to:
  /// **'The import stopped early after an unusual amount of data. The days already read were kept — run the import again to continue.'**
  String get healthSyncImportStoppedEarly;

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
  /// **'How your family\'s data is stored, shared, and kept private'**
  String get settingsPrivacySubtitle;

  /// Title of the in-app privacy policy dialog.
  ///
  /// In en, this message translates to:
  /// **'lunarlog Privacy Policy'**
  String get settingsPrivacyDialogTitle;

  /// Body of the in-app privacy policy dialog; mirrors PRIVACY.md's summary.
  ///
  /// In en, this message translates to:
  /// **'lunarlog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind your device\'s passcode or biometrics.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Minimum-Age Policy: Licensed for ages 13 and older; household profiles managed by adult guardians (18+).\n• Guardian Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md'**
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

  /// Issue #957: the acknowledgement shown to an under-13 operator who arrived through a parent's or guardian's "her own profile" invitation, instead of the flat 13+ label. The parent's invitation is the parental-consent record.
  ///
  /// In en, this message translates to:
  /// **'My parent or guardian created this profile and invited me to use it'**
  String get firstRunAgeAcknowledgementParentInviteLabel;

  /// Issue #957: one-line hint under the parent-invite acknowledgement.
  ///
  /// In en, this message translates to:
  /// **'Your parent or guardian set up this profile and sent you this invitation. That invitation is their permission for you to use lunarlog and log here yourself.'**
  String get firstRunAgeAcknowledgementParentInviteHint;

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

  /// Caption at the top of the cycle-questions step; states skippability and (truthfully, for the two persisted answers) later editability. Issue #1005: names the field 'life-stage mode' (the edit dialog's own label) and points at the 'Edit profile' action instead of inventing a fifth way to say where.
  ///
  /// In en, this message translates to:
  /// **'A few optional questions to set this profile up — every one can be skipped. The life-stage mode and birth-control answers can be changed later from Edit profile.'**
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

  /// Label of the life-stage-mode question. Issue #1005: was 'Goal / mode', a name no other surface used, so a parent could not find the field later; now matches the edit dialog's 'Life-stage mode' label and the care-mode vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Life-stage mode'**
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

  /// Title of the first-run invite step (issue #804; reworded by issue #996 to name the outcome — another guardian — rather than an unanswerable question about 'help').
  ///
  /// In en, this message translates to:
  /// **'Add another guardian?'**
  String get firstRunInviteTitle;

  /// Body of the first-run invite step: states the benefit to the invited guardian instead of the account plumbing (issue #996). Plural-aware on the number of profiles created in this flow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A co-parent or caregiver can follow and log this profile from their own phone.} other{A co-parent or caregiver can follow and log these profiles from their own phone.}}'**
  String firstRunInviteBody(int count);

  /// Shown on the invite step when there is no session: names why an account is required here, in the order the user meets it (issue #804 AC3; reworded by issue #996 to drop the mechanism sentence).
  ///
  /// In en, this message translates to:
  /// **'Invites are sent from your lunarlog account, so sign in first.'**
  String get firstRunInviteWhyAccount;

  /// Button on the invite step opening the embedded sign-in screen; names the outcome the sign-in is for (issue #804; reworded by issue #996).
  ///
  /// In en, this message translates to:
  /// **'Sign in to invite'**
  String get firstRunInviteSignInAction;

  /// Per-profile button opening the invite dialog with the guardian presets (issue #804). Issue #1005: 'a guardian' is the umbrella the dialog actually offers — a grandparent inviting is not a co-parent.
  ///
  /// In en, this message translates to:
  /// **'Invite a guardian'**
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

  /// Overview line naming the predicted PMS band and the 6-cycle averages behind it as one sentence (Issue #220, #1000; merged into one line by Issue #874). range is the localized start-end date span. Only rendered once at least three PMS intervals have been logged.
  ///
  /// In en, this message translates to:
  /// **'Predicted PMS: {range} — usually starts about {days} {days, plural, =1{day} other{days}} before your period and lasts about {length} {length, plural, =1{day} other{days}}.'**
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
  /// **'Because this profile is set to {mode} mode, period predictions are turned off — the ordinary cycle averages this app estimates from don\'t apply right now. Switch back to Period Tracking mode from Edit profile to resume ordinary prediction.'**
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
  /// **'Waits for a start date on the recorded method — re-record the method from Edit profile to set one'**
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

  /// ProfileErasureFailure.network copy at the purge surface, rendered by profileErasureFailureCopy (lib/ui/l10n/profile_erasure_failure_copy.dart). Issue #1005: 'remove', not the jargon 'purge'.
  ///
  /// In en, this message translates to:
  /// **'Can\'t remove imported data while offline. Check your connection and try again.'**
  String get profileErasureFailureNetwork;

  /// ProfileErasureFailure.unauthorized copy at the purge surface. Only ever shown to a signed-in caller who genuinely lacks the role (issue #883); a signed-out caller never sees it. Issue #1005: 'remove', not 'purge'.
  ///
  /// In en, this message translates to:
  /// **'Only that profile\'s primary guardian can remove its imported data.'**
  String get profileErasureFailureUnauthorized;

  /// ProfileErasureFailure.notSignedIn copy, rendered by profileErasureFailureCopy (lib/ui/l10n/profile_erasure_failure_copy.dart). A no-session refusal at a purge surface, distinct from profileErasureFailureUnauthorized (issue #883). Issue #1005: 'remove', not 'purge'.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account to remove imported data.'**
  String get profileErasureFailureNotSignedIn;

  /// ProfileErasureFailure.invalidSource copy at the purge surface. Issue #1005: 'remove', not 'purge'.
  ///
  /// In en, this message translates to:
  /// **'That import source isn\'t supported. Nothing was removed.'**
  String get profileErasureFailureInvalidSource;

  /// ProfileErasureFailure.other copy at the purge surface. Issue #1005: the unknown-failure case no longer borrows the network case's 'check connection' advice, and says 'remove', not 'purge'.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove the imported data. Try again.'**
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

  /// AuthSignUpClosedFailure copy. Issue #1003: the old line blocked an invitee with no next step; this names who can invite them.
  ///
  /// In en, this message translates to:
  /// **'New accounts are created by invitation. Ask the person who set up your family\'s lunarlog to invite you.'**
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

  /// Issue #241: the one-line cycle status on a ProfileCard row for a profile whose predictions are suppressed (a continuous birth-control method in effect, or a pregnancy/postpartum/perimenopause life-stage mode). Issue #1005: 'paused', not 'off' — nothing was toggled off and the mode pauses it.
  ///
  /// In en, this message translates to:
  /// **'Period estimates paused'**
  String get profileStatusPredictionsSuppressed;

  /// Issue #241: the one-line cycle status on a ProfileCard row for a profile whose operator turned predictions off in settings (issue #225's PredictionsDisabled state).
  ///
  /// In en, this message translates to:
  /// **'Period predictions off'**
  String get profileStatusPredictionsOff;

  /// Issue #982: the one-line cycle status on a ProfileCard row for a stale-history profile (ActivePrediction.staleHistory, issue #859) — a neutral line replacing the rolled 'Cycle day N' count the same way the overview's stale card replaces it.
  ///
  /// In en, this message translates to:
  /// **'No recent period logged'**
  String get profileStatusNoRecentPeriod;

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

  /// Explainer under the editor fields stating the discretion posture: manual text only, no auto-inserted names or dates, and that custom text is visible on the lock screen (Issue #184, #1002).
  ///
  /// In en, this message translates to:
  /// **'The preview is exactly what the notification will show — nothing more. lunarlog never adds a profile name, date, or health detail to notification text. Anything you type here appears on the lock screen, so keep it something anyone may see.'**
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

  /// Pregnancy card quiet line when the mode is pregnancy but no due date was recorded (Issue #192). Issue #1005: it only renders when the life-stage mode already is Pregnancy, so it no longer tells the reader to set the mode they have already set; points at the 'Edit profile' action.
  ///
  /// In en, this message translates to:
  /// **'No due date yet. Add one from Edit profile.'**
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
  /// **'Cycles logged during the pregnancy can distort the averages future predictions use. Excluding them keeps the cycle history intact — the pregnancy span is just left out of the math. Individual cycles can also be excluded later from cycle history.'**
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

  /// Conceive-mode card line naming the peak conception-likelihood day from the cited population-average study (Issue #204). Issue #1005: names what the percentage is a percentage of — the study's population, not the reader's personal odds.
  ///
  /// In en, this message translates to:
  /// **'Most likely day: {date} (about {percent}% of cycles in the study behind this estimate)'**
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
  /// **'The last completed cycle was {days} longer than the one before it'**
  String perimenopauseLengthLonger(String days);

  /// Perimenopause comparison line when the compared cycle is shorter than the one before it (Issue #196). {days} is an already-formatted, pluralized day count. Issue #862: names the completed cycles the card actually compares, never 'this cycle'.
  ///
  /// In en, this message translates to:
  /// **'The last completed cycle was {days} shorter than the one before it'**
  String perimenopauseLengthShorter(String days);

  /// Perimenopause comparison line when the two compared cycles are the same length (Issue #196). Issue #862: names the completed cycles the card actually compares, never 'this cycle'.
  ///
  /// In en, this message translates to:
  /// **'The last completed cycle was the same length as the one before it'**
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

  /// Invite dialog (Issue #802): the 'their own profile' preset choice, offered when the profile's relationship is daughter/son/child or the profile is a minor's. Grants the caregiver role plus the subject marker. Issue #1003: gender-neutral — the preset is offered for daughter/son/child, so 'her' was wrong.
  ///
  /// In en, this message translates to:
  /// **'Invite {name} to log their own profile'**
  String inviteSubjectOption(String name);

  /// Invite dialog (Issue #802): the consequence line under the subject preset choice, naming what it grants without the caregiver mislabel. Issue #1003: gender-neutral.
  ///
  /// In en, this message translates to:
  /// **'Caregiver access - this is {name}\'s own profile, listed as theirs on their device'**
  String inviteSubjectOptionDetail(String name);

  /// Invite dialog, generated state: what to do with a helper invitation link.
  ///
  /// In en, this message translates to:
  /// **'Share this single-use link with the guardian for {profile}:'**
  String inviteCreatedShareGuardian(String profile);

  /// Invite dialog, generated state (Issue #802): what to do with a 'their own profile' invitation link. Issue #1003: gender-neutral.
  ///
  /// In en, this message translates to:
  /// **'Share this single-use link with {name} - they\'ll use it to join and log their own profile:'**
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
  /// **'{name} is logging her own profile now. Teen mode frames things for someone building body literacy for the first time - same data, same honesty. You can change it any time from Edit profile.'**
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

  /// Issue #803, #1000: household member's cycle is past the predicted start date (e.g. '1 day past the estimate', '3 days past the estimate'). Count is pluralized through the shared ICU daysCount shape.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day past the estimate} other{{count} days past the estimate}}'**
  String householdTimingPastEstimate(int count);

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

  /// Issue #799: title of the overview's read-only, dismissible card surfacing Apple's four computed cycle-deviation types. Deliberately soft ('noticed…'), never alarming.
  ///
  /// In en, this message translates to:
  /// **'Apple Health noticed…'**
  String get healthDeviationCardTitle;

  /// Issue #799: the second-opinion label. Apple computes its deviations from whatever was logged in Apple Health, which can differ from lunarlog's history, so the two can legitimately disagree and are never merged.
  ///
  /// In en, this message translates to:
  /// **'These are Apple\'s own estimates from your Health data — separate from lunarlog\'s prediction.'**
  String get healthDeviationCardSubtitle;

  /// Issue #799: tooltip on the deviation card's dismiss button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get healthDeviationDismiss;

  /// Issue #799: label for Apple's irregularMenstrualCycles deviation.
  ///
  /// In en, this message translates to:
  /// **'irregular cycles'**
  String get healthDeviationKindIrregular;

  /// Issue #799: label for Apple's infrequentMenstrualCycles deviation.
  ///
  /// In en, this message translates to:
  /// **'infrequent cycles'**
  String get healthDeviationKindInfrequent;

  /// Issue #799: label for Apple's prolongedMenstrualPeriods deviation.
  ///
  /// In en, this message translates to:
  /// **'prolonged periods'**
  String get healthDeviationKindProlonged;

  /// Issue #799: label for Apple's persistentIntermenstrualBleeding deviation.
  ///
  /// In en, this message translates to:
  /// **'bleeding between periods'**
  String get healthDeviationKindPersistentIntermenstrualBleeding;

  /// Issue #799: one deviation line on the card, e.g. 'Possible irregular cycles (Aug 1 – Aug 30)'.
  ///
  /// In en, this message translates to:
  /// **'Possible {kind} ({range})'**
  String healthDeviationLine(String kind, String range);

  /// Issue #799: the date span of a deviation interval; both placeholders are already-formatted local dates.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String healthDeviationRange(String start, String end);

  /// Issue #799: a deviation whose interval starts and ends on the same civil day; the placeholder is an already-formatted local date.
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String healthDeviationRangeSingle(String date);

  /// Issue #1003: delete-account dialog body — plain language, no 'server rows' jargon.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, everything stored in it, and the copy on this device. This cannot be undone.'**
  String get accountDeleteDialogBody;

  /// Issue #1003: Settings delete-account tile subtitle — plain language, no 'server rows' jargon.
  ///
  /// In en, this message translates to:
  /// **'Deletes the account, everything in it, and this device\'s copy.'**
  String get accountDeleteTileSubtitle;

  /// Issue #1003: the sign-out-everywhere confirmation body — plainer and shorter than the previous 'Ends every session…' copy.
  ///
  /// In en, this message translates to:
  /// **'Signs this account out on every device. Other devices may keep working for up to an hour. The copy on this device is removed; everything stays in your account.'**
  String get accountSignOutEverywhereBody;

  /// Issue #1003: transfer-ownership confirmation body. Names the canonical 'Primary Guardian' role and the continuing role the arming parent chose.
  ///
  /// In en, this message translates to:
  /// **'{name} will become the Primary Guardian of this profile. You\'ll keep access as {role}, and they can remove that access at any time.'**
  String transferOwnershipConfirmBody(String name, String role);

  /// Issue #1003: transfer-ownership 'What changes' bullet — 'Primary Guardian', not 'owner'.
  ///
  /// In en, this message translates to:
  /// **'{name} becomes this profile\'s Primary Guardian.'**
  String transferOwnershipBecomesGuardian(String name);

  /// Issue #1003: transfer-ownership post-transfer role description for the co_parent role — the canonical 'Co-Parent' label, not 'Co-manager'.
  ///
  /// In en, this message translates to:
  /// **'Co-Parent: keep logging entries and managing this profile.'**
  String get transferOwnershipRoleCoParent;

  /// Issue #1003: transfer-ownership post-transfer role description for the viewer role.
  ///
  /// In en, this message translates to:
  /// **'Viewer: read-only access to their calendar and entries.'**
  String get transferOwnershipRoleViewer;

  /// Issue #1003: the revoke confirmation dialog title when the caller is removing their own row — 'Leave', not 'Remove <name>'.
  ///
  /// In en, this message translates to:
  /// **'Leave {profile}\'s profile?'**
  String manageGuardiansLeaveProfileDialogTitle(String profile);

  /// Issue #1003: the confirm button on the caller's own leave dialog — 'Leave', not 'Remove'.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get manageGuardiansLeaveProfileConfirm;

  /// Issue #1003: pending prediction-connection tile title with no recipient label — plain language, not 'code redemption'.
  ///
  /// In en, this message translates to:
  /// **'Waiting for them to open the link'**
  String get manageGuardiansWaitingForRedemption;

  /// Issue #1003: the confirm action of the 'Sync {name} to this phone?' dialog — matches the title verb, not 'Bind'.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get healthSyncConfirmSyncAction;

  /// Issue #1003: the recipient's manual-entry dialog title — says 'link' to match what the sharer copies.
  ///
  /// In en, this message translates to:
  /// **'Enter a connection link'**
  String get predictionEnterLinkTitle;

  /// Issue #1003: the recipient's manual-entry field hint — says 'link' to match what the sharer copies.
  ///
  /// In en, this message translates to:
  /// **'Paste the link you received'**
  String get predictionEnterLinkHint;

  /// Issue #1003: the recipient's manual-entry FAB label — says 'link' to match what the sharer copies.
  ///
  /// In en, this message translates to:
  /// **'Enter link'**
  String get predictionEnterLinkAction;

  /// Issue #1003: the sharer's copy action — sentence case and one term ('link') with the recipient's entry point.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get sharePredictionsCopyLink;

  /// Issue #1003: the sharer's expiry note — says 'link', matching the copied artifact and the recipient's wording.
  ///
  /// In en, this message translates to:
  /// **'The link expires in 72 hours and can be used once.'**
  String get sharePredictionsLinkExpiry;

  /// Issue #1003: the claim-transfer confirm button — names the canonical 'Primary Guardian' role, not 'Owner'.
  ///
  /// In en, this message translates to:
  /// **'Become Primary Guardian'**
  String get claimProfileBecomeGuardianAction;

  /// Issue #1003: the claim-transfer intro — names the canonical 'Primary Guardian' role, not 'owner'.
  ///
  /// In en, this message translates to:
  /// **'Claiming this link makes you this profile\'s Primary Guardian. The parent who shared it keeps the role they chose, and every past entry stays with whoever originally logged it.'**
  String get claimProfileBody;

  /// Issue #1004 (tranche 1): shared catch-all error copy in the sharing flows (accept invite, accept prediction connection, claim profile, redeem prediction code). Moved verbatim from the literals it replaces.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get sharingUnexpectedError;

  /// Issue #1004 (tranche 1): accept-invite sheet personalized intro when the invite preview resolved.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited to join {profileName}\'s shared profile as {roleLabel}. Accepting will sync its cycle calendar and health logs to this device.'**
  String sharingAcceptInvitePreviewIntro(String profileName, String roleLabel);

  /// Issue #1004 (tranche 1): accept-invite sheet neutral intro used while the preview loads or is unavailable.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited to a shared profile in lunarlog. Accepting will sync its cycle calendar and health logs to this device.'**
  String get sharingAcceptInviteNeutralIntro;

  /// Issue #1004 (tranche 1): accept-invite sheet preview status while loading.
  ///
  /// In en, this message translates to:
  /// **'Loading invite details…'**
  String get sharingAcceptInvitePreviewLoading;

  /// Issue #1004 (tranche 1): accept-invite sheet preview status on a fetch error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load invite details, but you can still continue.'**
  String get sharingAcceptInvitePreviewError;

  /// Issue #1004 (tranche 1): accept-invite sheet preview status when the token returns no preview.
  ///
  /// In en, this message translates to:
  /// **'This invite link may have expired or already been used.'**
  String get sharingAcceptInvitePreviewUnavailable;

  /// Issue #1004 (tranche 1): accept-invite sheet title.
  ///
  /// In en, this message translates to:
  /// **'Join Shared Profile'**
  String get sharingAcceptInviteTitle;

  /// Issue #1004 (tranche 1): accept-invite sheet decline button.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get sharingAcceptInviteDecline;

  /// Issue #1004 (tranche 1): accept-invite sheet accept button.
  ///
  /// In en, this message translates to:
  /// **'Accept & Sync'**
  String get sharingAcceptInviteAccept;

  /// Issue #1004 (tranche 1): accept-invite sheet display-name field label.
  ///
  /// In en, this message translates to:
  /// **'Your display name (e.g. Dad, Mom, Grandma)'**
  String get sharingAcceptInviteNameLabel;

  /// Issue #1004 (tranche 1): accept-invite sheet display-name field hint.
  ///
  /// In en, this message translates to:
  /// **'Shows when you log entries'**
  String get sharingAcceptInviteNameHint;

  /// Issue #1004 (tranche 1): accept-prediction-connection sheet title.
  ///
  /// In en, this message translates to:
  /// **'Connect to cycle predictions'**
  String get sharingAcceptPredictionTitle;

  /// Issue #1004 (tranche 1): accept-prediction-connection sheet body.
  ///
  /// In en, this message translates to:
  /// **'Accepting adds a read-only calendar of their estimated period, fertile, ovulation, and PMS days. No notes, tags, or logs are ever shared or synced to this device.'**
  String get sharingAcceptPredictionBody;

  /// Issue #1004 (tranche 1): accept-prediction-connection sheet decline button.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get sharingAcceptPredictionDecline;

  /// Issue #1004 (tranche 1): accept-prediction-connection sheet connect button.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sharingAcceptPredictionConnect;

  /// Issue #1004 (tranche 1): claim-profile sheet title.
  ///
  /// In en, this message translates to:
  /// **'Become the Owner'**
  String get sharingClaimProfileTitle;

  /// Issue #1004 (tranche 1): claim-profile sheet decline button.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get sharingClaimProfileDecline;

  /// Issue #1004 (tranche 1): claim-profile sheet child-name field label.
  ///
  /// In en, this message translates to:
  /// **'Child\'s display name (optional)'**
  String get sharingClaimProfileChildNameLabel;

  /// Issue #1004 (tranche 1): claim-profile sheet child-name field hint.
  ///
  /// In en, this message translates to:
  /// **'Shows on the profile'**
  String get sharingClaimProfileChildNameHint;

  /// Issue #1004 (tranche 1): claim-profile sheet parent-label field label.
  ///
  /// In en, this message translates to:
  /// **'Label for the parent (optional)'**
  String get sharingClaimProfileParentLabelLabel;

  /// Issue #1004 (tranche 1): claim-profile sheet parent-label field hint.
  ///
  /// In en, this message translates to:
  /// **'Shows when they log entries'**
  String get sharingClaimProfileParentLabelHint;

  /// Issue #1004 (tranche 1): invite-guardian dialog unexpected create failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate invite. Please check your connection and try again.'**
  String get sharingInviteGuardianGenerateFailed;

  /// Issue #1004 (tranche 1): invite-guardian dialog preset picker label.
  ///
  /// In en, this message translates to:
  /// **'Role:'**
  String get sharingInviteGuardianRoleLabel;

  /// Issue #1004 (tranche 1): invite-guardian dialog co-parent preset choice.
  ///
  /// In en, this message translates to:
  /// **'Co-Parent (Can log, edit profile & invite)'**
  String get sharingInviteGuardianPresetCoParent;

  /// Issue #1004 (tranche 1): invite-guardian dialog caregiver preset choice.
  ///
  /// In en, this message translates to:
  /// **'Caregiver (Can log symptoms & periods)'**
  String get sharingInviteGuardianPresetCaregiver;

  /// Issue #1004 (tranche 1): invite-guardian dialog viewer preset choice.
  ///
  /// In en, this message translates to:
  /// **'Viewer (Read-only access)'**
  String get sharingInviteGuardianPresetViewer;

  /// Issue #1004 (tranche 1): invite-guardian dialog generated-state title.
  ///
  /// In en, this message translates to:
  /// **'Invitation Created'**
  String get sharingInviteGuardianCreatedTitle;

  /// Issue #1004 (tranche 1): invite-guardian dialog generated-state expiry note.
  ///
  /// In en, this message translates to:
  /// **'Expires in 48 hours. Can be redeemed once.'**
  String get sharingInviteGuardianExpiry;

  /// Issue #1004 (tranche 1): invite-guardian dialog in-dialog copy confirmation.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get sharingInviteGuardianCopied;

  /// Issue #1004 (tranche 1): invite-guardian dialog done button.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sharingInviteGuardianDone;

  /// Issue #1004 (tranche 1): invite-guardian dialog copy-link button.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get sharingInviteGuardianCopyLink;

  /// Issue #1004 (tranche 1): invite-guardian dialog share button.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sharingInviteGuardianShare;

  /// Issue #1004 (tranche 1): invite-guardian dialog title.
  ///
  /// In en, this message translates to:
  /// **'Invite guardian to {profileName}'**
  String sharingInviteGuardianTitle(String profileName);

  /// Issue #1004 (tranche 1): invite-guardian dialog nickname field label.
  ///
  /// In en, this message translates to:
  /// **'Nickname / Label (Optional)'**
  String get sharingInviteGuardianNicknameLabel;

  /// Issue #1004 (tranche 1): invite-guardian dialog nickname field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dad, Grandma, School Nurse'**
  String get sharingInviteGuardianNicknameHint;

  /// Issue #1004 (tranche 1): invite-guardian dialog help-card link label.
  ///
  /// In en, this message translates to:
  /// **'How do invitations work?'**
  String get sharingInviteGuardianHelpLabel;

  /// Issue #1004 (tranche 1): invite-guardian dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingInviteGuardianCancel;

  /// Issue #1004 (tranche 1): invite-guardian dialog create-link button.
  ///
  /// In en, this message translates to:
  /// **'Create Link'**
  String get sharingInviteGuardianCreateLink;

  /// Issue #1004 (tranche 1): manage-guardians screen generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingManageGuardiansCancel;

  /// Issue #1004 (tranche 1): confirm dialog title for revoking a prediction connection.
  ///
  /// In en, this message translates to:
  /// **'End prediction sharing?'**
  String get sharingManageGuardiansEndPredictionTitle;

  /// Issue #1004 (tranche 1): confirm dialog body for revoking a prediction connection.
  ///
  /// In en, this message translates to:
  /// **'They will immediately lose the shared predictions calendar. You can create a new connection any time.'**
  String get sharingManageGuardiansEndPredictionBody;

  /// Issue #1004 (tranche 1): destructive confirm action for revoking a prediction connection.
  ///
  /// In en, this message translates to:
  /// **'End sharing'**
  String get sharingManageGuardiansEndSharing;

  /// Issue #1004 (tranche 1): snackbar after a prediction connection is revoked.
  ///
  /// In en, this message translates to:
  /// **'Prediction sharing ended'**
  String get sharingManageGuardiansPredictionSharingEnded;

  /// Issue #1004 (tranche 1): snackbar when revoking a prediction connection fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to end sharing. Check connection.'**
  String get sharingManageGuardiansEndSharingFailed;

  /// Issue #1004 (tranche 1): first delete-profile confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete {profileName} permanently?'**
  String sharingManageGuardiansDeleteProfileTitle(String profileName);

  /// Issue #1004 (tranche 1): first delete-profile confirmation body.
  ///
  /// In en, this message translates to:
  /// **'This permanently erases every day entry, care note, and visit-prep item on this profile, and removes every guardian\'s access to it — including your own. Synced copies on every device are erased too.'**
  String get sharingManageGuardiansDeleteProfileStep1Body;

  /// Issue #1004 (tranche 1): first delete-profile confirmation continue action.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get sharingManageGuardiansContinue;

  /// Issue #1004 (tranche 1): second delete-profile confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Are you absolutely sure?'**
  String get sharingManageGuardiansDeleteProfileStep2Title;

  /// Issue #1004 (tranche 1): second delete-profile confirmation body.
  ///
  /// In en, this message translates to:
  /// **'{profileName}\'s history will be gone permanently, for every guardian on this profile. There is no undo.'**
  String sharingManageGuardiansDeleteProfileStep2Body(String profileName);

  /// Issue #1004 (tranche 1): final destructive delete-profile action.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get sharingManageGuardiansDeletePermanently;

  /// Issue #1004 (tranche 1): delete-profile failure while offline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t delete while offline. Check your connection and try again.'**
  String get sharingManageGuardiansDeleteOffline;

  /// Issue #1004 (tranche 1): generic delete-profile failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete profile. Check connection and try again.'**
  String get sharingManageGuardiansDeleteFailed;

  /// Issue #1004 (tranche 1): error when the sole primary guardian tries to leave.
  ///
  /// In en, this message translates to:
  /// **'You\'re now the only primary guardian, so you can\'t leave. Add another primary guardian first, then try again.'**
  String get sharingManageGuardiansSolePrimaryLeave;

  /// Issue #1004 (tranche 1): generic revoke-guardian failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove guardian. Check connection.'**
  String get sharingManageGuardiansRemoveFailed;

  /// Issue #1004 (tranche 1): confirm dialog title for revoking a guardian or leaving.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String sharingManageGuardiansRemoveTitle(String name);

  /// Issue #1004 (tranche 1): confirm dialog body when the caller removes herself.
  ///
  /// In en, this message translates to:
  /// **'You will leave this profile and no longer receive updates or sync its entries.'**
  String get sharingManageGuardiansLeaveBody;

  /// Issue #1004 (tranche 1): confirm dialog body when removing another guardian.
  ///
  /// In en, this message translates to:
  /// **'This guardian will lose access to {profileName}\'s calendar and entries.'**
  String sharingManageGuardiansRemoveBody(String profileName);

  /// Issue #1004 (tranche 1): destructive remove-guardian action.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get sharingManageGuardiansRemove;

  /// Issue #1004 (tranche 1): snackbar after a guardian is removed.
  ///
  /// In en, this message translates to:
  /// **'Removed {name}'**
  String sharingManageGuardiansRemoved(String name);

  /// Issue #1004 (tranche 1): confirm dialog title for cancelling a pending invitation.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation for {name}?'**
  String sharingManageGuardiansCancelInviteTitle(String name);

  /// Issue #1004 (tranche 1): confirm dialog body for cancelling a pending invitation.
  ///
  /// In en, this message translates to:
  /// **'The invite link will stop working immediately. You can send a new one any time.'**
  String get sharingManageGuardiansCancelInviteBody;

  /// Issue #1004 (tranche 1): decline action for the cancel-invitation dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep Invitation'**
  String get sharingManageGuardiansKeepInvitation;

  /// Issue #1004 (tranche 1): destructive confirm action for cancelling an invitation.
  ///
  /// In en, this message translates to:
  /// **'Cancel Invitation'**
  String get sharingManageGuardiansCancelInvitation;

  /// Issue #1004 (tranche 1): snackbar when cancelling an invitation fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to cancel invitation. Check connection.'**
  String get sharingManageGuardiansCancelInviteFailed;

  /// Issue #1004 (tranche 1): inline error when the pending-invitations list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load pending invitations.'**
  String get sharingManageGuardiansPendingLoadError;

  /// Issue #1004 (tranche 1): empty state for the pending-invitations section.
  ///
  /// In en, this message translates to:
  /// **'No pending invitations'**
  String get sharingManageGuardiansNoPending;

  /// Issue #1004 (tranche 1): pending-invitations section heading.
  ///
  /// In en, this message translates to:
  /// **'Pending invitations'**
  String get sharingManageGuardiansPendingTitle;

  /// Issue #1004 (tranche 1): pending-invitation row subtitle for an expired invitation.
  ///
  /// In en, this message translates to:
  /// **'{kindLabel} • Expired'**
  String sharingManageGuardiansPendingSubtitleExpired(String kindLabel);

  /// Issue #1004 (tranche 1): pending-invitation row subtitle with the live expiry label.
  ///
  /// In en, this message translates to:
  /// **'{kindLabel} • {expiry}'**
  String sharingManageGuardiansPendingSubtitle(String kindLabel, String expiry);

  /// Issue #1004 (tranche 1): resend action on an expired pending invitation.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get sharingManageGuardiansResend;

  /// Issue #1004 (tranche 1): expiry label once an invitation has lapsed.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get sharingManageGuardiansExpiryExpired;

  /// Issue #1004 (tranche 1): expiry label rounded to hours.
  ///
  /// In en, this message translates to:
  /// **'expires in {hours}h'**
  String sharingManageGuardiansExpiryHours(int hours);

  /// Issue #1004 (tranche 1): expiry label rounded to minutes.
  ///
  /// In en, this message translates to:
  /// **'expires in {minutes}m'**
  String sharingManageGuardiansExpiryMinutes(int minutes);

  /// Issue #1004 (tranche 1): manage-guardians app-bar title.
  ///
  /// In en, this message translates to:
  /// **'{profileName} Guardians'**
  String sharingManageGuardiansScreenTitle(String profileName);

  /// Issue #1004 (tranche 1): invite-guardian floating action label.
  ///
  /// In en, this message translates to:
  /// **'Invite guardian'**
  String get sharingManageGuardiansInviteAction;

  /// Issue #1004 (tranche 1): empty guardian list title.
  ///
  /// In en, this message translates to:
  /// **'No guardians linked yet'**
  String get sharingManageGuardiansNoGuardiansTitle;

  /// Issue #1004 (tranche 1): empty guardian list body.
  ///
  /// In en, this message translates to:
  /// **'Invite another guardian to sync and share tracking.'**
  String get sharingManageGuardiansNoGuardiansBody;

  /// Issue #1004 (tranche 1): prediction-connection section heading.
  ///
  /// In en, this message translates to:
  /// **'Predictions-only sharing'**
  String get sharingManageGuardiansPredictionsSectionTitle;

  /// Issue #1004 (tranche 1): prediction-connection section explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Shares estimated period, fertile, ovulation, and PMS days on a read-only calendar - never notes or logs. One connection.'**
  String get sharingManageGuardiansPredictionsSectionBody;

  /// Issue #1004 (tranche 1): prediction-connection notice on a minor's profile.
  ///
  /// In en, this message translates to:
  /// **'Prediction sharing is not available for a minor\'s profile.'**
  String get sharingManageGuardiansPredictionsMinor;

  /// Issue #1004 (tranche 1): primary-guardian action to arm a prediction connection.
  ///
  /// In en, this message translates to:
  /// **'Share predictions only...'**
  String get sharingManageGuardiansSharePredictionsAction;

  /// Issue #1004 (tranche 1): notice for a non-primary guardian on the prediction section.
  ///
  /// In en, this message translates to:
  /// **'Only the primary guardian can share predictions.'**
  String get sharingManageGuardiansPredictionsPrimaryOnly;

  /// Issue #1004 (tranche 1): prediction-connection tile title once active.
  ///
  /// In en, this message translates to:
  /// **'Sharing predictions'**
  String get sharingManageGuardiansSharingPredictions;

  /// Issue #1004 (tranche 1): inline pending marker on the prediction-connection tile.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get sharingManageGuardiansPendingBadge;

  /// Issue #1004 (tranche 1): prediction-connection tile subtitle once active.
  ///
  /// In en, this message translates to:
  /// **'Phases-only calendar • not a guardian'**
  String get sharingManageGuardiansPhasesOnlyCalendar;

  /// Issue #1004 (tranche 1): danger-zone section heading.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get sharingManageGuardiansDangerZoneTitle;

  /// Issue #1004 (tranche 1): danger-zone section explanatory copy.
  ///
  /// In en, this message translates to:
  /// **'Permanently erases this profile and everything logged on it, for every guardian. This cannot be undone.'**
  String get sharingManageGuardiansDangerZoneBody;

  /// Issue #1004 (tranche 1): danger-zone delete-profile action.
  ///
  /// In en, this message translates to:
  /// **'Delete profile permanently'**
  String get sharingManageGuardiansDeleteProfileAction;

  /// Issue #1004 (tranche 1): generic role-update failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to update role. Check connection.'**
  String get sharingManageGuardiansRoleUpdateFailed;

  /// Issue #1004 (tranche 1): confirm dialog title for a role change.
  ///
  /// In en, this message translates to:
  /// **'Change role to {newRoleLabel}?'**
  String sharingManageGuardiansChangeRoleTitle(String newRoleLabel);

  /// Issue #1004 (tranche 1): confirm dialog body for a role change. The consequence sentence is supplied by roleChangeConsequence.
  ///
  /// In en, this message translates to:
  /// **'{name} currently has {currentRoleLabel} access. {consequence} No new invitation is needed — the new role applies on their next sync.'**
  String sharingManageGuardiansChangeRoleBody(
    String name,
    String currentRoleLabel,
    String consequence,
  );

  /// Issue #1004 (tranche 1): confirm action for a role change.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get sharingManageGuardiansChangeRoleAction;

  /// Issue #1004 (tranche 1): snackbar after a role change.
  ///
  /// In en, this message translates to:
  /// **'Role updated to {newRoleLabel}'**
  String sharingManageGuardiansRoleUpdated(String newRoleLabel);

  /// Issue #1004 (tranche 1): suffix marking the caller's own guardian row.
  ///
  /// In en, this message translates to:
  /// **'(you)'**
  String get sharingManageGuardiansYouSuffix;

  /// Issue #1004 (tranche 1): notification-preferences app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get sharingNotificationPreferencesTitle;

  /// Issue #1004 (tranche 1): confirm dialog title when saving despite an unrecognised time zone.
  ///
  /// In en, this message translates to:
  /// **'Save without time zone?'**
  String get sharingNotificationPreferencesSaveWithoutTzTitle;

  /// Issue #1004 (tranche 1): confirm dialog body when saving despite an unrecognised time zone.
  ///
  /// In en, this message translates to:
  /// **'Your quiet hours will not adjust for your local time zone until this is resolved. Continue anyway?'**
  String get sharingNotificationPreferencesSaveWithoutTzBody;

  /// Issue #1004 (tranche 1): notification-preferences dialog cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingNotificationPreferencesCancel;

  /// Issue #1004 (tranche 1): save action that accepts the UTC-fallback time zone.
  ///
  /// In en, this message translates to:
  /// **'Save without time zone'**
  String get sharingNotificationPreferencesSaveWithoutTz;

  /// Issue #1004 (tranche 1): cadence selector title for log alerts.
  ///
  /// In en, this message translates to:
  /// **'Log alert delivery'**
  String get sharingNotificationPreferencesLogDeliveryTitle;

  /// Issue #1004 (tranche 1): cadence selector subtitle for log alerts.
  ///
  /// In en, this message translates to:
  /// **'Immediate, once a day, or off - extra alerts never exceed a daily limit and roll into the digest'**
  String get sharingNotificationPreferencesLogDeliverySubtitle;

  /// Issue #1004 (tranche 1): cadence selector title for cycle-start alerts.
  ///
  /// In en, this message translates to:
  /// **'Cycle-start alert delivery'**
  String get sharingNotificationPreferencesCycleStartDelivery;

  /// Issue #1004 (tranche 1): cadence selector title for high-severity alerts.
  ///
  /// In en, this message translates to:
  /// **'High-severity alert delivery'**
  String get sharingNotificationPreferencesHighSeverityDelivery;

  /// Issue #1004 (tranche 1): digest-time tile title.
  ///
  /// In en, this message translates to:
  /// **'Digest time'**
  String get sharingNotificationPreferencesDigestTimeTitle;

  /// Issue #1004 (tranche 1): digest-time tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'When daily digests are delivered in your time zone'**
  String get sharingNotificationPreferencesDigestTimeSubtitle;

  /// Issue #1004 (tranche 1): inline error when notification preferences fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load your notification settings.'**
  String get sharingNotificationPreferencesLoadError;

  /// Issue #1004 (tranche 1): discretion note at the top of notification preferences.
  ///
  /// In en, this message translates to:
  /// **'Alerts never show what was logged - just a generic reminder to open lunarlog.'**
  String get sharingNotificationPreferencesDiscretion;

  /// Issue #1004 (tranche 1): master alert toggle label.
  ///
  /// In en, this message translates to:
  /// **'Notify me when {profileName} logs an entry'**
  String sharingNotificationPreferencesNotifyOnLog(String profileName);

  /// Issue #1004 (tranche 1): narrowing toggle for cycle-start alerts.
  ///
  /// In en, this message translates to:
  /// **'Only notify on cycle start'**
  String get sharingNotificationPreferencesCycleStartOnly;

  /// Issue #1004 (tranche 1): narrowing toggle for high-severity alerts.
  ///
  /// In en, this message translates to:
  /// **'Notify on high-severity days'**
  String get sharingNotificationPreferencesHighSeverity;

  /// Issue #1004 (tranche 1): missed-entry threshold tile title.
  ///
  /// In en, this message translates to:
  /// **'Missed-entry reminder'**
  String get sharingNotificationPreferencesMissedEntryTitle;

  /// Issue #1004 (tranche 1): missed-entry threshold tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Check in when no entry has been logged for a while'**
  String get sharingNotificationPreferencesMissedEntrySubtitle;

  /// Issue #1004 (tranche 1): off option in the notification-preferences dropdowns.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get sharingNotificationPreferencesOff;

  /// Issue #1004 (tranche 1): one-day missed-entry threshold option.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get sharingNotificationPreferencesOneDay;

  /// Issue #1004 (tranche 1): two-day missed-entry threshold option.
  ///
  /// In en, this message translates to:
  /// **'2 days'**
  String get sharingNotificationPreferencesTwoDays;

  /// Issue #1004 (tranche 1): three-day missed-entry threshold option.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get sharingNotificationPreferencesThreeDays;

  /// Issue #1004 (tranche 1): quiet-hours start tile title.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours start'**
  String get sharingNotificationPreferencesQuietStart;

  /// Issue #1004 (tranche 1): quiet-hours end tile title.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours end'**
  String get sharingNotificationPreferencesQuietEnd;

  /// Issue #1004 (tranche 1): clear-quiet-hours action.
  ///
  /// In en, this message translates to:
  /// **'Clear quiet hours'**
  String get sharingNotificationPreferencesClearQuietHours;

  /// Issue #1004 (tranche 1): incoming prediction-connections app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Shared with me'**
  String get sharingPredictionConnectionsTitle;

  /// Issue #1004 (tranche 1): confirm dialog title for leaving a received prediction connection.
  ///
  /// In en, this message translates to:
  /// **'Stop receiving these predictions?'**
  String get sharingPredictionConnectionsStopTitle;

  /// Issue #1004 (tranche 1): confirm dialog body for leaving a received prediction connection.
  ///
  /// In en, this message translates to:
  /// **'You will stop seeing this profile\'s shared cycle calendar. The sharer can invite you again at any time.'**
  String get sharingPredictionConnectionsStopBody;

  /// Issue #1004 (tranche 1): prediction-connections generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingPredictionConnectionsCancel;

  /// Issue #1004 (tranche 1): destructive action to leave a received prediction connection.
  ///
  /// In en, this message translates to:
  /// **'Stop receiving'**
  String get sharingPredictionConnectionsStopAction;

  /// Issue #1004 (tranche 1): snackbar after leaving a received prediction connection.
  ///
  /// In en, this message translates to:
  /// **'Stopped receiving predictions'**
  String get sharingPredictionConnectionsStopped;

  /// Issue #1004 (tranche 1): snackbar when leaving a prediction connection fails.
  ///
  /// In en, this message translates to:
  /// **'Could not stop receiving. Check connection.'**
  String get sharingPredictionConnectionsStopFailed;

  /// Issue #1004 (tranche 1): snackbar when redeeming a prediction code fails without a typed reason.
  ///
  /// In en, this message translates to:
  /// **'Connection failed.'**
  String get sharingPredictionConnectionsFailed;

  /// Issue #1004 (tranche 1): inline error when incoming connections fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load connections.'**
  String get sharingPredictionConnectionsLoadError;

  /// Issue #1004 (tranche 1): empty incoming-connections title.
  ///
  /// In en, this message translates to:
  /// **'No shared predictions yet'**
  String get sharingPredictionConnectionsEmptyTitle;

  /// Issue #1004 (tranche 1): empty incoming-connections body.
  ///
  /// In en, this message translates to:
  /// **'When someone shares their cycle predictions with you, their calendar appears here.'**
  String get sharingPredictionConnectionsEmptyBody;

  /// Issue #1004 (tranche 1): incoming connection row title and calendar fallback name.
  ///
  /// In en, this message translates to:
  /// **'Cycle predictions'**
  String get sharingPredictionConnectionsCyclePredictions;

  /// Issue #1004 (tranche 1): incoming connection row subtitle.
  ///
  /// In en, this message translates to:
  /// **'Shared {date} • phases only'**
  String sharingPredictionConnectionsSharedSubtitle(String date);

  /// Issue #1004 (tranche 1): tooltip on the leave-connection icon.
  ///
  /// In en, this message translates to:
  /// **'Stop receiving'**
  String get sharingPredictionConnectionsStopTooltip;

  /// Issue #1004 (tranche 1): manual code entry confirm action.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sharingPredictionConnectionsConnect;

  /// Issue #1004 (tranche 1): inline error when the shared predictions fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load the shared predictions.'**
  String get sharingPredictionCalendarLoadError;

  /// Issue #1004 (tranche 1): phase calendar waiting state title.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first update'**
  String get sharingPredictionCalendarWaitingTitle;

  /// Issue #1004 (tranche 1): phase calendar waiting state body.
  ///
  /// In en, this message translates to:
  /// **'You\'re connected, but {profileName}\'s app hasn\'t shared its first predictions yet. They appear here automatically once it does - tap refresh to check again.'**
  String sharingPredictionCalendarWaitingBody(String profileName);

  /// Issue #1004 (tranche 1): phase calendar ended state title.
  ///
  /// In en, this message translates to:
  /// **'Connection ended'**
  String get sharingPredictionCalendarEndedTitle;

  /// Issue #1004 (tranche 1): phase calendar ended state body.
  ///
  /// In en, this message translates to:
  /// **'This prediction connection is no longer active.'**
  String get sharingPredictionCalendarEndedBody;

  /// Issue #1004 (tranche 1): confidence tier line in the phase calendar disclaimer banner.
  ///
  /// In en, this message translates to:
  /// **'Estimate confidence: {tierLabel}'**
  String sharingPredictionCalendarConfidence(String tierLabel);

  /// Issue #1004 (tranche 1): phase legend entry for period days.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get sharingPredictionCalendarLegendPeriod;

  /// Issue #1004 (tranche 1): phase legend entry for fertile days.
  ///
  /// In en, this message translates to:
  /// **'Fertile'**
  String get sharingPredictionCalendarLegendFertile;

  /// Issue #1004 (tranche 1): phase legend entry for ovulation days.
  ///
  /// In en, this message translates to:
  /// **'Ovulation'**
  String get sharingPredictionCalendarLegendOvulation;

  /// Issue #1004 (tranche 1): phase legend entry for PMS days.
  ///
  /// In en, this message translates to:
  /// **'PMS'**
  String get sharingPredictionCalendarLegendPms;

  /// Issue #1004 (tranche 1): share-predictions dialog unexpected create failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to create the connection. Please check your connection and try again.'**
  String get sharingSharePredictionsCreateFailed;

  /// Issue #1004 (tranche 1): share-predictions dialog generated-state title.
  ///
  /// In en, this message translates to:
  /// **'Connection created'**
  String get sharingSharePredictionsCreatedTitle;

  /// Issue #1004 (tranche 1): share-predictions dialog generated-state share line.
  ///
  /// In en, this message translates to:
  /// **'Send this single-use link to the person who should see {profileName}\'s predictions:'**
  String sharingSharePredictionsSendLink(String profileName);

  /// Issue #1004 (tranche 1): share-predictions dialog generated-state body.
  ///
  /// In en, this message translates to:
  /// **'They will see estimated period, fertile, ovulation, and PMS days on a read-only calendar — no notes or logs. {expiry}'**
  String sharingSharePredictionsCreatedBody(String expiry);

  /// Issue #1004 (tranche 1): share-predictions dialog in-dialog copy confirmation.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get sharingSharePredictionsCopied;

  /// Issue #1004 (tranche 1): share-predictions dialog done action.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sharingSharePredictionsDone;

  /// Issue #1004 (tranche 1): share-predictions dialog title.
  ///
  /// In en, this message translates to:
  /// **'Share predictions of {profileName}'**
  String sharingSharePredictionsTitle(String profileName);

  /// Issue #1004 (tranche 1): share-predictions dialog explanatory body.
  ///
  /// In en, this message translates to:
  /// **'Creates a read-only connection that sees estimated period, fertile, ovulation, and PMS days — never notes, tags, or logs. One connection per profile.'**
  String get sharingSharePredictionsBody;

  /// Issue #1004 (tranche 1): share-predictions dialog nickname field label.
  ///
  /// In en, this message translates to:
  /// **'Nickname / Label (Optional)'**
  String get sharingSharePredictionsNicknameLabel;

  /// Issue #1004 (tranche 1): share-predictions dialog nickname field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Partner, Aunt'**
  String get sharingSharePredictionsNicknameHint;

  /// Issue #1004 (tranche 1): share-predictions dialog cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingSharePredictionsCancel;

  /// Issue #1004 (tranche 1): share-predictions dialog create-link action.
  ///
  /// In en, this message translates to:
  /// **'Create Link'**
  String get sharingSharePredictionsCreateLink;

  /// Issue #1004 (tranche 1): transfer-ownership app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Transfer {profileName}\'s Profile'**
  String sharingTransferOwnershipScreenTitle(String profileName);

  /// Issue #1004 (tranche 1): confirm dialog title before arming a transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership?'**
  String get sharingTransferOwnershipConfirmTitle;

  /// Issue #1004 (tranche 1): transfer-ownership generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sharingTransferOwnershipCancel;

  /// Issue #1004 (tranche 1): destructive confirm action for arming a transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get sharingTransferOwnershipTransferAction;

  /// Issue #1004 (tranche 1): snackbar after cancelling an orphaned transfer.
  ///
  /// In en, this message translates to:
  /// **'Pending transfer cancelled'**
  String get sharingTransferOwnershipPendingCancelled;

  /// Issue #1004 (tranche 1): snackbar after cancelling a generated transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer cancelled'**
  String get sharingTransferOwnershipCancelled;

  /// Issue #1004 (tranche 1): snackbar after copying a transfer link.
  ///
  /// In en, this message translates to:
  /// **'Transfer link copied to clipboard'**
  String get sharingTransferOwnershipLinkCopied;

  /// Issue #1004 (tranche 1): armable-state section heading.
  ///
  /// In en, this message translates to:
  /// **'What changes'**
  String get sharingTransferOwnershipWhatChanges;

  /// Issue #1004 (tranche 1): armable-state bullet.
  ///
  /// In en, this message translates to:
  /// **'You keep the role you choose below.'**
  String get sharingTransferOwnershipBulletKeepRole;

  /// Issue #1004 (tranche 1): armable-state bullet.
  ///
  /// In en, this message translates to:
  /// **'They can remove your access at any time.'**
  String get sharingTransferOwnershipBulletRemoveAccess;

  /// Issue #1004 (tranche 1): armable-state bullet.
  ///
  /// In en, this message translates to:
  /// **'If they later delete their account, this profile\'s history goes with it.'**
  String get sharingTransferOwnershipBulletDeleteAccount;

  /// Issue #1004 (tranche 1): transfer help-card link label.
  ///
  /// In en, this message translates to:
  /// **'How does the transfer work?'**
  String get sharingTransferOwnershipHelpLabel;

  /// Issue #1004 (tranche 1): post-transfer role picker heading.
  ///
  /// In en, this message translates to:
  /// **'Your role after the transfer'**
  String get sharingTransferOwnershipRoleAfterTitle;

  /// Issue #1004 (tranche 1): recipient label field label.
  ///
  /// In en, this message translates to:
  /// **'Recipient label (optional)'**
  String get sharingTransferOwnershipRecipientLabel;

  /// Issue #1004 (tranche 1): recipient label field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sam'**
  String get sharingTransferOwnershipRecipientHint;

  /// Issue #1004 (tranche 1): arm-transfer action.
  ///
  /// In en, this message translates to:
  /// **'Transfer Ownership'**
  String get sharingTransferOwnershipAction;

  /// Issue #1004 (tranche 1): orphaned-transfer state title.
  ///
  /// In en, this message translates to:
  /// **'A Transfer Is Already Pending'**
  String get sharingTransferOwnershipPendingTitle;

  /// Issue #1004 (tranche 1): orphaned-transfer state body.
  ///
  /// In en, this message translates to:
  /// **'A transfer for {profileName} is already pending, but its link is not available on this screen (it may have been created earlier or on another device). Cancel it to start a new one.'**
  String sharingTransferOwnershipPendingBody(String profileName);

  /// Issue #1004 (tranche 1): transfer expiry line.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String sharingTransferOwnershipExpires(String date);

  /// Issue #1004 (tranche 1): cancel an orphaned transfer action.
  ///
  /// In en, this message translates to:
  /// **'Cancel Pending Transfer'**
  String get sharingTransferOwnershipCancelPending;

  /// Issue #1004 (tranche 1): generated-transfer state title.
  ///
  /// In en, this message translates to:
  /// **'Transfer Ready'**
  String get sharingTransferOwnershipReadyTitle;

  /// Issue #1004 (tranche 1): generated-transfer state share line.
  ///
  /// In en, this message translates to:
  /// **'Share this single-use link with {profileName}:'**
  String sharingTransferOwnershipShareLink(String profileName);

  /// Issue #1004 (tranche 1): copy-transfer-link action.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get sharingTransferOwnershipCopyLink;

  /// Issue #1004 (tranche 1): share-transfer-link action.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get sharingTransferOwnershipShare;

  /// Issue #1004 (tranche 1): cancel a generated transfer action.
  ///
  /// In en, this message translates to:
  /// **'Cancel transfer'**
  String get sharingTransferOwnershipCancelTransfer;

  /// Issue #1004 (tranche 1): activity-feed app-bar title.
  ///
  /// In en, this message translates to:
  /// **'{profileName} Activity'**
  String sharingActivityFeedScreenTitle(String profileName);

  /// Issue #1004 (tranche 1): single-guardian empty-state title.
  ///
  /// In en, this message translates to:
  /// **'Just you for now'**
  String get sharingActivityFeedJustYouTitle;

  /// Issue #1004 (tranche 1): single-guardian empty-state body.
  ///
  /// In en, this message translates to:
  /// **'This profile has one guardian, so there is no shared activity to review. When a second guardian joins, both of your changes appear here.'**
  String get sharingActivityFeedJustYouBody;

  /// Issue #1004 (tranche 1): no-activity empty-state title.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get sharingActivityFeedNoActivityTitle;

  /// Issue #1004 (tranche 1): no-activity empty-state body.
  ///
  /// In en, this message translates to:
  /// **'Changes either guardian makes to this profile will appear here.'**
  String get sharingActivityFeedNoActivityBody;

  /// Issue #1004 (tranche 1): activity-feed list caption.
  ///
  /// In en, this message translates to:
  /// **'Newest first. Each row shows a day’s latest change — earlier edits by the same guardian are not recorded separately.'**
  String get sharingActivityFeedCaption;

  /// Issue #1004 (tranche 1): activity row verb for a logged entry.
  ///
  /// In en, this message translates to:
  /// **'Logged'**
  String get sharingActivityFeedVerbLogged;

  /// Issue #1004 (tranche 1): activity row verb for an updated entry.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get sharingActivityFeedVerbUpdated;

  /// Issue #1004 (tranche 1): activity row verb for a removed entry.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get sharingActivityFeedVerbRemoved;

  /// Issue #1004 (tranche 1): activity row title with an attributed actor.
  ///
  /// In en, this message translates to:
  /// **'{verb} by {actor}'**
  String sharingActivityFeedByLineActor(String verb, String actor);

  /// Issue #1004 (tranche 1): activity row title for an unattributed entry.
  ///
  /// In en, this message translates to:
  /// **'Entry {verb}'**
  String sharingActivityFeedByLineNoActor(String verb);

  /// Issue #1004 (tranche 1): merge-outcome row title without an actor.
  ///
  /// In en, this message translates to:
  /// **'Sync merge kept one version'**
  String get sharingActivityFeedMergeKeptOne;

  /// Issue #1004 (tranche 1): merge-outcome row title with a possessive actor.
  ///
  /// In en, this message translates to:
  /// **'Sync merge kept {possessive} version'**
  String sharingActivityFeedMergeKeptPossessive(String possessive);

  /// Issue #1004 (tranche 1): access-removed row title without an actor.
  ///
  /// In en, this message translates to:
  /// **'A guardian no longer has access'**
  String get sharingActivityFeedAccessRemovedNoActor;

  /// Issue #1004 (tranche 1): access-removed row title with an actor.
  ///
  /// In en, this message translates to:
  /// **'{actor} no longer has access'**
  String sharingActivityFeedAccessRemovedActor(String actor);

  /// Issue #1004 (tranche 1): access-removed row subtitle.
  ///
  /// In en, this message translates to:
  /// **'Access to this profile was removed'**
  String get sharingActivityFeedAccessRemovedSubtitle;

  /// Issue #1004 (tranche 1): entry subtitle date fragment.
  ///
  /// In en, this message translates to:
  /// **'for {date}'**
  String sharingActivityFeedForDate(String date);

  /// Issue #1004 (tranche 1): entry subtitle original-logger fragment.
  ///
  /// In en, this message translates to:
  /// **'logged by {actor}'**
  String sharingActivityFeedLoggedBy(String actor);

  /// Issue #1004 (tranche 1): entry subtitle tag-count fragment.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tag} other{{count} tags}}'**
  String sharingActivityFeedTagCount(int count);

  /// Issue #1004 (tranche 1): entry subtitle note-presence fragment.
  ///
  /// In en, this message translates to:
  /// **'note'**
  String get sharingActivityFeedNote;

  /// Issue #1004 (tranche 1): fallback actor label for a merge-outcome row.
  ///
  /// In en, this message translates to:
  /// **'one guardian'**
  String get sharingActivityFeedOneGuardian;

  /// Issue #1004 (tranche 1): merge-outcome subtitle fragment.
  ///
  /// In en, this message translates to:
  /// **'flow and note values were'**
  String get sharingActivityFeedDiscardedFlowAndNote;

  /// Issue #1004 (tranche 1): merge-outcome subtitle fragment.
  ///
  /// In en, this message translates to:
  /// **'note was'**
  String get sharingActivityFeedDiscardedNote;

  /// Issue #1004 (tranche 1): merge-outcome subtitle fragment.
  ///
  /// In en, this message translates to:
  /// **'flow value was'**
  String get sharingActivityFeedDiscardedFlow;

  /// Issue #1004 (tranche 1): merge-outcome row subtitle.
  ///
  /// In en, this message translates to:
  /// **'{possessive} {what} discarded in a same-date merge'**
  String sharingActivityFeedMergeDiscarded(String possessive, String what);

  /// Issue #1004 (tranche 1): New chip on an unseen activity row.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get sharingActivityFeedNewBadge;

  /// Issue #1004 (tranche 1): possessive form when the actor is the current user.
  ///
  /// In en, this message translates to:
  /// **'your'**
  String get sharingActivityFeedPossessiveYou;

  /// Issue #1004 (tranche 1): possessive form for a named actor.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s'**
  String sharingActivityFeedPossessiveName(String name);

  /// Issue #1004 (tranche 1): co-managed indicator tooltip on a profile sharing row.
  ///
  /// In en, this message translates to:
  /// **'Shared · {count} guardians'**
  String sharingProfileSharingSharedTooltip(int count);

  /// Issue #1004 (tranche 1): pending-invitation badge tooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pending invitation} other{{count} pending invitations}}'**
  String sharingPendingInviteBadgePendingCount(int count);

  /// Issue #1004 (tranche 1): expired-invitation badge tooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 invitation expired} other{{count} invitations expired}}'**
  String sharingPendingInviteBadgeExpiredCount(int count);

  /// Issue #1004 (tranche 3): the lock screen's nested MaterialApp title.
  ///
  /// In en, this message translates to:
  /// **'lunarlog'**
  String get gateLockScreenAppTitle;

  /// Issue #1004 (tranche 3): headline on the locked screen.
  ///
  /// In en, this message translates to:
  /// **'lunarlog is locked'**
  String get gateLockScreenTitle;

  /// Issue #1004 (tranche 3): body under the locked headline.
  ///
  /// In en, this message translates to:
  /// **'Everything logged on this device stays protected. Unlock to continue.'**
  String get gateLockScreenProtectedBody;

  /// Issue #1004 (tranche 3): shown when the device-credential prompt was declined.
  ///
  /// In en, this message translates to:
  /// **'Not unlocked. The profiles on this device stay hidden until the device credential is accepted.'**
  String get gateLockScreenDeniedBody;

  /// Issue #1004 (tranche 3): primary unlock action on the locked screen.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get gateLockScreenUnlockButton;

  /// Issue #1004 (tranche 3): body shown when no device credential is enrolled.
  ///
  /// In en, this message translates to:
  /// **'This device has no screen lock set. lunarlog protects your family\'s data using your device\'s own screen lock, so it can\'t open until you add one — a passcode, PIN, pattern, or biometric lock all work.'**
  String get gateLockScreenNoCredentialBody;

  /// Issue #1004 (tranche 3): action opening the platform device settings.
  ///
  /// In en, this message translates to:
  /// **'Open device settings'**
  String get gateLockScreenOpenDeviceSettings;

  /// Issue #1004 (tranche 3): retry action on the locked screen.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get gateLockScreenTryAgain;

  /// Issue #1004 (tranche 3): alternate action in the current-PIN authorization dialog.
  ///
  /// In en, this message translates to:
  /// **'Use device credential instead'**
  String get gatePinAuthorizationUseDeviceCredential;

  /// Issue #1004 (tranche 3): cancel action in the current-PIN authorization dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gatePinAuthorizationCancel;

  /// Issue #1004 (tranche 3): cancel action in the turn-off-PIN confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gatePinSettingsRemoveCancel;

  /// Issue #1004 (tranche 3): title of the screenshot consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Attach a screenshot?'**
  String get feedbackAttachmentConsentTitle;

  /// Issue #1004 (tranche 3): body of the screenshot consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Screenshots of this app usually contain cycle data for a family member. Only attach one if it helps explain the issue.'**
  String get feedbackAttachmentConsentBody;

  /// Issue #1004 (tranche 3): cancel action of the screenshot consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get feedbackAttachmentConsentCancel;

  /// Issue #1004 (tranche 3): continue action of the screenshot consent dialog.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get feedbackAttachmentConsentContinue;

  /// Issue #1004 (tranche 3): button that opens the screenshot consent flow.
  ///
  /// In en, this message translates to:
  /// **'Add screenshot'**
  String get feedbackAttachmentAddScreenshot;

  /// Issue #1004 (tranche 3): app-bar title of the feedback screen.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackScreenTitle;

  /// Issue #1004 (tranche 3): label above the feedback category chips.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get feedbackScreenCategoryLabel;

  /// Issue #1004 (tranche 3): label of the feedback message field.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get feedbackScreenMessageLabel;

  /// Issue #1004 (tranche 3): label of the feedback reply-email field.
  ///
  /// In en, this message translates to:
  /// **'Reply email'**
  String get feedbackScreenReplyEmailLabel;

  /// Issue #1004 (tranche 3): title of the diagnostics toggle.
  ///
  /// In en, this message translates to:
  /// **'Include diagnostics'**
  String get feedbackScreenDiagnosticsTitle;

  /// Issue #1004 (tranche 3): subtitle of the diagnostics toggle.
  ///
  /// In en, this message translates to:
  /// **'App version, OS, device model, and recent activity.'**
  String get feedbackScreenDiagnosticsSubtitle;

  /// Issue #1004 (tranche 3): toggle revealing the diagnostics preview.
  ///
  /// In en, this message translates to:
  /// **'See what will be attached'**
  String get feedbackScreenDiagnosticsPreview;

  /// Issue #1004 (tranche 3): submit button of the feedback screen.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackScreenSendButton;

  /// Issue #1004 (tranche 3): validation error for an over-long feedback message.
  ///
  /// In en, this message translates to:
  /// **'Message must be 4000 characters or fewer.'**
  String get feedbackScreenMessageTooLong;

  /// Issue #1004 (tranche 3): validation error for an invalid reply email.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid reply email address.'**
  String get feedbackScreenReplyEmailInvalid;

  /// Issue #1004 (tranche 3): confirmation shown after a feedback submission.
  ///
  /// In en, this message translates to:
  /// **'Thanks — we\'ll get back to you at {email}.'**
  String feedbackScreenThanks(String email);

  /// Issue #1004 (tranche 3): app-bar title of the support history screen.
  ///
  /// In en, this message translates to:
  /// **'Support history'**
  String get supportHistoryTitle;

  /// Issue #1004 (tranche 3): empty-state title of the support history screen.
  ///
  /// In en, this message translates to:
  /// **'No feedback yet'**
  String get supportHistoryEmptyTitle;

  /// Issue #1004 (tranche 3): empty-state body of the support history screen.
  ///
  /// In en, this message translates to:
  /// **'Reports you send from Settings appear here.'**
  String get supportHistoryEmptyBody;

  /// Issue #1004 (tranche 3): retry action after a support history load failure.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get supportHistoryRetry;

  /// Issue #1004 (tranche 3): label of the reply field on a support ticket.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get supportHistoryReplyLabel;

  /// Issue #1004 (tranche 3): send action on a support ticket reply.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get supportHistorySend;

  /// Issue #1004 (tranche 3): unarchive action on an archived profile detail.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get profileDetailUnarchive;

  /// Issue #1004 (tranche 3): label of the profile detail overview tab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get profileDetailOverviewTab;

  /// Issue #1004 (tranche 3): label of the profile detail calendar tab.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get profileDetailCalendarTab;

  /// Issue #1004 (tranche 3): suffix appended to an archived profile's title.
  ///
  /// In en, this message translates to:
  /// **' (archived)'**
  String get profileDetailArchivedSuffix;

  /// Issue #1004 (tranche 3): co-managed indicator chip label.
  ///
  /// In en, this message translates to:
  /// **'Shared · {count} guardians'**
  String profileDetailSharedGuardians(int count);

  /// Issue #1004 (tranche 3): app-bar title of the profile picker.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profilePickerTitle;

  /// Issue #1004 (tranche 3): empty-state title of the profile picker.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet'**
  String get profilePickerEmptyTitle;

  /// Issue #1004 (tranche 3): empty-state body of the profile picker.
  ///
  /// In en, this message translates to:
  /// **'Add a profile to start tracking.'**
  String get profilePickerEmptyBody;

  /// Issue #1004 (tranche 3): empty-state primary action of the profile picker.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get profilePickerEmptyAddAction;

  /// Issue #1004 (tranche 3): archived section header on the profile picker.
  ///
  /// In en, this message translates to:
  /// **'Archived ({count})'**
  String profilePickerArchivedHeader(int count);

  /// Issue #1004 (tranche 3): profile row subtitle naming the creation date.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String profilePickerCreated(String date);

  /// Issue #1004 (tranche 3): section header for owned profiles.
  ///
  /// In en, this message translates to:
  /// **'My profiles'**
  String get profilePickerMyProfilesHeader;

  /// Issue #1004 (tranche 3): section header for profiles shared with the operator.
  ///
  /// In en, this message translates to:
  /// **'Shared with me'**
  String get profilePickerSharedWithMeHeader;

  /// Issue #1004 (tranche 3): profile row menu item opening Manage Guardians.
  ///
  /// In en, this message translates to:
  /// **'Guardians'**
  String get profilePickerMenuGuardians;

  /// Issue #1004 (tranche 3): archive action on a profile row and its confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get profileArchive;

  /// Issue #1004 (tranche 3): derived minor status in the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Counts as a minor (derived from birth year)'**
  String get profileDialogCountsAsMinor;

  /// Issue #1004 (tranche 3): derived adult status in the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Counts as an adult (derived from birth year)'**
  String get profileDialogCountsAsAdult;

  /// Issue #1004 (tranche 3): title of the create-profile dialog.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get profileDialogAddTitle;

  /// Issue #1004 (tranche 3): label of the optional birth-year field.
  ///
  /// In en, this message translates to:
  /// **'Birth year (optional)'**
  String get profileDialogBirthYearLabel;

  /// Issue #1004 (tranche 3): empty option in the relationship dropdown.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get profileDialogRelationshipNone;

  /// Issue #1004 (tranche 3): cancel action of the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileDialogCancel;

  /// Issue #1004 (tranche 3): create action of the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get profileDialogCreate;

  /// Issue #1004 (tranche 3): save action of the profile edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileDialogSave;

  /// Issue #1004 (tranche 3): title of the archive-profile confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String profileArchiveConfirmTitle(String name);

  /// Issue #1004 (tranche 3): body of the archive-profile confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'The profile moves to the archived list and out of everyday use. Its history stays on this device and can be restored at any time.'**
  String get profileArchiveConfirmBody;

  /// Issue #1004 (tranche 3): cancel action of the archive-profile confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileArchiveConfirmCancel;

  /// Issue #1004 (tranche 3): confirm action of the archive-profile confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get profileArchiveConfirmButton;

  /// Issue #1004 (tranche 3): error shown when first-run profile creation fails.
  ///
  /// In en, this message translates to:
  /// **'Could not create the profile. Please try again.'**
  String get firstRunCreateError;

  /// Issue #1004 (tranche 3): app-bar title of the care notes screen.
  ///
  /// In en, this message translates to:
  /// **'{name} Care'**
  String careNotesTitle(String name);

  /// Issue #1004 (tranche 3): read-only reason on an archived profile's care notes.
  ///
  /// In en, this message translates to:
  /// **'This profile is archived.'**
  String get careNotesReadOnlyArchived;

  /// Issue #1004 (tranche 3): section header of the care notes list.
  ///
  /// In en, this message translates to:
  /// **'Care notes'**
  String get careNotesSectionTitle;

  /// Issue #1004 (tranche 3): empty state of the care notes list.
  ///
  /// In en, this message translates to:
  /// **'No care notes yet.'**
  String get careNotesEmpty;

  /// Issue #1004 (tranche 3): label of the add-care-note field.
  ///
  /// In en, this message translates to:
  /// **'Add a care note'**
  String get careNotesAddLabel;

  /// Issue #1004 (tranche 3): hint of the add-care-note field.
  ///
  /// In en, this message translates to:
  /// **'Standing notes for everyone caring for this profile'**
  String get careNotesAddHint;

  /// Issue #1004 (tranche 3): add-care-note action.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get careNotesAddButton;

  /// Issue #1004 (tranche 3): title of the delete-care-note confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this care note?'**
  String get careNotesDeleteTitle;

  /// Issue #1004 (tranche 3): body of the delete-care-note confirmation.
  ///
  /// In en, this message translates to:
  /// **'Every guardian with access to this profile can see this note. Deleting it removes it for everyone and cannot be undone.'**
  String get careNotesDeleteBody;

  /// Issue #1004 (tranche 3): cancel action of the delete-care-note confirmation.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get careNotesDeleteCancel;

  /// Issue #1004 (tranche 3): confirm action of the delete-care-note confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get careNotesDeleteConfirm;

  /// Issue #1004 (tranche 3): lowercase attribution for the current operator.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get careNotesActorYou;

  /// Issue #1004 (tranche 3): fallback attribution for an unknown guardian.
  ///
  /// In en, this message translates to:
  /// **'Guardian'**
  String get careNotesActorGuardian;

  /// Issue #1004 (tranche 3): error after a failed care-note save.
  ///
  /// In en, this message translates to:
  /// **'Could not save the care note.'**
  String get careNotesSaveError;

  /// Issue #1004 (tranche 3): error after a failed prep-item add.
  ///
  /// In en, this message translates to:
  /// **'Could not add the prep item.'**
  String get careNotesAddPrepError;

  /// Issue #1004 (tranche 3): error after a failed supply-item add.
  ///
  /// In en, this message translates to:
  /// **'Could not add the supply item.'**
  String get careNotesAddSupplyError;

  /// Issue #1004 (tranche 3): error after a failed prep-item update.
  ///
  /// In en, this message translates to:
  /// **'Could not update the prep item.'**
  String get careNotesUpdatePrepError;

  /// Issue #1004 (tranche 3): error after a failed prep-item removal.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the prep item.'**
  String get careNotesRemovePrepError;

  /// Issue #1004 (tranche 3): error after a failed care-note removal.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the care note.'**
  String get careNotesRemoveNoteError;

  /// Issue #1004 (tranche 3): error after a failed clear-checked action.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the checked items.'**
  String get careNotesClearCheckedError;

  /// Issue #1004 (tranche 3): error after a failed clear-stocked action.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the stocked items.'**
  String get careNotesClearStockedError;

  /// Issue #1004 (tranche 3): section header of the visit-prep checklist.
  ///
  /// In en, this message translates to:
  /// **'Visit prep'**
  String get careVisitPrepSectionTitle;

  /// Issue #1004 (tranche 3): empty state of the visit-prep checklist.
  ///
  /// In en, this message translates to:
  /// **'No prep items yet.'**
  String get careVisitPrepEmpty;

  /// Issue #1004 (tranche 3): action clearing checked visit-prep items.
  ///
  /// In en, this message translates to:
  /// **'Clear checked ({count})'**
  String careVisitPrepClearChecked(int count);

  /// Issue #1004 (tranche 3): label of the add-prep-item field.
  ///
  /// In en, this message translates to:
  /// **'Add a prep item'**
  String get careVisitPrepAddLabel;

  /// Issue #1004 (tranche 3): hint of the add-prep-item field.
  ///
  /// In en, this message translates to:
  /// **'A question or to-bring for the next appointment'**
  String get careVisitPrepAddHint;

  /// Issue #1004 (tranche 3): add-prep-item action.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get careVisitPrepAddButton;

  /// Issue #1004 (tranche 3): attribution verb for a checked prep item.
  ///
  /// In en, this message translates to:
  /// **'Checked by'**
  String get careVisitPrepCheckedVerb;

  /// Issue #1004 (tranche 3): section header of the household supplies list.
  ///
  /// In en, this message translates to:
  /// **'Supplies'**
  String get careSuppliesSectionTitle;

  /// Issue #1004 (tranche 3): empty state of the household supplies list.
  ///
  /// In en, this message translates to:
  /// **'No supplies tracked yet.'**
  String get careSuppliesEmpty;

  /// Issue #1004 (tranche 3): action clearing stocked supply items.
  ///
  /// In en, this message translates to:
  /// **'Clear stocked ({count})'**
  String careSuppliesClearStocked(int count);

  /// Issue #1004 (tranche 3): label of the add-supply-item field.
  ///
  /// In en, this message translates to:
  /// **'Add a supply item'**
  String get careSuppliesAddLabel;

  /// Issue #1004 (tranche 3): hint of the add-supply-item field.
  ///
  /// In en, this message translates to:
  /// **'Something to keep stocked, e.g. liners'**
  String get careSuppliesAddHint;

  /// Issue #1004 (tranche 3): add-supply-item action.
  ///
  /// In en, this message translates to:
  /// **'Add supply'**
  String get careSuppliesAddButton;

  /// Issue #1004 (tranche 3): attribution verb for a stocked supply item.
  ///
  /// In en, this message translates to:
  /// **'Stocked by'**
  String get careSuppliesStockedVerb;

  /// Issue #1004 (tranche 3): restock nudge title naming the due date.
  ///
  /// In en, this message translates to:
  /// **'Restock before {date}'**
  String careRestockBefore(String date);

  /// Issue #1004 (tranche 3): label of the guardian-note field.
  ///
  /// In en, this message translates to:
  /// **'Your note for this day'**
  String get guardianNotesFieldLabel;

  /// Issue #1004 (tranche 3): fallback author name for a guardian note.
  ///
  /// In en, this message translates to:
  /// **'Guardian'**
  String get guardianNotesGuardianFallback;

  /// Web banner for a build with sync off (LUNARLOG_WEB_SYNC unset): no account, no token, not for real data. Epic #831.
  ///
  /// In en, this message translates to:
  /// **'Development build — not for real data.'**
  String get webBannerDevCopy;

  /// Web banner when LUNARLOG_WEB_SYNC=true made web a first-class client (epic #831): the browser holds synced family data unencrypted alongside the session. Deliberately never says 'not for real data'.
  ///
  /// In en, this message translates to:
  /// **'Browser build — this browser stores a copy of the signed-in profiles\' data unencrypted, plus your sign-in. Signing out clears it.'**
  String get webBannerSyncedCopy;

  /// Tooltip/label on the browser-build notice's per-session dismiss button (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get webBrowserNoticeDismissTooltip;

  /// Action on the web banner opening the confirm-guarded local wipe (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Wipe local data'**
  String get webWipeAction;

  /// Title of the web banner's local-wipe confirmation (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Erase all local data?'**
  String get webWipeConfirmTitle;

  /// Local-wipe confirmation body for a sync-off web build (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Erases all data stored in this browser. This cannot be undone.'**
  String get webWipeConfirmDevBody;

  /// Local-wipe confirmation body for a sync-enabled web build, naming that the account copy is not touched (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Erases all data stored in this browser and signs out. This cannot be undone here; data already in your account stays there.'**
  String get webWipeConfirmSyncedBody;

  /// Cancel action of the web local-wipe confirmation (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get webWipeCancel;

  /// Confirm action of the web local-wipe confirmation (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Erase everything'**
  String get webWipeConfirmAction;

  /// Snackbar after the web local wipe completes (epic #831).
  ///
  /// In en, this message translates to:
  /// **'All local data erased.'**
  String get webWipeDone;

  /// Title of the one-time web first-run acknowledgement for a sync-off build (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Development build'**
  String get webFirstRunDevTitle;

  /// Body of the one-time web first-run acknowledgement for a sync-off build (epic #831).
  ///
  /// In en, this message translates to:
  /// **'This is a development build, not for real data. Data in this browser is not encrypted and not backed up.'**
  String get webFirstRunDevBody;

  /// Title of the one-time web first-run acknowledgement when the build is a first-class (sync-enabled) client (epic #831).
  ///
  /// In en, this message translates to:
  /// **'Using lunarlog in this browser'**
  String get webFirstRunSyncedTitle;

  /// Body of the one-time web first-run acknowledgement when LUNARLOG_WEB_SYNC=true; the honest browser-storage story that replaces the old 'not for real data' wording (epic #831).
  ///
  /// In en, this message translates to:
  /// **'This browser keeps an unencrypted copy of the profiles you can see — including synced family data — and your sign-in. Anyone who uses this browser can read it. Signing out removes the copy from this browser; your account\'s data stays in your account and can sync again later.'**
  String get webFirstRunSyncedBody;

  /// Acknowledge button of the one-time web first-run acknowledgement (epic #831).
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get webFirstRunAcknowledge;

  /// Issue #1004 (tranche 2): account-mismatch screen app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Different account'**
  String get accountMismatchTitle;

  /// Issue #1004 (tranche 2): account-mismatch body when no email is known.
  ///
  /// In en, this message translates to:
  /// **'This device holds data that belongs to a different account than the one you just signed in to.'**
  String get accountMismatchBodyNoEmail;

  /// Issue #1004 (tranche 2): account-mismatch body naming the signed-in email.
  ///
  /// In en, this message translates to:
  /// **'This device holds data that belongs to a different account than {email}.'**
  String accountMismatchBodyWithEmail(String email);

  /// Issue #1004 (tranche 2): account-mismatch explainer paragraph.
  ///
  /// In en, this message translates to:
  /// **'This device is set up for a different account. This happens when Apple\'s Hide My Email created a new account, or when you chose a different Google account. Nothing has been uploaded or changed.'**
  String get accountMismatchExplainer;

  /// Issue #1004 (tranche 2): account-mismatch non-destructive exit button.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get accountMismatchSwitchAccount;

  /// Issue #1004 (tranche 2): account-mismatch switch-account subtitle.
  ///
  /// In en, this message translates to:
  /// **'Signs out and keeps everything on this device.'**
  String get accountMismatchSwitchAccountSubtitle;

  /// Issue #1004 (tranche 2): account-mismatch destructive exit button.
  ///
  /// In en, this message translates to:
  /// **'Remove this device\'s data'**
  String get accountMismatchRemoveData;

  /// Issue #1004 (tranche 2): account-mismatch confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove this device\'s data?'**
  String get accountMismatchRemoveDialogTitle;

  /// Issue #1004 (tranche 2): account-mismatch confirmation dialog body.
  ///
  /// In en, this message translates to:
  /// **'Erases every profile and entry stored on this device and signs out. The data stays in the account it belongs to; it is not deleted there.'**
  String get accountMismatchRemoveDialogBody;

  /// Issue #1004 (tranche 2): account-mismatch confirmation cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountMismatchCancel;

  /// Issue #1004 (tranche 2): account-mismatch confirmation destructive button.
  ///
  /// In en, this message translates to:
  /// **'Remove and sign out'**
  String get accountMismatchRemoveConfirm;

  /// Issue #1004 (tranche 2): account-mismatch switch-account failure copy.
  ///
  /// In en, this message translates to:
  /// **'Could not switch accounts. Please try again.'**
  String get accountMismatchSwitchError;

  /// Issue #1004 (tranche 2): account-mismatch remove-data failure copy.
  ///
  /// In en, this message translates to:
  /// **'Could not remove this device\'s data. Please try again.'**
  String get accountMismatchRemoveError;

  /// Issue #1004 (tranche 2): upload-consent screen app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Upload to your account?'**
  String get accountUploadConsentTitle;

  /// Issue #1004 (tranche 2): upload-consent body with counts of this device's rows.
  ///
  /// In en, this message translates to:
  /// **'This device holds {profileCount, plural, =1{1 profile} other{{profileCount} profiles}} and {entryCount, plural, =1{1 entry} other{{entryCount} entries}} that are not in your account yet. Uploading copies them to the account, deletions included, and keeps this device in sync from now on.'**
  String accountUploadConsentBody(int profileCount, int entryCount);

  /// Issue #1004 (tranche 2): upload-consent body while the row counts load.
  ///
  /// In en, this message translates to:
  /// **'This device holds data that is not in your account yet.'**
  String get accountUploadConsentLoadingBody;

  /// Issue #1004 (tranche 2): upload-consent duplicate-profile note.
  ///
  /// In en, this message translates to:
  /// **'If another device also created the same person while offline, you will see two profiles after the upload; archive the one you do not want.'**
  String get accountUploadConsentDuplicateNote;

  /// Issue #1004 (tranche 2): upload-consent upload button.
  ///
  /// In en, this message translates to:
  /// **'Upload to my account'**
  String get accountUploadConsentUploadAction;

  /// Issue #1004 (tranche 2): upload-consent defer button.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get accountUploadConsentNotNow;

  /// Issue #1004 (tranche 2): empty-device restore progress label.
  ///
  /// In en, this message translates to:
  /// **'Restoring your data…'**
  String get accountRestoringScreenBody;

  /// Issue #1004 (tranche 2): restore-failure screen heading.
  ///
  /// In en, this message translates to:
  /// **'Unable to restore data'**
  String get accountRestoreErrorTitle;

  /// Issue #1004 (tranche 2): restore-failure screen default body.
  ///
  /// In en, this message translates to:
  /// **'We could not restore your account data from the cloud. Please check your internet connection and try again.'**
  String get accountRestoreErrorBody;

  /// Issue #1004 (tranche 2): restore-failure retry button.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get accountRestoreErrorRetry;

  /// Issue #1004 (tranche 2): restore-failure continue-without-sync button.
  ///
  /// In en, this message translates to:
  /// **'Continue without syncing'**
  String get accountRestoreErrorContinue;

  /// Issue #1004 (tranche 2): restore-failure sign-out button.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountRestoreErrorSignOut;

  /// Issue #1004 (tranche 2): password-recovery screen app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get accountPasswordRecoveryTitle;

  /// Issue #1004 (tranche 2): password-recovery intro paragraph.
  ///
  /// In en, this message translates to:
  /// **'You opened a password reset link. Choose a new password for your account.'**
  String get accountPasswordRecoveryIntro;

  /// Issue #1004 (tranche 2): password-recovery new-password field label.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get accountPasswordRecoveryNewLabel;

  /// Issue #1004 (tranche 2): password-recovery length helper text.
  ///
  /// In en, this message translates to:
  /// **'At least {length} characters'**
  String accountPasswordRecoveryLengthHelper(int length);

  /// Issue #1004 (tranche 2): password-recovery confirm-password field label.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get accountPasswordRecoveryConfirmLabel;

  /// Issue #1004 (tranche 2): password-recovery reveal toggle tooltip (shown).
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get accountPasswordRecoveryShow;

  /// Issue #1004 (tranche 2): password-recovery reveal toggle tooltip (hidden).
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get accountPasswordRecoveryHide;

  /// Issue #1004 (tranche 2): password-recovery too-short error.
  ///
  /// In en, this message translates to:
  /// **'Use at least {length} characters for the password.'**
  String accountPasswordRecoveryLengthError(int length);

  /// Issue #1004 (tranche 2): password-recovery mismatch error.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get accountPasswordRecoveryMismatchError;

  /// Issue #1004 (tranche 2): password-recovery save button.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get accountPasswordRecoverySave;

  /// Issue #1004 (tranche 2): password-recovery defer button.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get accountPasswordRecoveryNotNow;

  /// Issue #1004 (tranche 2): MFA remove-factor confirmation cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountMfaSettingsCancel;

  /// Issue #1004 (tranche 2): MFA step-up dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountMfaStepUpCancel;

  /// Issue #1004 (tranche 2): sync-status tile subtitle when entries were rejected.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get accountSyncStatusTapToRetry;

  /// Issue #1004 (tranche 2): sync-status snackbar action opening Settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get accountSyncStatusSettingsAction;

  /// Issue #1004 (tranche 2): sign-in screen first-run embedded intro.
  ///
  /// In en, this message translates to:
  /// **'An account keeps a copy of this device\'s data so it can be restored on another device. You can also keep everything on this device only.'**
  String get accountSignInEmbeddedIntro;

  /// Issue #1004 (tranche 2): sign-in screen passkey button.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a passkey'**
  String get accountSignInPasskeyAction;

  /// Issue #1004 (tranche 2): sign-in screen provider/passwordless divider label.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get accountSignInOr;

  /// Issue #1004 (tranche 2): sign-in screen email field label.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountSignInEmailLabel;

  /// Issue #1004 (tranche 2): sign-in screen password field label.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get accountSignInPasswordLabel;

  /// Issue #1004 (tranche 2): sign-in screen create-account primary button.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get accountSignInCreateAccountAction;

  /// Issue #1004 (tranche 2): sign-in screen sign-in primary button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignInAction;

  /// Issue #1004 (tranche 2): sign-in screen forgot-password button.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get accountSignInForgotPasswordAction;

  /// Issue #1004 (tranche 2): sign-in screen email-code field label.
  ///
  /// In en, this message translates to:
  /// **'Code from the email'**
  String get accountSignInCodeLabel;

  /// Issue #1004 (tranche 2): sign-in screen email-code field hint.
  ///
  /// In en, this message translates to:
  /// **'6-10 digits'**
  String get accountSignInCodeHint;

  /// Issue #1004 (tranche 2): sign-in screen verify-code button.
  ///
  /// In en, this message translates to:
  /// **'Sign in with code'**
  String get accountSignInVerifyCodeAction;

  /// Issue #1004 (tranche 2): sign-in screen first-run defer button.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get accountSignInNotNow;

  /// Issue #1004 (tranche 2): sign-in screen app-bar title in sign-in mode.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignInTitle;

  /// Issue #1004 (tranche 2): sign-in screen app-bar title in create mode.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get accountSignInTitleCreate;

  /// Issue #1004 (tranche 2): sign-in screen create-mode short-password error.
  ///
  /// In en, this message translates to:
  /// **'Use at least {length} characters for the password.'**
  String accountSignInUseAtLeast(int length);

  /// Issue #1004 (tranche 2): sign-in screen post-signup confirmation info.
  ///
  /// In en, this message translates to:
  /// **'Check your email to confirm the account, then open the link on this device.'**
  String get accountSignInConfirmEmailInfo;

  /// Issue #1004 (tranche 2): sign-in screen post-reset-request info.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, a reset link is on its way. Open it on this device. If you request another email, only the newest link works — an earlier one stops working (issue #32).'**
  String get accountSignInResetInfo;

  /// Issue #1004 (tranche 2): sign-in screen post-magic-link info.
  ///
  /// In en, this message translates to:
  /// **'Check your email for a sign-in link or code.'**
  String get accountSignInMagicLinkInfo;

  /// Issue #1004 (tranche 2): sign-in screen create-mode length helper text.
  ///
  /// In en, this message translates to:
  /// **'At least {length} characters'**
  String accountSignInPasswordLengthHelper(int length);

  /// Issue #1004 (tranche 2): sign-in screen password reveal toggle tooltip (shown).
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get accountSignInShowPassword;

  /// Issue #1004 (tranche 2): sign-in screen password reveal toggle tooltip (hidden).
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get accountSignInHidePassword;

  /// Issue #1004 (tranche 2): sign-in screen mode toggle (create mode active).
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get accountSignInToggleHaveAccount;

  /// Issue #1004 (tranche 2): sign-in screen mode toggle (sign-in mode active).
  ///
  /// In en, this message translates to:
  /// **'Create an account instead'**
  String get accountSignInToggleCreateInstead;

  /// Issue #1004 (tranche 2): sign-in screen magic-link button in create mode.
  ///
  /// In en, this message translates to:
  /// **'Email me a link to create my account'**
  String get accountSignInMagicLinkCreate;

  /// Issue #1004 (tranche 2): sign-in screen magic-link button in sign-in mode.
  ///
  /// In en, this message translates to:
  /// **'Email me a sign-in link'**
  String get accountSignInMagicLinkSignIn;

  /// Issue #1004 (tranche 2): delete-account confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get accountDeleteDialogTitle;

  /// Issue #1004 (tranche 2): delete-account dialog guardian-entry note.
  ///
  /// In en, this message translates to:
  /// **'Entries you logged as a guardian on someone else\'s profile are kept and re-attributed to its owner, not deleted. Apple Health / Health Connect writes this device already made stay in the device\'s own health store - account deletion does not remove them.'**
  String get accountDeleteDialogGuardianNote;

  /// Issue #1004 (tranche 2): delete-account dialog blast-radius acknowledgement checkbox.
  ///
  /// In en, this message translates to:
  /// **'I understand this removes access for other guardians and deletes any minor profiles I own.'**
  String get accountDeleteDialogAck;

  /// Issue #1004 (tranche 2): delete-account dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountDeleteDialogCancel;

  /// Issue #1004 (tranche 2): delete-account dialog transfer-ownership escape hatch.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership first'**
  String get accountDeleteDialogTransferFirst;

  /// Issue #1004 (tranche 2): delete-account dialog export-first button.
  ///
  /// In en, this message translates to:
  /// **'Export first'**
  String get accountDeleteDialogExportFirst;

  /// Issue #1004 (tranche 2): delete-account dialog destructive confirm button.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDeleteDialogConfirm;

  /// Issue #1004 (tranche 2): delete-account dialog export failure copy.
  ///
  /// In en, this message translates to:
  /// **'Could not export your data. Please try again.'**
  String get accountDeleteDialogExportError;

  /// Issue #1004 (tranche 2): delete-account blast radius with no other guardians.
  ///
  /// In en, this message translates to:
  /// **'This will also permanently delete {count, plural, =1{1 profile} other{{count} profiles}} you own ({names}).'**
  String accountDeleteDialogBlastRadiusProfiles(int count, String names);

  /// Issue #1004 (tranche 2): delete-account blast radius naming other guardians.
  ///
  /// In en, this message translates to:
  /// **'This will also permanently delete {count, plural, =1{1 profile} other{{count} profiles}} you own ({names}) and remove access for {guardianCount, plural, =1{1 other guardian} other{{guardianCount} other guardians}}.'**
  String accountDeleteDialogBlastRadiusGuardians(
    int count,
    String names,
    int guardianCount,
  );

  /// Issue #1004 (tranche 2): Settings Account section heading.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSectionTitle;

  /// Issue #1004 (tranche 2): account identity tile subtitle listing sign-in methods.
  ///
  /// In en, this message translates to:
  /// **'Sign-in methods: {methods}'**
  String accountSectionSignInMethods(String methods);

  /// Issue #1004 (tranche 2): account identity tile title with no known email.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get accountSectionSignedIn;

  /// Issue #1004 (tranche 2): account identity tile title naming the email.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String accountSectionSignedInAs(String email);

  /// Issue #1004 (tranche 2): account add-Apple tile label.
  ///
  /// In en, this message translates to:
  /// **'Add Apple'**
  String get accountSectionAddApple;

  /// Issue #1004 (tranche 2): account add-Google tile label.
  ///
  /// In en, this message translates to:
  /// **'Add Google'**
  String get accountSectionAddGoogle;

  /// Issue #1004 (tranche 2): account add-passkey tile label.
  ///
  /// In en, this message translates to:
  /// **'Add a passkey'**
  String get accountSectionAddPasskey;

  /// Issue #1004 (tranche 2): account sign-in tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync this device\'s data to an account.'**
  String get accountSectionSyncSubtitle;

  /// Issue #1004 (tranche 2): account sign-in tile title when the session expired.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get accountSectionSignInAgain;

  /// Issue #1004 (tranche 2): account sign-in tile title.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSectionSignIn;

  /// Issue #1004 (tranche 2): account sync-now tile and dialog button.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get accountSectionSyncNow;

  /// Issue #1004 (tranche 2): account sign-out tile and confirm button.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSectionSignOut;

  /// Issue #1004 (tranche 2): account sign-out tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes the data from this device.'**
  String get accountSectionSignOutSubtitle;

  /// Issue #1004 (tranche 2): account sign-out-everywhere tile and confirm button.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere'**
  String get accountSectionSignOutEverywhere;

  /// Issue #1004 (tranche 2): account sign-out-everywhere tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Signs out all devices, though others may take up to an hour to notice.'**
  String get accountSectionSignOutEverywhereSubtitle;

  /// Issue #1004 (tranche 2): account delete tile title.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountSectionDelete;

  /// Issue #1004 (tranche 2): account add-method tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to this account another way.'**
  String get accountSectionLinkSubtitle;

  /// Issue #1004 (tranche 2): account remove-method tile title.
  ///
  /// In en, this message translates to:
  /// **'Remove {provider}'**
  String accountSectionRemoveProvider(String provider);

  /// Issue #1004 (tranche 2): account remove-method tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Stop using this to sign in to this account.'**
  String get accountSectionRemoveSubtitle;

  /// Issue #1004 (tranche 2): account remove-method confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Remove {provider}?'**
  String accountSectionRemoveTitle(String provider);

  /// Issue #1004 (tranche 2): account remove-method confirmation body.
  ///
  /// In en, this message translates to:
  /// **'You will no longer be able to sign in to this account with {provider}. Your data and your other sign-in methods are unchanged.'**
  String accountSectionRemoveBody(String provider);

  /// Issue #1004 (tranche 2): account section dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accountSectionCancel;

  /// Issue #1004 (tranche 2): account remove-method confirm button.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountSectionRemove;

  /// Issue #1004 (tranche 2): sign-out-with-unsynced-rows dialog title.
  ///
  /// In en, this message translates to:
  /// **'Unsynced changes'**
  String get accountSectionUnsyncedTitle;

  /// Issue #1004 (tranche 2): sign-out-with-unsynced-rows dialog body.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change on this device has not been uploaded yet, deletions included. Sync first, or discard it and sign out.} other{{count} changes on this device have not been uploaded yet, deletions included. Sync first, or discard them and sign out.}}'**
  String accountSectionUnsyncedBody(int count);

  /// Issue #1004 (tranche 2): sign-out-with-unsynced-rows discard button.
  ///
  /// In en, this message translates to:
  /// **'Discard unsynced changes and sign out'**
  String get accountSectionDiscardAndSignOut;

  /// Issue #1004 (tranche 2): sign-out confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get accountSectionSignOutTitle;

  /// Issue #1004 (tranche 2): sign-out-everywhere confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere?'**
  String get accountSectionSignOutEverywhereTitle;

  /// Issue #1004 (tranche 2): sign-out confirmation dialog body.
  ///
  /// In en, this message translates to:
  /// **'This removes the data from this device. It stays in your account.'**
  String get accountSectionSignOutBody;

  /// Issue #1004 (tranche 2): sign-out-everywhere partial-failure snackbar suffix.
  ///
  /// In en, this message translates to:
  /// **'{failureCopy} Other devices were not signed out.'**
  String accountSectionOtherDevicesNotSignedOut(String failureCopy);

  /// Issue #1004 (tranche 2): export-range picker sheet title.
  ///
  /// In en, this message translates to:
  /// **'Export range'**
  String get settingsExportRangeTitle;

  /// Issue #1004 (tranche 2): export-range picker cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsExportRangeCancel;

  /// Issue #1004 (tranche 2): export-range picker confirm button.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsExportRangeConfirm;

  /// Issue #1004 (tranche 2): export-range custom start-date button.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get settingsExportRangeStartDate;

  /// Issue #1004 (tranche 2): export-range custom end-date button.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get settingsExportRangeEndDate;

  /// Issue #1004 (tranche 2): FHIR clinical-export tile title.
  ///
  /// In en, this message translates to:
  /// **'Export clinical summary (FHIR)'**
  String get settingsClinicalExportFhirTitle;

  /// Issue #1004 (tranche 2): CSV export tile title.
  ///
  /// In en, this message translates to:
  /// **'Export as CSV'**
  String get settingsCsvExportTitle;

  /// Issue #1004 (tranche 2): CSV export profile-chooser dialog title.
  ///
  /// In en, this message translates to:
  /// **'Export CSV data for'**
  String get settingsCsvExportForTitle;

  /// Issue #1004 (tranche 2): health-sync bind confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Sync {name} to this phone?'**
  String healthSyncBindTitle(String name);

  /// Issue #1004 (tranche 2): health-sync bind confirmation body for a write direction.
  ///
  /// In en, this message translates to:
  /// **'Only {name}\'s data will ever be written to this phone\'s Health app. This phone can sync one profile at a time — choosing a different profile later replaces this one.'**
  String healthSyncBindWriteBody(String name);

  /// Issue #1004 (tranche 2): health-sync bind confirmation body for an import-only direction.
  ///
  /// In en, this message translates to:
  /// **'Only {name}\'s data will ever be imported from this phone\'s Health app. This phone can sync one profile at a time — choosing a different profile later replaces this one.'**
  String healthSyncBindImportBody(String name);

  /// Issue #1004 (tranche 2): health-sync bind confirmation cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get healthSyncBindCancel;

  /// Issue #1004 (tranche 2): health-sync bind failure snackbar.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync {name} — try again.'**
  String healthSyncSyncFailed(String name);

  /// Issue #1004 (tranche 2): health-sync import failure line.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish the import. Please try again.'**
  String get healthSyncImportFailed;

  /// Issue #1004 (tranche 2): health-sync profile-load failure line.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load profiles for health sync.'**
  String get healthSyncLoadFailed;

  /// Issue #1004 (tranche 2): health-sync retry button.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get healthSyncRetry;

  /// Issue #1004 (tranche 2): health-sync import progress line before the first page reports.
  ///
  /// In en, this message translates to:
  /// **'Importing from {source}…'**
  String healthSyncImporting(String source);

  /// Issue #1004 (tranche 2): health-sync lossy flow-mapping disclosure.
  ///
  /// In en, this message translates to:
  /// **'Super heavy days are written to the Health app as Heavy. Spotting logged inside a period is written as Light bleeding; spotting between periods is written as intermenstrual bleeding.'**
  String get healthSyncFlowCollapseNote;

  /// Issue #1004 (tranche 2): health-sync revocation/off disclosure.
  ///
  /// In en, this message translates to:
  /// **'Turning sync off, or later revoking this phone\'s Health app permission, leaves everything already written in the Health app in place. To remove it, delete it in the Health app itself.'**
  String get healthSyncRevocationNote;

  /// Issue #1004 (tranche 2): health-sync import tile title naming the source.
  ///
  /// In en, this message translates to:
  /// **'Import from {source}'**
  String healthSyncImportFrom(String source);

  /// Issue #1004 (tranche 2): health-sync unbind tile title.
  ///
  /// In en, this message translates to:
  /// **'Stop syncing to this phone'**
  String get healthSyncUnbindAction;

  /// Issue #1004 (tranche 2): import screen app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get importScreenTitle;

  /// Issue #1004 (tranche 2): import screen file-pick body.
  ///
  /// In en, this message translates to:
  /// **'Choose a file: a JSON backup this app exported (Settings > Your data > Export my data), or the .zip Clue emailed you. Your data is added to this device — nothing already here is ever deleted.'**
  String get importScreenPickBody;

  /// Issue #1004 (tranche 2): import screen file-pick button.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get importScreenChooseFileAction;

  /// Issue #1004 (tranche 2): import screen preview confirm button.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importScreenImportAction;

  /// Issue #1004 (tranche 2): import screen preview cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get importScreenCancel;

  /// Issue #1004 (tranche 2): import screen result done button.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get importScreenDone;

  /// Issue #1004 (tranche 2): reminder settings empty state.
  ///
  /// In en, this message translates to:
  /// **'Create a profile to set up reminders.'**
  String get reminderNoProfile;

  /// Issue #1004 (tranche 2): reminder settings lock-screen privacy note.
  ///
  /// In en, this message translates to:
  /// **'Reminders never show a name, date, or any health detail on the lock screen. Logging from a notification waits until the app is unlocked.'**
  String get reminderPrivacyNote;

  /// Issue #1004 (tranche 2): reminder settings profile row title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get reminderProfileLabel;

  /// Issue #1004 (tranche 2): reminder settings cadence row title.
  ///
  /// In en, this message translates to:
  /// **'Cadence'**
  String get reminderCadenceLabel;

  /// Issue #1004 (tranche 2): reminder settings time row title.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get reminderTimeLabel;

  /// Issue #1004 (tranche 2): reminder settings quiet-hours switch title.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get reminderQuietHoursTitle;

  /// Issue #1004 (tranche 2): reminder settings quiet-hours switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'A reminder that lands inside the window waits until it ends'**
  String get reminderQuietHoursSubtitle;

  /// Issue #1004 (tranche 2): reminder settings quiet-hours start row.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get reminderQuietStart;

  /// Issue #1004 (tranche 2): reminder settings quiet-hours end row.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get reminderQuietEnd;

  /// Issue #1004 (tranche 2): Your data export tile title.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get yourDataExportTitle;

  /// Issue #1004 (tranche 2): Your data export tile subtitle when signed in.
  ///
  /// In en, this message translates to:
  /// **'Save your profiles, day entries, care notes, and visit-prep lists as a JSON file, including your account\'s server data.'**
  String get yourDataExportSubtitleSignedIn;

  /// Issue #1004 (tranche 2): Your data export tile subtitle when local-only.
  ///
  /// In en, this message translates to:
  /// **'Save your profiles, day entries, care notes, and visit-prep lists as a JSON file.'**
  String get yourDataExportSubtitleLocal;

  /// Issue #1004 (tranche 2): Your data import tile title.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get yourDataImportTitle;

  /// Issue #1004 (tranche 2): Your data import tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a JSON backup, or bring in a Clue export (.zip).'**
  String get yourDataImportSubtitle;

  /// Issue #1004 (tranche 2): purge-imported-data tile and dialog title.
  ///
  /// In en, this message translates to:
  /// **'Purge imported data'**
  String get yourDataPurgeTitle;

  /// Issue #1004 (tranche 2): purge-imported-data tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove only the entries a specific import brought in — manually logged data is never touched.'**
  String get yourDataPurgeSubtitle;

  /// Issue #1004 (tranche 2): purge success snackbar naming the import source.
  ///
  /// In en, this message translates to:
  /// **'Purged {source} data'**
  String yourDataPurgedSnack(String source);

  /// Issue #1004 (tranche 2): purge-imported-data dialog body.
  ///
  /// In en, this message translates to:
  /// **'Only entries and observations tagged with the chosen import source are removed. Manually logged data, and the profile itself, are never touched. If this purge leaves the profile with no entries at all, its saved cycle details (last period start and typical cycle length) are cleared too, since they may have come from the import.'**
  String get yourDataPurgeDialogBody;

  /// Issue #1004 (tranche 2): purge-imported-data dialog profile field label.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get yourDataPurgeProfileLabel;

  /// Issue #1004 (tranche 2): purge-imported-data dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get yourDataPurgeCancel;

  /// Issue #1004 (tranche 2): purge-imported-data dialog confirm button.
  ///
  /// In en, this message translates to:
  /// **'Purge'**
  String get yourDataPurgeConfirm;

  /// Issue #1004 (tranche 2): purge-imported-data dialog import-source field label.
  ///
  /// In en, this message translates to:
  /// **'Import source'**
  String get yourDataImportSourceLabel;

  /// Issue #1004 (tranche 4b): estimated reading time on a cycle literacy article sheet.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min read'**
  String cycleLiteracyReadingTimeMinutes(int minutes);

  /// Issue #1004 (tranche 4b): provenance block heading on a cycle literacy article sheet.
  ///
  /// In en, this message translates to:
  /// **'Source & Review'**
  String get cycleLiteracySourceHeading;

  /// Issue #1004 (tranche 4b): provenance source line on a cycle literacy article sheet.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String cycleLiteracySourceLine(String source);

  /// Issue #1004 (tranche 4b): provenance review date on a cycle literacy article sheet.
  ///
  /// In en, this message translates to:
  /// **'Last reviewed: {date}'**
  String cycleLiteracyLastReviewedLine(String date);

  /// Issue #1004 (tranche 4b): app-bar title of the standalone cycle literacy library.
  ///
  /// In en, this message translates to:
  /// **'Cycle Literacy Library'**
  String get cycleLiteracyLibraryTitle;

  /// Issue #1004 (tranche 4b): intro paragraph atop the cycle literacy library.
  ///
  /// In en, this message translates to:
  /// **'Evidence-based educational guides to understand your body, hormones, and cycle rhythms.'**
  String get cycleLiteracyLibraryIntro;

  /// Issue #1004 (tranche 4b): provenance source line on a bundled help card.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String helpCardSourceLine(String source);

  /// Issue #1004 (tranche 4b): provenance review date on a bundled help card.
  ///
  /// In en, this message translates to:
  /// **'Reviewed: {date}'**
  String helpCardReviewedLine(String date);

  /// Issue #1004 (tranche 4b): OS task-switcher title of the fail-closed startup app.
  ///
  /// In en, this message translates to:
  /// **'lunarlog'**
  String get failClosedAppTitle;

  /// Issue #1004 (tranche 4b): the fail-closed screen's single Close action.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get failClosedClose;

  /// Issue #1004 (tranche 4b): label above the raw error on the fail-closed screen.
  ///
  /// In en, this message translates to:
  /// **'Technical detail (for the device owner):'**
  String get failClosedTechnicalDetail;

  /// Issue #1004 (tranche 4b): fail-closed title for a quarantined database.
  ///
  /// In en, this message translates to:
  /// **'lunarlog could not open your data'**
  String get failClosedQuarantineTitle;

  /// Issue #1004 (tranche 4b): fail-closed body for a quarantined database.
  ///
  /// In en, this message translates to:
  /// **'The data saved on this device could not be opened. Nothing was changed and nothing was deleted — the data file was left exactly as it was, untouched.'**
  String get failClosedQuarantineBody;

  /// Issue #1004 (tranche 4b): fail-closed title for a generic startup failure.
  ///
  /// In en, this message translates to:
  /// **'lunarlog could not start'**
  String get failClosedStartTitle;

  /// Issue #1004 (tranche 4b): fail-closed body for a generic startup failure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong before any data was opened. Nothing on this device was changed.'**
  String get failClosedStartBody;

  /// Issue #1004 (tranche 4b): body of the day sheet's discard-after-failed-save confirmation.
  ///
  /// In en, this message translates to:
  /// **'The last change couldn\'t be saved. Discarding removes it from this device.'**
  String get daySheetDiscardFailedBody;

  /// Issue #1004 (tranche 4b): fertile-window explainer body on a future calendar day, prefixed by the mode's own fertile-window label.
  ///
  /// In en, this message translates to:
  /// **'{label} — the days around estimated ovulation, back-calculated from the predicted period date.'**
  String monthCalendarFertileWindowExplainer(String label);

  /// Issue #1004 (tranche 4b): tooltip on the day sheet merge notice's dismiss button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get mergeNoticeDismissTooltip;

  /// Issue #1004 (tranche 4b): fallback author name in the day sheet merge notice.
  ///
  /// In en, this message translates to:
  /// **'another guardian'**
  String get mergeNoticeAnotherGuardian;

  /// Issue #1004 (tranche 4b): possessive fallback author name in the day sheet merge notice.
  ///
  /// In en, this message translates to:
  /// **'another guardian\'s'**
  String get mergeNoticeAnotherGuardianPossessive;

  /// Issue #1004 (tranche 4b): the signed-in user as a merge-notice author.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get mergeNoticeYou;

  /// Issue #1004 (tranche 4b): possessive form of the signed-in user in a merge-notice sentence.
  ///
  /// In en, this message translates to:
  /// **'your'**
  String get mergeNoticeYour;

  /// Issue #1004 (tranche 4b): merge-notice sentence for a discarded note.
  ///
  /// In en, this message translates to:
  /// **'Two entries for this date were merged; {winner} note was kept and {loser} note was discarded.'**
  String mergeNoticeNoteBody(String winner, String loser);

  /// Issue #1004 (tranche 4b): merge-notice sentence for a discarded flow level.
  ///
  /// In en, this message translates to:
  /// **'Two entries for this date were merged; {winner} flow level was kept and {loser} was discarded.'**
  String mergeNoticeFlowBody(String winner, String loser);

  /// Issue #1004 (tranche 4b): merge-notice sentence for a replaced guardian note.
  ///
  /// In en, this message translates to:
  /// **'A guardian note for this date was replaced on sync.'**
  String get mergeNoticeGuardianNoteBody;

  /// Issue #1004 (tranche 4b): restore action for a discarded note.
  ///
  /// In en, this message translates to:
  /// **'Restore my note'**
  String get mergeNoticeRestoreNote;

  /// Issue #1004 (tranche 4b): restore action for a discarded flow level.
  ///
  /// In en, this message translates to:
  /// **'Restore my flow level'**
  String get mergeNoticeRestoreFlow;

  /// Issue #1004 (tranche 4b): the signed-in user in a caregiver-attribution badge.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get caregiverAttributionYou;

  /// Issue #1004 (tranche 4b): fallback guardian name in a caregiver-attribution badge.
  ///
  /// In en, this message translates to:
  /// **'Guardian'**
  String get caregiverAttributionGuardianFallback;

  /// Issue #1004 (tranche 4b): attribution verb naming who logged an entry.
  ///
  /// In en, this message translates to:
  /// **'Logged by {name}'**
  String caregiverAttributionLoggedBy(String name);

  /// Issue #1004 (tranche 4b): attribution verb naming who last modified an entry.
  ///
  /// In en, this message translates to:
  /// **'Modified by {name}'**
  String caregiverAttributionModifiedBy(String name);

  /// Issue #1004 (tranche 4b): import-source badge for a Clue import.
  ///
  /// In en, this message translates to:
  /// **'Imported from Clue'**
  String get caregiverAttributionImportedClue;

  /// Issue #1004 (tranche 4b): import-source badge for an Apple Health / HealthKit import.
  ///
  /// In en, this message translates to:
  /// **'Imported from Health'**
  String get caregiverAttributionImportedHealth;

  /// Issue #1004 (tranche 4b): import-source badge for a Health Connect import.
  ///
  /// In en, this message translates to:
  /// **'Imported from Health Connect'**
  String get caregiverAttributionImportedHealthConnect;

  /// Issue #1004 (tranche 4b): import-source badge for a file import.
  ///
  /// In en, this message translates to:
  /// **'Imported from file'**
  String get caregiverAttributionImportedFile;

  /// Issue #1004 (tranche 4b): import-source badge for a wearable import.
  ///
  /// In en, this message translates to:
  /// **'Imported from wearable'**
  String get caregiverAttributionImportedWearable;

  /// Issue #1004 (tranche 4b): generic import-source badge for an unrecognised source.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get caregiverAttributionImportedGeneric;

  /// Issue #1004 (tranche 4a): shared retry action label (inline errors and the sync-failure banner).
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Issue #1004 (tranche 4a): Today destination label in the app shell's navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get appShellTabToday;

  /// Issue #1004 (tranche 4a): Calendar destination label in the app shell's navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get appShellTabCalendar;

  /// Issue #1004 (tranche 4a): Insights destination label in the app shell's navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get appShellTabInsights;

  /// Issue #1004 (tranche 4a): More destination label in the app shell's navigation bar.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get appShellTabMore;

  /// Issue #1004 (tranche 4a): sync-failure banner action that switches to the Settings tab.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get appShellSyncBannerGoToSettings;

  /// Issue #1004 (tranche 4a): tooltip on the Today card's quick-log button, naming the flow level it writes.
  ///
  /// In en, this message translates to:
  /// **'Logs a {level}-flow period start for today'**
  String todayCardLogsFlowTooltip(String level);

  /// Issue #1004 (tranche 4a): heading of the cycle-history section.
  ///
  /// In en, this message translates to:
  /// **'Cycle history'**
  String get cycleHistoryTitle;

  /// Issue #1004 (tranche 4a): note under the cycle-history list explaining that omissions sync.
  ///
  /// In en, this message translates to:
  /// **'Omissions sync across your devices.'**
  String get cycleHistorySyncNote;

  /// Issue #1004 (tranche 4a): label of the average-cycle-length statistic.
  ///
  /// In en, this message translates to:
  /// **'Avg cycle'**
  String get cycleHistoryAvgCycle;

  /// Issue #1004 (tranche 4a): label of the average-period-length statistic.
  ///
  /// In en, this message translates to:
  /// **'Avg period'**
  String get cycleHistoryAvgPeriod;

  /// Issue #1004 (tranche 4a): label of the cycle-length variation statistic.
  ///
  /// In en, this message translates to:
  /// **'Variation'**
  String get cycleHistoryVariation;

  /// Issue #1004 (tranche 4a): subtitle marking a cycle excluded automatically as an outlier.
  ///
  /// In en, this message translates to:
  /// **'Outlier — never averaged'**
  String get cycleHistoryOutlier;

  /// Issue #1004 (tranche 4a): title of the open cycle row, naming its start date.
  ///
  /// In en, this message translates to:
  /// **'Current cycle — started {date}'**
  String cycleHistoryCurrentCycleStarted(String date);

  /// Issue #1004 (tranche 4a): subtitle of an open cycle the operator skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped — excluded from averages'**
  String get cycleHistorySkippedExcluded;

  /// Issue #1004 (tranche 4a): action restoring a previously omitted cycle to the averages.
  ///
  /// In en, this message translates to:
  /// **'Include'**
  String get cycleHistoryInclude;

  /// Issue #1004 (tranche 4a): action excluding a cycle from the averages.
  ///
  /// In en, this message translates to:
  /// **'Omit'**
  String get cycleHistoryOmit;

  /// Issue #1004 (tranche 4a): action undoing a skipped open cycle.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get cycleHistoryUndo;

  /// Issue #1004 (tranche 4a): snoozed late-resolver line naming the date it resumes.
  ///
  /// In en, this message translates to:
  /// **'We will check back on {date}.'**
  String lateResolverSnoozedUntil(String date);

  /// Issue #1004 (tranche 4a): action ending a late-resolution snooze early.
  ///
  /// In en, this message translates to:
  /// **'Show options'**
  String get lateResolverShowOptions;

  /// Issue #1004 (tranche 4a): late-resolver title naming the day count, pluralised.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day late} other{{count} days late}}'**
  String lateResolverDaysLate(int count);

  /// Issue #1004 (tranche 4a): late-resolver fallback line, where {days} is an already-localized day count.
  ///
  /// In en, this message translates to:
  /// **'No period logged for {days}'**
  String lateResolverNoPeriodLoggedFor(String days);

  /// Issue #1004 (tranche 4a): late-resolver prompt after a snooze expired.
  ///
  /// In en, this message translates to:
  /// **'Still nothing logged — what would you like to do?'**
  String get lateResolverPromptStillNothing;

  /// Issue #1004 (tranche 4a): late-resolver prompt.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do?'**
  String get lateResolverPrompt;

  /// Issue #1004 (tranche 4a): late-resolver action opening the day sheet.
  ///
  /// In en, this message translates to:
  /// **'Log it'**
  String get lateResolverLogIt;

  /// Issue #1004 (tranche 4a): late-resolver action omitting the open cycle.
  ///
  /// In en, this message translates to:
  /// **'Skip this cycle'**
  String get lateResolverSkipCycle;

  /// Issue #1004 (tranche 4a): late-resolver action snoozing for three days.
  ///
  /// In en, this message translates to:
  /// **'Remind me in 3 days'**
  String get lateResolverRemindMe;

  /// Issue #1004 (tranche 4a): late-resolver link to the late-period help card.
  ///
  /// In en, this message translates to:
  /// **'Why is it late?'**
  String get lateResolverWhyLate;

  /// Issue #1004 (tranche 4a): label of the help-card link explaining the three-cycle threshold.
  ///
  /// In en, this message translates to:
  /// **'Why three completed cycles?'**
  String get overviewWhyThreeCompletedCycles;

  /// Issue #1004 (tranche 4a): error shown when the analysis tab's prediction stream fails.
  ///
  /// In en, this message translates to:
  /// **'Could not load your cycle analysis.'**
  String get analysisLoadError;

  /// Issue #1004 (tranche 4a): heading of the analysis tab.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get analysisTitle;

  /// Issue #1004 (tranche 4a): title of the BBT chart card.
  ///
  /// In en, this message translates to:
  /// **'BBT by cycle day'**
  String get analysisBbtChartTitle;

  /// Issue #1004 (tranche 4a): title of the headline cycle-statistics card.
  ///
  /// In en, this message translates to:
  /// **'Cycle statistics'**
  String get analysisStatsTitle;

  /// Issue #1004 (tranche 4a): label of the mean cycle-length statistic.
  ///
  /// In en, this message translates to:
  /// **'Average cycle length'**
  String get analysisMeanCycleLength;

  /// Issue #1004 (tranche 4a): label of the mean period-length statistic.
  ///
  /// In en, this message translates to:
  /// **'Average period length'**
  String get analysisMeanPeriodLength;

  /// Issue #1004 (tranche 4a): label of the cycle-length variability statistic.
  ///
  /// In en, this message translates to:
  /// **'Variability'**
  String get analysisVariability;

  /// Issue #1004 (tranche 4a): variability value, the spread from the mean in days.
  ///
  /// In en, this message translates to:
  /// **'±{days} days'**
  String analysisSpreadDays(int days);

  /// Issue #1004 (tranche 4a): empty-state title of the BBT chart.
  ///
  /// In en, this message translates to:
  /// **'No BBT logged yet'**
  String get bbtChartEmptyTitle;

  /// Issue #1004 (tranche 4a): empty-state body of the BBT chart.
  ///
  /// In en, this message translates to:
  /// **'Log a basal body temperature reading in the day sheet to see your curve here, plotted against cycle day.'**
  String get bbtChartEmptyBody;

  /// Issue #1004 (tranche 4a): BBT chart caption, naming the cycle count and the temperature range.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cycle shown} other{{count} cycles shown}} · {range}'**
  String bbtChartCaption(int count, String range);

  /// Issue #1004 (tranche 4a): label introducing a subphase's what-to-track guidance.
  ///
  /// In en, this message translates to:
  /// **'Helpful to track:'**
  String get phaseInsightsHelpfulToTrack;

  /// Issue #1004 (tranche 4a): button opening the subphase's context article, naming its title.
  ///
  /// In en, this message translates to:
  /// **'Read: {title}'**
  String phaseInsightsReadArticle(String title);

  /// Issue #1004 (tranche 4a): provenance footnote naming the subphase content's source and review date.
  ///
  /// In en, this message translates to:
  /// **'Source: {source} · Rev: {date}'**
  String phaseInsightsSource(String source, String date);

  /// Issue #1004 (tranche 4a): heading of the symptom-trends section.
  ///
  /// In en, this message translates to:
  /// **'Symptom Trends & Patterns'**
  String get symptomTrendsTitle;

  /// Issue #1004 (tranche 4a): title of the recurring-symptoms card.
  ///
  /// In en, this message translates to:
  /// **'Recurring Symptoms'**
  String get symptomTrendsRecurring;

  /// Issue #1004 (tranche 4a): empty state of the recurring-symptoms card.
  ///
  /// In en, this message translates to:
  /// **'Log symptoms across at least 3 completed cycles to uncover recurring patterns and trends.'**
  String get symptomTrendsEmpty;

  /// Issue #1004 (tranche 4a): disclaimer under the recurring-symptoms list.
  ///
  /// In en, this message translates to:
  /// **'Patterns reflect descriptive logs only and are not clinical diagnostics.'**
  String get symptomTrendsDisclaimer;

  /// Issue #1004 (tranche 4a): title of the flow-distribution summary.
  ///
  /// In en, this message translates to:
  /// **'Typical Bleed Rhythm'**
  String get symptomTrendsFlowTitle;

  /// Issue #1004 (tranche 4a): flow summary subtitle naming the typical peak cycle day and flow level.
  ///
  /// In en, this message translates to:
  /// **'Peak flow typically falls on Cycle Day {day} ({flow}).'**
  String symptomTrendsFlowSubtitle(int day, String flow);

  /// Issue #1004 (tranche 4a): title of the cycle-literacy library call to action.
  ///
  /// In en, this message translates to:
  /// **'Cycle Literacy Library'**
  String get symptomTrendsLibraryTitle;

  /// Issue #1004 (tranche 4a): subtitle of the cycle-literacy library call to action.
  ///
  /// In en, this message translates to:
  /// **'Evidence-based guides on hormones, cycle phases, and body signals.'**
  String get symptomTrendsLibrarySubtitle;

  /// Issue #1004 (tranche 4a): title of the cramp-prediction card.
  ///
  /// In en, this message translates to:
  /// **'Anticipated Cramp Window'**
  String get crampPredictionTitle;

  /// Issue #1004 (tranche 4a): cramp-prediction line naming the predicted dates.
  ///
  /// In en, this message translates to:
  /// **'Estimated dates: {dates}'**
  String crampPredictionDates(String dates);

  /// Issue #1004 (tranche 4a): cramp-prediction line naming how many cycles the pattern was observed in.
  ///
  /// In en, this message translates to:
  /// **'Observed in {observed} of {total} recorded cycles.'**
  String crampPredictionObserved(int observed, int total);

  /// Issue #1004 (tranche 4a): per-pattern line naming its occurrence and cycle counts.
  ///
  /// In en, this message translates to:
  /// **'Logged {occurrences} times across {cycles} cycles'**
  String symptomTrendsLogged(int occurrences, int cycles);
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
