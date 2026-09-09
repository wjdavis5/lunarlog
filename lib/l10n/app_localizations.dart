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
