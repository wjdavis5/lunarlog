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
  /// **'LunarLog is a family cycle tracker built for sync and sharing.\n\n• Sync & Family Sharing: An account (Supabase) syncs a profile across your devices and lets it be shared with other guardians, each with their own role. No data is uploaded without your explicit consent.\n• Protected at Rest: Cycle data is protected at rest by your device\'s own operating system encryption and shown only behind biometric authentication.\n• Works Offline: Logging, viewing, and predictions keep working without a network; sharing a profile with another guardian does require signing in.\n• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health and personal details on-device.\n• Family Custodianship: Minor profiles are managed directly by adult guardians with identical privacy protections.\n• Minimum-Age Policy: Licensed for ages 13 and older; household profiles managed by adult guardians (18+).\n• Caregiver Alerts: Optional push notifications to another guardian never carry what was logged - only a generic reminder, via Firebase Cloud Messaging.\n\nCanonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md'**
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
  /// **'Caregiver alerts'**
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

  /// Date-format option: follow the locale's own month/day order; the example shows the English (day-first) rendering.
  ///
  /// In en, this message translates to:
  /// **'System default (5 Sep)'**
  String get settingsDateFormatSystemOption;

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

  /// Checkbox label acknowledging the 13+ minimum-age statement on first-run profile creation.
  ///
  /// In en, this message translates to:
  /// **'I am 13 or older, or a guardian managing a family profile'**
  String get firstRunAgeAcknowledgementLabel;

  /// One-line hint under the minimum-age acknowledgement checkbox in the first-run form.
  ///
  /// In en, this message translates to:
  /// **'LunarLog requires users to be at least 13 years old, or managed by a parent or legal guardian.'**
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

  /// SharingFailure.other copy — distinct from the generic commonSomethingWentWrong because this failure is always an accept-invite attempt.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept invitation. Please try again.'**
  String get sharingFailureOther;

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
  /// **'Remove caregiver'**
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
  /// **'Lunarlog'**
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
  /// **'The preview is exactly what the notification will show — nothing more. Lunarlog never adds a profile name, date, or health detail to notification text.'**
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
