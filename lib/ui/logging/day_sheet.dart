/// Day entry sheet (U5, R8/R9): flow selector, one-tap curated tag chips,
/// free-text note, autosave-on-change, and confirm-then-tombstone Delete.
///
/// Guards: future dates are never loggable (the calendar disables them; the
/// sheet re-checks), archived profiles get a read-only view with no
/// logging affordances, and a repository save/delete failure keeps the
/// sheet open with all entered values intact plus an inline retry error.
///
/// Issue #198 (B-12/B-13/B-14): the sheet autosaves on change (debounced
/// through [kDaySheetAutosaveDelay]) instead of a save-or-lose button — the
/// commit-immediately model. The sheet never closes on save; closing happens
/// by dismissal (drag, barrier tap), and a change still inside the debounce
/// window is flushed on dismissal so nothing is silently dropped. A write
/// failure surfaces the inline retry error and keeps the pending state, and
/// a [PopScope] guard blocks dismissal only in that failure-pending state
/// (behind an explicit discard confirmation). The delete affordance and the
/// autosave status live in a pinned bottom area inside the sheet that never
/// scrolls away, and the sheet's shell pads itself by the keyboard inset so
/// the note field and that pinned area stay above the keyboard.
///
/// Issue #247 (flow model, ported from #335 into the autosave compose
/// path): the chip row offers [kSelectableFlowLevels] — the deprecated
/// [FlowLevel.spotting] alias is gone from it, and `notBleeding` and
/// `superHeavy` are offered. Spotting is an `observations` category row
/// written/cleared by [_syncSpottingObservation] after every successful
/// entry write (its toggle seeds via [_loadExistingSpotting] at init), and
/// [_composeEntry] persists [_resolveEffectiveFlow]'s value so
/// spotting-only days still assert an explicit `notBleeding` day while an
/// un-checked spotting-only day reverts to `none`. Provenance
/// (`source`/`sourceId`/`importId`, issue #159's review finding) carries
/// forward on every write so an imported entry is never reset to manual.
///
/// Issue #131: the profile's care mode selects the category headings and
/// the order they are surfaced in (`careModeCopyFor`) — a prospective
/// logging-default only. Every category remains available in every mode
/// (teen reorders, it never removes: "not a euphemism for a reduced app"),
/// and saved entries always render verbatim regardless of mode.
///
/// Issue #259: the profile's synced tracking preferences overlay the care
/// mode's default — the sheet renders [resolveTrackingCategories]'s
/// curated-first order and skips disabled categories entirely (their
/// already-logged tags keep round-tripping through autosave untouched;
/// hiding never deletes), with the minor-visibility default applied for
/// never-mentioned categories. The concrete picker UI that edits the
/// document is #234; this is the read path.
///
/// Route naming (U2 Approach 2b): the sheet itself is named
/// `DaySheetScreen` at its push site (`month_calendar.dart`). Its internal
/// "Delete this entry?" / "Discard unsaved changes?" `showDialog`s are
/// deliberately left unnamed — trivial confirm/cancel choices, not distinct
/// destinations.
///
/// Issue #887 (cycle-start consent): a bleed-level chip tap that would
/// start a new cycle earlier than the profile's history expects asks
/// first (`_selectFlow` through the pure surprise condition in
/// `lib/domain/logging/cycle_start_confirm.dart` — "Start new cycle" /
/// "Log spotting instead" / cancel), and any session that changes the
/// cycle-start set leaves the sheet through a snackbar with an Undo
/// restoring the pre-session entry (`_cycleStartChangeSnackBar`, #316's
/// pattern). Disclosure and consent only — the engine's cycle-start
/// semantics are untouched, the same design principle #130 applied to
/// same-date merges.
library;

import 'dart:async'
    show StreamSubscription, Timer, scheduleMicrotask, unawaited;
import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/care/guardian_notes_section.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/logging/widgets/merge_notice_section.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/calendar_preferences.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/conceive.dart' show conceiveCategoryOrder;
import 'package:lunarlog/domain/import/clue/clue_import_run.dart'
    show describeUnmappedRaw;
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/cycle_start_confirm.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/logging/day_sheet_reconciliation.dart';
import 'package:lunarlog/domain/logging/day_sheet_save_state.dart';
import 'package:lunarlog/domain/logging/tag_recents.dart';
import 'package:lunarlog/domain/logging/tag_recents_store.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/measurement_validation.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/perimenopause.dart'
    show isPerimenopauseMode, perimenopauseCategoryOrder;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart'
    show kOfflineSaveConfirmationCopy, shouldConfirmOfflineSave;
import 'package:provider/provider.dart';

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/components/category_picker.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/components/responsive_body.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/components/intensity_selector.dart';
import 'package:lunarlog/ui/components/sheet_drag_header.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';
import 'package:lunarlog/ui/logging/widgets/custom_tag_manager_sheet.dart';
import 'package:lunarlog/ui/theme/haptics.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

/// Debounce between the last change (chip, flow, or note keystroke) and the
/// autosave write (#198 B-13). Short enough to feel commit-immediate, long
/// enough that a burst of chip taps or fast typing is one write.
const Duration kDaySheetAutosaveDelay = Duration(milliseconds: 600);

/// How long the transient "Saved" micro-confirmation stays visible after a
/// successful autosave (#198 B-13).
const Duration kDaySheetSavedIndicatorDuration = Duration(seconds: 2);

/// Human-readable sheet date (#198 B-14, coordinated with #160):
/// "Today · Sun 30 Aug" for [date] == [today], "Yesterday" for the day
/// before, otherwise a locale-aware absolute date ("Sun 1 Mar 2026") —
/// never the raw ISO string. Backed by `intl` so #160's shared
/// date formatter can absorb this helper wholesale once it lands (same
/// inputs, same shape); until then it is the sheet's own thin local helper.
/// [preference] (Issue #226) reorders the month/day pair per the
/// Calendar → "Date format" setting; it defaults to the system order, which
/// since issue #884 follows [locale]'s own day/month ordering (month-first
/// for `en_US`, day-first for `en_GB`).
String daySheetDateLabel(
  LocalDate date,
  LocalDate today, {
  String locale = dates.kFallbackLocale,
  DateFormatPreference preference = DateFormatPreference.system,
}) =>
    dates.relativeDayLabelForLocalDate(
      date,
      today,
      locale: locale,
      preference: preference,
    );

/// Issue #457: formats a BBT/weight value for display in a text field or an
/// inline error — up to two decimal places, with trailing zeros trimmed
/// (`36.7` and `61` render as themselves, never `36.70` or `61.00`), so a
/// converted value (e.g. Celsius-to-Fahrenheit) never shows more spurious
/// precision than a person would type by hand. Public so the day sheet's
/// seeding, its own validation-error copy, and this file's tests all share
/// one formatting rule.
String formatMeasurementValue(double value) {
  final rounded = (value * 100).roundToDouble() / 100;
  var text = rounded.toStringAsFixed(2);
  if (text.endsWith('.00')) {
    text = rounded.toStringAsFixed(0);
  } else if (text.endsWith('0')) {
    text = rounded.toStringAsFixed(1);
  }
  return text;
}

/// The flow levels the chip row offers (issue #247): the deprecated
/// [FlowLevel.spotting] alias is excluded — spotting is logged via the
/// separate "Spotting" toggle below the flow row instead, which writes an
/// `observations` row, never a flow level (see [_syncSpottingObservation]).
const List<FlowLevel> kSelectableFlowLevels = [
  FlowLevel.none,
  FlowLevel.notBleeding,
  FlowLevel.light,
  FlowLevel.medium,
  FlowLevel.heavy,
  FlowLevel.superHeavy,
];

/// Issue #256: the graded intensity values a pain code's selector offers —
/// the full `observations.intensity` domain (1-5, `kMinObservationIntensity`
/// .. `kMaxObservationIntensity`, the same bounds the server-side CHECK and
/// the local storage layer enforce). 4 and 5 are the grades the
/// caregiver-alert trigger classifies as high severity.
final List<int> kGradedIntensities = [
  for (int i = kMinObservationIntensity; i <= kMaxObservationIntensity; i++) i,
];

/// [#138] Wraps a chip so a screen reader hears its group, its label, and
/// its selected state as one node, with an accessibility tap action wired
/// to the same toggle the visible chip performs. The chip's own semantics
/// are excluded and rebuilt by the wrapper: a raw chip announces only its
/// own text plus its selected flag ("Medium, selected"), never which group
/// of controls it belongs to, and [Semantics.onTap] keeps activation
/// working after the exclusion. The `'<group>, <chip>'` phrase shape (and
/// its comma join) matches `dayCellSemanticLabel`'s, so every semantic
/// label this pass introduces reads the same way.
Widget groupedChipSemantics({
  required String group,
  required String label,
  required bool selected,
  required Widget child,
  VoidCallback? onTap,
}) {
  return Semantics(
    label: '$group, $label',
    button: onTap != null,
    enabled: onTap != null,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  );
}

/// Issue #160: the localized flow-chip label. Same strings [flowLabel]
/// derives for `en`; this variant reads them from [AppLocalizations] so
/// the sheet's chips follow the active locale (`flowLabel` stays as the
/// `en` fallback for callers outside the four localized screens, e.g. the
/// activity feed). #138: `notBleeding`/`superHeavy` (issue #247) now have
/// ARB keys of their own instead of inline `en` literals.
String localizedFlowLabel(FlowLevel flow, AppLocalizations l10n) =>
    switch (flow) {
      FlowLevel.none => l10n.flowLevelNone,
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.spotting => l10n.flowLevelSpotting,
      FlowLevel.light => l10n.flowLevelLight,
      FlowLevel.medium => l10n.flowLevelMedium,
      FlowLevel.heavy => l10n.flowLevelHeavy,
      FlowLevel.notBleeding => l10n.flowLevelNotBleeding,
      FlowLevel.superHeavy => l10n.flowLevelSuperHeavy,
    };

class DaySheet extends StatefulWidget {
  const DaySheet({
    super.key,
    required this.repository,
    required this.profileId,
    required this.date,
    required this.today,
    this.existing,
    this.mode = ProfileMode.standard,
    this.lifecycleMode,
    this.trackingPreferences,
    this.isMinor = false,
    this.readOnly = false,
    this.timezoneProvider,
    this.currentUserId,
    this.guardians = const [],
    this.bbtUnit = BbtUnit.celsius,
    this.weightUnit = WeightUnit.kg,
  });

  final DayEntriesRepository repository;
  final String profileId;
  final LocalDate date;

  /// Device-local civil date; [date] must not be after this to be loggable.
  final LocalDate today;

  /// The current live entry for (profileId, date), or null for a new log.
  final DayEntry? existing;

  /// The profile's care mode (Issue #131): category headings and surfacing
  /// order. Presentation only — never a permission.
  final ProfileMode mode;

  /// The profile's life-stage mode (Issue #188/#204): when
  /// [LifecycleMode.conceive], the sheet surfaces the fertility-signal
  /// categories (Tests, then Discharge) ahead of everything else — see
  /// [_resolveCategoriesInOrder] and `domain/conceive.dart`. Null means the
  /// caller has no life-stage context (an older/test call site): the sheet
  /// falls back to the ordinary order, never guessing. Orthogonal to
  /// [mode] — this never changes vocabulary or permissions.
  final LifecycleMode? lifecycleMode;

  /// The profile's curated tracking categories (Issue #259): the synced
  /// preference document the day sheet reads to decide which categories
  /// render and in what order (AC2). Null — the default — means never
  /// customized: every category resolves to its default. Presentation
  /// only; a disabled category is simply not shown, never deleted (AC3),
  /// and this field is never consulted by any authorization path.
  final TrackingPreferences? trackingPreferences;

  /// Whether the profile subject is a minor (Issue #259): gates the
  /// minor-visibility *defaults* — categories in
  /// [kMinorDefaultHiddenTrackingCategories] stay unsurfaced for a minor
  /// until a primary guardian explicitly enables them (AC4). Defaults to
  /// false; only resolution of absent entries reads it, never any stored
  /// entry (an explicit enable/disable always wins over the default).
  final bool isMinor;
  final bool readOnly;

  /// Provider for the resolved IANA time zone identifier (paired with #38).
  /// Defaults to [resolveCurrentTimeZone] if not specified.
  final String Function()? timezoneProvider;

  final String? currentUserId;
  final List<ProfileGuardian> guardians;

  /// Per-profile BBT display unit (Issue #457, storage per #255): the day
  /// sheet's BBT field reads and writes in this unit — a stored row in a
  /// different unit (an imported Fahrenheit reading on a Celsius-display
  /// profile) is converted for editing, and a save re-denominates the row
  /// to this unit, mirroring `measurement_unit.dart`'s read-time-only
  /// conversion contract.
  final BbtUnit bbtUnit;

  /// Per-profile weight display unit (Issue #457); same contract as
  /// [bbtUnit].
  final WeightUnit weightUnit;

  @override
  State<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<DaySheet> {
  late FlowLevel _flow;
  late final Set<String> _tags;
  late final TextEditingController _noteController;
  bool _busy = false;
  bool _deleteFailed = false;

  /// Autosave state (#198, issue #601): every change of "is a save pending,
  /// in flight, just succeeded, or failed" lives in one
  /// [DaySheetSaveState] — see `lib/domain/logging/day_sheet_save_state.dart`
  /// for the sealed hierarchy and the pure transition functions this class
  /// drives. This field is the only thing they operate on; everything else
  /// here (the debounce [Timer], the "Saved" banner's own timer, the actual
  /// repository write) is a side effect the widget layers on top.
  DaySheetSaveState _saveState = const DaySheetIdle();
  Timer? _saveDebounce;

  /// Issue #923: what the last failed write was — null (and cleared on every
  /// success) means the generic "Couldn't save" copy. A date-bounds rejection
  /// class gets rule-specific copy and is never reported to Sentry; a [bug]
  /// keeps the report-and-generic-copy behaviour. Set in [_writePending]
  /// before it returns `false`, so the banner [_pinnedBottomArea] renders
  /// always agrees with the failure that produced the [DaySheetFailed] state.
  DaySheetWriteErrorClass? _saveErrorClass;

  /// Issue #130: the date's undismissed same-date merge disclosures — the
  /// quiet notice list, loaded once when the sheet opens (the events for a
  /// date are fixed once recorded; dismissal updates this list locally).
  List<DayEntryMergeEvent> _mergeEvents = const [];
  Timer? _savedIndicatorTimer;
  String? _persistedEntryId;

  /// The Future of whichever repository write is running right now, if
  /// any (issue #601's LLA-003 audit finding) — set only for the exact
  /// duration of the `saveDayEntryWithObservations` call [_performAutosave]
  /// is currently awaiting, tracked outside [_saveState] since it is an
  /// awaitable side effect, not state. [_delete] awaits this (when
  /// non-null) before ever calling `widget.repository.delete` itself, so
  /// an already in-flight write can never complete *after* the delete and
  /// silently resurrect the row via its own upsert (`deletedAt: null`).
  /// Transitioning [_saveState] to [DaySheetDeleting] *before* that await
  /// is what actually closes the race, not this field alone — see
  /// [DaySheetDeleting]'s own doc.
  Future<void>? _inFlightWrite;

  /// True once the user explicitly confirmed discarding a failed save —
  /// the only state in which dismissal drops pending changes on purpose.
  bool _discardUnsaved = false;
  bool _discardDialogOpen = false;

  /// Captured (while still mounted) after a successful save in an
  /// offline-looking sync state, so the "Saved on this device · will sync"
  /// SnackBar can be shown when the sheet is dismissed — the sheet no
  /// longer closes on save, and a SnackBar shown under an open modal sheet
  /// would be invisible behind its barrier (issue #182 AC8 shape).
  ScaffoldMessengerState? _offlineAckMessenger;

  /// Issue #247: spotting is logged as its own `observations` row
  /// (`category: 'spotting'`), not a [FlowLevel] value — this toggle
  /// tracks it independently of [_flow]. Initialised from any already
  /// -persisted (or synthesised-from-legacy-`spotting`-flow) spotting
  /// observation by [_loadExistingSpotting]; starts `false` for a new
  /// entry.
  bool _spotting = false;

  /// Issue #256: the graded intensity (1-5) chosen per pain code, keyed by
  /// taxonomy code and synced to the day's `category: 'pain'` observations
  /// rows by [_syncPainIntensityObservations] on every autosave — the
  /// observations side of the intensity model (`observations.intensity`,
  /// #240), which is what the server's high-severity caregiver alert
  /// (`intensity >= 4`) reads. Absent key = no intensity for that code;
  /// an explicit `null` value = the user cleared a previously recorded
  /// intensity this session (the row is tombstoned — ungraded means "no
  /// severity recorded", never "low"). Seeded on load by
  /// [_loadExistingPainIntensity] from any already-persisted graded pain
  /// rows (including imported ones), so an existing grade is never
  /// silently dropped: editing a pain code's intensity is always a
  /// deliberate act on the selector below the Pain chips.
  final Map<String, int?> _painIntensity = {};

  /// Issue #642, LLA-011: whether [_loadExistingSpotting] and
  /// [_loadExistingPainIntensity] have both settled (succeeded or failed)
  /// — only [_readOnlyBody] surfaces this. The editable UI's own spotting
  /// toggle/intensity selectors need no loading affordance: they simply
  /// start unset and update once the load resolves, which reads fine as
  /// "nothing chosen yet"; the read-only view has no such natural "empty"
  /// state to fall back on, so it shows a small loading row instead until
  /// both loaders settle. Starts `true` only when there is an [existing]
  /// entry to load child observations for — see [initState].
  bool _childObservationsLoading = false;

  /// Set by either loader's `catch` (issue #642, LLA-011) — the read-only
  /// body then shows [AppLocalizations.daySheetChildObservationsError]
  /// instead of silently omitting spotting/pain-intensity, the same "say
  /// something went wrong" discipline every other repository-backed read
  /// in this file uses.
  bool _childObservationsLoadFailed = false;

  /// How many of [_loadExistingSpotting]/[_loadExistingPainIntensity] are
  /// still outstanding; [_childObservationsLoading] clears once this
  /// reaches zero. Both loaders always run together (see [initState]), so
  /// this only ever starts at 2 or 0.
  int _childObservationsLoadsPending = 0;

  /// Marks one of the two child-observation loaders settled (issue #642,
  /// LLA-011): flips [_childObservationsLoadFailed] on [failed], and
  /// clears [_childObservationsLoading] once both have reported in. Must
  /// be called from inside a `setState` (or while unmounted, where no
  /// rebuild is needed) — it does not call `setState` itself, matching
  /// every other private mutator in this file.
  void _childObservationLoadSettled({bool failed = false}) {
    if (failed) _childObservationsLoadFailed = true;
    _childObservationsLoadsPending--;
    if (_childObservationsLoadsPending <= 0) {
      _childObservationsLoading = false;
    }
  }

  /// Issue #457: BBT/weight text controllers. Seeded (like the note field)
  /// from any already-persisted manual measurement, converted into
  /// [DaySheet.bbtUnit]/[DaySheet.weightUnit] so the field always shows a
  /// value in the profile's current display unit regardless of which unit
  /// it was originally entered/imported in.
  late final TextEditingController _bbtController;
  late final TextEditingController _weightController;

  /// The last value each field parsed as valid (or `null` for "cleared") —
  /// what an autosave actually writes, as opposed to whatever text is
  /// currently in the controller. Kept separate from the controller's raw
  /// text so an in-progress invalid keystroke (an extra digit, a stray
  /// letter, a still-out-of-range number) never overwrites — or deletes —
  /// a previously valid, already-persisted value; see [_onBbtChanged]'s doc.
  double? _bbtValue;
  double? _weightValue;

  /// Issue #457: BBT's per-point exclusion flag (A1-44), reused verbatim
  /// for weight — "exclude this reading from charts" without deleting the
  /// logged value itself.
  bool _bbtExcluded = false;
  bool _weightExcluded = false;

  /// Non-null while the field's current text fails to parse or falls
  /// outside [isValidBbt]/[isValidWeight]'s sanity range — rendered as an
  /// [InlineError] under the field. Null the moment the text is empty
  /// (a clear) or parses to a valid value.
  String? _bbtError;
  String? _weightError;

  /// True only for the duration of [_loadExistingMeasurements]' programmatic
  /// `TextEditingController.text` assignment — suppresses
  /// [_onBbtChanged]/[_onWeightChanged], which would otherwise treat that
  /// seed as a user edit and mark the sheet dirty on nothing more than
  /// opening it (the note field avoids the same problem differently, by
  /// setting its initial text before its listener is attached at all — not
  /// available here since this seed arrives asynchronously, after
  /// `initState` already attached both listeners).
  bool _seedingMeasurements = false;

  /// #165: the editable sheet's text-field focus chain — "next" on the BBT
  /// field advances to weight, "next" on weight advances to the note field
  /// (the sheet's field order, explicit rather than tree-derived).
  final _bbtFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _noteFocus = FocusNode();

  /// Issue #220: the first-class PMS marker, tracked straight off the
  /// loaded entry (like flow and tags — it rides `DayEntry.pms` itself,
  /// not a child row).
  bool _pms = false;

  /// Review fix (blocking): `true` once [_loadExistingSpotting] finds the
  /// day already had spotting on load — kept `true` even after the user
  /// unchecks the toggle, so [_resolveEffectiveFlow] can tell "spotting
  /// was just removed" apart from "spotting was never on this session".
  bool _hadSpottingOnLoad = false;

  /// Review fix (blocking): `true` once the user taps any flow chip this
  /// session (including re-tapping the already-selected one) — an
  /// explicit choice, as opposed to [_flow]'s initial value merely being
  /// inherited from the loaded entry (which, for a spotting-only day, is
  /// [FlowLevel.notBleeding] only because spotting raised it there, never
  /// because anyone chose "Not bleeding" on purpose). See
  /// [_resolveEffectiveFlow]'s `revertToNone`.
  bool _flowExplicitlySet = false;

  /// Issue #889: `true` when turning the Spotting toggle on is what raised
  /// the in-memory [_flow] from [FlowLevel.none] to
  /// [FlowLevel.notBleeding]. Turning spotting back off is then allowed to
  /// undo exactly that raise (through [resolveEffectiveFlow]'s own
  /// `revertToNone`), while an explicit "Not bleeding" — tapped this
  /// session or loaded that way — is never reverted. Reset whenever
  /// spotting is turned off.
  bool _spottingRaisedFlow = false;

  /// Issue #887: the profile's bleed dates excluding this sheet's own
  /// date, snapshotted once at open by [_loadBleedHistory] — the history
  /// the cycle-start guard evaluates against. Null until the load
  /// settles, and permanently null when it fails: the guard fails open
  /// (a silent no-op, exactly the pre-#887 behavior) because logging
  /// must never be blocked on a disclosure guard's own read.
  Set<LocalDate>? _otherBleedDates;

  /// The observations repository backing the spotting toggle (#247),
  /// resolved once the sheet is in the tree ([Provider.of] is illegal in
  /// `initState`) and cached so a write started while mounted can finish
  /// its [_syncSpottingObservation] step after the sheet has gone (a
  /// dismissal-time autosave flush outlives its widget — #335's save
  /// skipped the sync in that case; autosave must not silently drop the
  /// toggle's state instead).
  ObservationsRepository? _observationsRepository;

  /// Issue #257: the profile's custom-tag registry repository, resolved
  /// exactly like [_observationsRepository] (nullable lookup — a bare test
  /// harness with no provider resolves null and the whole custom-tags
  /// surface stays hidden). Watched live so a co-guardian's registry write
  /// (a tag created on another device) re-renders the picker mid-session.
  TagRegistryRepository? _tagRegistry;
  List<CustomTag> _registry = const [];
  StreamSubscription<List<CustomTag>>? _registrySub;

  /// Issue #257: codes the registry owns (live rows, retired included — a
  /// retired tag stays a valid stored value), for [validateTagCodes]: a
  /// code this profile's registry owns is as valid as a curated one.
  Set<String> get _registryCodes => {
        for (final tag in _registry) tag.code,
      };

  /// Issue #257: resolves a stored tag code for display — the taxonomy's
  /// label first, then the registry entry's display name (a retired tag's
  /// rows keep rendering by name), else the raw code (#237's
  /// unknown-never-drop rule: a code not yet synced to this device's
  /// registry copy renders as text, never dropped).
  String _displayOf(String code) {
    final curated = tagByCode(code);
    if (curated != null) return curated.display;
    for (final tag in _registry) {
      if (tag.code == code) return tag.displayName;
    }
    return code;
  }

  /// The mode's headings and surfacing order (Issue #131).
  CareModeCopy get _copy => careModeCopyFor(widget.mode);

  /// The categories this sheet surfaces, resolved per Issue #259 (AC2):
  /// the profile's curated set and order first, then the uncurated
  /// remainder in the mode's default order, with the minor-visibility
  /// default applied to categories the document never mentions (AC4).
  /// Resolved once per sheet session (`late final`): the sheet is a modal
  /// route whose State is not recreated by a shell rebuild, so a document
  /// change arriving while the sheet is open applies the next time the
  /// sheet opens. (The `mode` copy getter above IS rebuilt per access.)
  late final List<TagCategory> _categoriesInOrder =
      _resolveCategoriesInOrder();

  /// Issue #204: the resolved category order for this sheet — #259's curated
  /// order, then Conceive mode's fertility-first reordering (Tests, then
  /// Discharge) when [DaySheet.lifecycleMode] is [LifecycleMode.conceive].
  /// `conceiveCategoryOrder` only reorders; it never drops a category, so
  /// Conceive mode still logs everything the other modes do.
  ///
  /// Issue #196: Perimenopause mode applies the same reorder-only rule with
  /// `perimenopauseCategoryOrder` (hot flashes, then the sleep/energy/mind/
  /// feelings cluster), so the mode's symptom vocabulary is what the sheet
  /// leads with. The two life-stage reorderings are mutually exclusive —
  /// [DaySheet.lifecycleMode] is a single mode.
  List<TagCategory> _resolveCategoriesInOrder() {
    final resolved = resolveTrackingCategories(
      defaultOrder: _copy.categoriesInOrder,
      preferences: widget.trackingPreferences,
      isMinor: widget.isMinor,
    );
    if (widget.lifecycleMode == LifecycleMode.conceive) {
      return conceiveCategoryOrder(resolved);
    }
    if (isPerimenopauseMode(widget.lifecycleMode)) {
      return perimenopauseCategoryOrder(resolved);
    }
    return resolved;
  }

  /// Stored codes absent from [kTagTaxonomy] at load time (#237): the chip
  /// grid below only ever renders [kTagTaxonomy] members, so a code the
  /// running build does not recognise would otherwise be adopted into
  /// [_tags] invisibly and undeselectably. Rendered separately as inert
  /// chips (`_unrecognisedTagsSection`) and never touched by the taxonomy
  /// chip grid's `onSelected`, so they round-trip through autosave
  /// unchanged.
  late final List<String> _unrecognisedTags;

  /// Codes the user actively picked from the visible taxonomy chip grid
  /// this editing session (#237) — as opposed to [_tags], which also holds
  /// whatever the entry already carried (including [_unrecognisedTags]).
  /// [validateTagCodes] is invoked against only this set before a write,
  /// never against the full adopted [_tags]: a pre-existing unknown code
  /// must never be re-validated (and rejected) just because a change was
  /// autosaved.
  final Set<String> _sessionSelectedTags = {};

  /// The day's `observations` rows carrying a non-null `raw` escape-hatch
  /// payload (Issue #199): an unrecognised Clue `type`/`value` shape the
  /// importer kept as-is rather than dropping. Rendered below as readable
  /// text ([_unmappedObservationsSection]) so an imported-but-unmapped row
  /// is never invisible; inert like [_unrecognisedTags] (display only,
  /// never edited here).
  ///
  /// Deliberately NOT counted by [_childObservationsLoadsPending]: that
  /// counter gates the read-only body's loading row for spotting and pain
  /// intensity, both of which the read-only view has no natural empty
  /// state to fall back on. This section simply renders nothing until it
  /// resolves, which reads correctly as "no unmapped rows on this day".
  List<Observation> _unmappedObservations = [];

  /// Issue #234: this profile's "recently used tags" (device-local, per
  /// profile — `lib/domain/logging/tag_recents.dart`), backing
  /// [CategoryPicker]'s Recent row. Most-recent-first; loaded once per
  /// sheet session by [_loadTagRecents] and updated optimistically by
  /// [_toggleTag] via [withRecordedTagUse] the moment a tag is picked, so
  /// the row reflects the pick immediately rather than waiting on the
  /// settings-store round trip.
  List<String> _tagRecents = const [];

  /// Issue #226: the Calendar → "Date format" preference, resolved once the
  /// ambient [SettingsStore] seeds it (null store — a bare test harness —
  /// keeps `system`, the pre-#226 rendering). Watched live so a picker
  /// change re-renders the sheet's date header on the next build.
  DateFormatPreference _dateFormat = DateFormatPreference.system;
  StreamSubscription<String?>? _dateFormatSub;

  @override
  void initState() {
    super.initState();
    final settingsStore = context.read<SettingsStore?>();
    if (settingsStore != null) {
      _dateFormatSub = settingsStore
          .watch(SettingsKeys.dateFormat)
          .listen((value) {
            if (mounted) {
              setState(
                () => _dateFormat = DateFormatPreference.fromStored(value),
              );
            }
          });
    }
    final existing = widget.existing;
    _persistedEntryId = existing?.id;
    _flow = existing?.flow ?? FlowLevel.none;
    _tags = {...?existing?.tags};
    _pms = existing?.pms ?? false;
    _unrecognisedTags = [
      for (final code in existing?.tags ?? const <String>[])
        if (!isValidTagCode(code)) code,
    ];
    _noteController = TextEditingController(text: existing?.note ?? '');
    // Every keystroke re-arms the autosave debounce (#198): the controller
    // is created with its initial text above, so the listener never fires
    // for the seeded value itself.
    _noteController.addListener(_markDirty);
    // Issue #457: created empty here (never seeded with initial text the
    // way the note field is) — any already-persisted value arrives
    // asynchronously via `_loadExistingMeasurements` below, which sets the
    // controller's text explicitly once it resolves, exactly like
    // `_loadExistingSpotting`/`_loadExistingPainIntensity` seed their own
    // state after an async repository read.
    _bbtController = TextEditingController()..addListener(_onBbtChanged);
    _weightController = TextEditingController()
      ..addListener(_onWeightChanged);
    if (existing != null) {
      _childObservationsLoading = true;
      _childObservationsLoadsPending = 2;
      unawaited(_loadExistingSpotting(existing.id));
      unawaited(_loadExistingPainIntensity(existing.id));
      unawaited(_loadExistingMeasurements(existing.id));
      unawaited(_loadUnmappedObservations(existing.id));
    }
    // Issue #234: the read-only sheet never builds CategoryPicker, so it
    // has no Recent row to seed.
    if (!widget.readOnly) unawaited(_loadTagRecents());
    // Issue #130: the merge-notice list for this date (rendered read-only
    // or not — the disclosure is informational, never an edit).
    unawaited(_loadMergeEvents());
    // Issue #887: the bleed history the cycle-start guard evaluates
    // against (see [_otherBleedDates]).
    unawaited(_loadBleedHistory());
  }

  /// Issue #887: loads the profile's bleed dates (excluding this sheet's
  /// own date) for the cycle-start guard. Session-scoped by design: a
  /// co-guardian's sync landing mid-session is seen by the next sheet
  /// open, not this one — the same staleness every other once-per-open
  /// read here (the merge-notice list, the child observations) carries.
  /// A failure fails open and is reported to Sentry: a safety disclosure
  /// silently going dark is worth a breadcrumb, but never worth blocking
  /// the sheet over.
  Future<void> _loadBleedHistory() async {
    try {
      final entries = await widget.repository.listForProfile(
        widget.profileId,
      );
      if (!mounted) return;
      _otherBleedDates = {
        for (final entry in entries)
          if (entry.deletedAt == null &&
              entry.localDate != widget.date &&
              isBleed(entry.flow))
            entry.localDate,
      };
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  /// Issue #130: loads this date's undismissed merge disclosures through
  /// the day-entries repository (the notice surface this feature owns). A
  /// failure never blocks the sheet — the notices are additive metadata,
  /// not logging state.
  Future<void> _loadMergeEvents() async {
    try {
      final events =
          await widget.repository.mergeEventsForDay(widget.profileId, widget.date);
      if (!mounted) return;
      setState(() => _mergeEvents = events);
    } on Exception {
      // Deliberately quiet (R18's posture): a failed notice read leaves
      // the sheet exactly as it was before this feature existed.
    }
  }

  /// Issue #130: dismisses one notice on THIS device only (the repository
  /// write is the device-local dismissal list, never a tombstone) and
  /// drops it from the visible list immediately.
  Future<void> _dismissMergeEvent(DayEntryMergeEvent event) async {
    setState(() => _mergeEvents = [
          for (final e in _mergeEvents)
            if (e.id != event.id) e,
        ]);
    await widget.repository.dismissMergeEvent(widget.profileId, event.id);
  }

  /// Issue #130: restores the losing author's discarded note into the note
  /// field — a re-entry of their own text, not an edit of the merged
  /// entry's other values. An empty field takes the text outright;
  /// a non-empty one appends it on a new line (never silently replaces
  /// text the user may have typed since opening the sheet). The
  /// controller's listener re-arms autosave.
  void _restoreMergedNote(DayEntryMergeEvent event) {
    final current = _noteController.text;
    _noteController.text = current.trim().isEmpty
        ? event.losingValueText
        : '$current\n${event.losingValueText}';
  }

  /// Issue #130: restores the losing author's discarded flow level via the
  /// sheet's single flow write path. Only offered when the retained wire
  /// string parses to a real level (it always does — the server CHECKs
  /// the set — but an unknown value degrades to leaving the selection
  /// untouched rather than silently selecting `none`).
  void _restoreMergedFlow(DayEntryMergeEvent event) {
    final match = FlowLevel.values
        .where((level) => level.toDb() == event.losingValueText)
        .firstOrNull;
    // Issue #887: the restore rides the same guarded write path as a chip
    // tap — a restored bleed can be an early cycle start too, and the
    // author deserves the same disclosure before it lands.
    if (match != null) unawaited(_selectFlow(match));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Nullable lookup: a sheet pumped where no repository is reachable at
    // all (e.g. the future-date guard in tests) resolves null rather than
    // throwing — [_syncSpottingObservation] then simply skips, since no
    // write can happen in those states anyway.
    _observationsRepository ??= Provider.of<ObservationsRepository?>(
      context,
      listen: false,
    );
    // Issue #257: same nullable-lookup rule; the registry watch is armed
    // once, here, because the repository only becomes reachable once the
    // sheet is in the tree. A null (no provider in scope) leaves the
    // custom-tags surface entirely absent — the pre-#257 sheet.
    if (_tagRegistry == null) {
      final tagRegistry = Provider.of<TagRegistryRepository?>(
        context,
        listen: false,
      );
      if (tagRegistry != null) {
        _tagRegistry = tagRegistry;
        _registrySub = tagRegistry
            .watchForProfile(widget.profileId)
            .listen((tags) {
          if (mounted) setState(() => _registry = tags);
        });
      }
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _savedIndicatorTimer?.cancel();
    unawaited(_dateFormatSub?.cancel());
    _dateFormatSub = null;
    unawaited(_registrySub?.cancel());
    _registrySub = null;
    if (!_discardUnsaved) _applyDisposeAction(daySheetDisposeAction(_saveState));
    _noteController.dispose();
    _bbtController.dispose();
    _weightController.dispose();
    _bbtFocus.dispose();
    _weightFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Executes the pure decision [daySheetDisposeAction] computed — kept out
  /// of [dispose] itself so that method's own cyclomatic complexity (the
  /// CRAP gate flagged it, issue #601 review) stays low; see
  /// [DaySheetDisposeAction]'s own doc in `day_sheet_save_state.dart` for
  /// the reasoning behind each case, carried forward from the inline
  /// `switch` this replaces.
  void _applyDisposeAction(DaySheetDisposeAction action) {
    switch (action) {
      case DaySheetDisposeFlush(:final pending):
        _flushOnDispose(pending);
      case DaySheetDisposeRetrigger(:final nextState):
        // Its continuation runs once the in-flight write completes
        // regardless of `mounted` (`widget`/`_observationsRepository` stay
        // valid to read), and correctly fires even post-dispose —
        // `daySheetSettleWrite` is pure state, never gated on `mounted`
        // itself, so this queued edit is never silently dropped (#546).
        _saveState = nextState;
      case DaySheetDisposeNoop():
        break;
    }
  }

  /// Belt-and-braces flush (#198) for a teardown that bypassed the normal
  /// dismissal flush ([_onSheetPop], which runs while still mounted): the
  /// entry is composed before the controller dies; the write itself is
  /// fire-and-forget — there is no sheet left to render a failure into, and
  /// the [PopScope] guard has already handled the interactive failure case.
  /// The spotting/pain sync rides along so the persisted entry and its
  /// observation rows can never disagree. Never called while a write is
  /// already in flight ([dispose]'s own switch routes that case to
  /// [daySheetRequestRetrigger] instead), so this never races a concurrent
  /// write for the same entry (issue #546).
  void _flushOnDispose(DayEntry pending) {
    final repository = widget.repository;
    final observations = _observationsRepository;
    // Set the field directly, not via `_updateSaveState` — calling
    // `setState` synchronously from inside `dispose()` itself crashes (the
    // `Element` is already `defunct` by the time a State's own `dispose()`
    // body runs, regardless of what `mounted` reports); the deferred
    // `finally` below runs later, once `mounted` is genuinely false, so
    // nothing here ever calls `setState`.
    _saveState = DaySheetSaving(pending);
    scheduleMicrotask(() async {
      try {
        final mutations = await _computeObservationMutations(
          pending,
          observations,
        );
        await repository.saveDayEntryWithObservations(
          entry: pending,
          observationsToUpsert: mutations.toUpsert,
          observationIdsToDelete: mutations.toDelete,
        );
      } catch (error, stackTrace) {
        // Issue #546: this used to be a bare `catch (_) {}` — the
        // operator's edit could be silently lost (DB locked during a
        // sync apply, disk full, closing the DB during a reset)
        // with nothing, UI or telemetry, ever saying so. There is
        // no sheet left to show a retry banner in, so this is
        // observability only, not recovery — captured the same way
        // every other data-layer failure in this codebase is.
        // Issue #923: a date-bounds rejection is the one exception —
        // it is user input, not a bug, and must not be reported.
        if (classifyDaySheetWriteError(error) ==
            DaySheetWriteErrorClass.bug) {
          unawaited(Sentry.captureException(error, stackTrace: stackTrace));
        }
      } finally {
        // Nothing reads `_saveState` again once this State is unreachable
        // (the microtask closure above is the only remaining reference to
        // `this`) — restored to `DaySheetDirty` rather than `DaySheetIdle`
        // only to mirror the old fields' literal end values exactly
        // (`_saving = false` via `_setAutosaveState`, `_dirty`/
        // `_pendingEntry` left untouched by this path either way).
        _saveState = DaySheetDirty(pending);
      }
    });
  }

  /// Records a pending change and re-arms the autosave debounce (#198).
  void _markDirty() {
    if (widget.readOnly || widget.date.isAfter(widget.today)) return;
    _saveState = daySheetMarkDirty(_saveState, _composeEntry());
    _saveDebounce?.cancel();
    _saveDebounce = Timer(kDaySheetAutosaveDelay, _performAutosave);
  }

  /// Snapshots the current editing state into the entry the next write
  /// will persist — called synchronously on change and before any await,
  /// never from a disposed context (the note controller must be alive).
  /// The flow written is [resolveEffectiveFlow]'s (#247): spotting's
  /// presence/absence is expressed in the entry's `flow` exactly the way
  /// #335's explicit Save did, on every debounced write.
  DayEntry _composeEntry() {
    final note = _noteController.text.trim();
    final tz = (widget.timezoneProvider ?? resolveCurrentTimeZoneSync)();
    final entryId = _persistedEntryId ?? widget.existing?.id ?? '';
    return DayEntry(
      id: entryId,
      profileId: widget.profileId,
      localDate: widget.date,
      tz: tz,
      flow: resolveEffectiveFlow(
        spotting: _spotting,
        flow: _flow,
        hadSpottingOnLoad: _hadSpottingOnLoad,
        flowExplicitlySet: _flowExplicitlySet,
      ),
      tags: _tags.toList(),
      note: note.isEmpty ? null : note,
      // Issue #220: the first-class PMS marker rides the entry itself.
      pms: _pms,
      updatedAt: DateTime.now().toUtc(),
      // Issue #159 review finding: a bare `DayEntry(...)` defaults to
      // manual/null/null, which would silently reset an imported entry's
      // provenance on every write (even a no-op one) — carry forward
      // whatever the loaded entry already had instead.
      source: widget.existing?.source ?? DayEntrySource.manual,
      sourceId: widget.existing?.sourceId,
      importId: widget.existing?.importId,
    );
  }

  /// The debounced autosave write (#198). Also the Retry handler for a
  /// failed write ([daySheetBeginSave] treats [DaySheetFailed] the same as
  /// [DaySheetDirty] — see its own doc). Never closes the sheet.
  Future<void> _performAutosave() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (_saveState is DaySheetSaving) {
      // A write is in flight (e.g. the debounce timer refired, or
      // dismissal flushed while one ran); mark it for retrigger so its
      // completion re-runs with the latest state, per [daySheetSettleWrite].
      _saveState = daySheetRequestRetrigger(_saveState);
      return;
    }
    final started = daySheetBeginSave(_saveState);
    // Idle, Saved, or a terminal Deleting/Deleted (issue #601 LLA-003):
    // nothing may start.
    if (started == null) return;
    _updateSaveState(started); // Optimistic; failure restores below.
    final writeFuture = _writePending(started.inFlight);
    // Issue #601 LLA-003: published for the exact duration of this write
    // so `_delete` can await it -- see `_inFlightWrite`'s own doc.
    _inFlightWrite = writeFuture;
    final saved = await writeFuture;
    _inFlightWrite = null;
    final (settled, retrigger) =
        daySheetSettleWrite(_saveState, succeeded: saved);
    if (saved) {
      _onAutosaveSuccess(settled);
    } else {
      _updateSaveState(settled);
    }
    if (retrigger) unawaited(_performAutosave());
  }

  /// Updates [_saveState]. Issue #546: the field always updates, even once
  /// the sheet has gone (a dismissal-time flush outlives the widget that
  /// started it) — [_performAutosave]'s reentrancy check and [dispose]'s
  /// own switch both read `_saveState` to decide whether a write is
  /// already in flight, and that must stay accurate whether or not the
  /// sheet is still mounted. Only the `setState` rebuild — which would
  /// throw once the widget is gone — is skipped while unmounted.
  void _updateSaveState(DaySheetSaveState next) {
    _saveState = next;
    if (!mounted) return;
    setState(() {});
  }

  /// Persists [pending] and its child observations atomically (Issue #471).
  /// Pure I/O — never touches [_saveState] itself; [_performAutosave]
  /// settles the state uniformly for both outcomes via
  /// [daySheetSettleWrite].
  Future<bool> _writePending(DayEntry pending) async {
    // Captured while every caller is still mounted: the write below may
    // complete after this sheet has gone (a dismissal-time flush), and
    // `Provider.of` from a dead context throws.
    final observations = _observationsRepository;
    try {
      // Only the codes freshly picked this session from the visible
      // taxonomy chip grid are validated (#237) — never the full adopted
      // `_tags`, which may still hold a pre-existing code the running build
      // does not recognise (`_unrecognisedTags`). That code is preserved,
      // not silently re-validated and rejected, on every autosave.
      // Issue #257: the profile's registry codes join the valid set — a
      // custom tag picked from the picker's custom-tags section is as
      // valid as a curated one (retired codes included: a retired tag
      // stays a valid stored value).
      validateTagCodes(_sessionSelectedTags, registryCodes: _registryCodes);
      final mutations = await _computeObservationMutations(
        pending,
        observations,
      );
      final saved = await widget.repository.saveDayEntryWithObservations(
        entry: pending,
        observationsToUpsert: mutations.toUpsert,
        observationIdsToDelete: mutations.toDelete,
      );
      _persistedEntryId = saved.id;
      _saveErrorClass = null;
      return true;
    } catch (error, stackTrace) {
      // Issue #923: distinguish a date-bounds rejection (#848 — a
      // user-input condition with rule-specific copy) from a genuine bug
      // such as a chip grid letting an unrecognised code through
      // `_sessionSelectedTags`. The classification reads the typed
      // `DayEntryDateOutOfBounds.violation`, never a message string. A
      // bounds rejection is NOT reported to Sentry; a real bug still is,
      // with its real type rather than being lost in the generic bucket.
      final errorClass = classifyDaySheetWriteError(error);
      _saveErrorClass = errorClass;
      if (errorClass == DaySheetWriteErrorClass.bug) {
        unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      }
      return false;
    }
  }

  /// Post-success bookkeeping: [settled] is already computed (by
  /// [daySheetSettleWrite] in [_performAutosave]) — this applies it, latches
  /// the offline acknowledgement messenger (issue #182 AC8 — it is shown
  /// when the sheet is dismissed, not now, because an open modal sheet's
  /// barrier hides a SnackBar), and arms the transient "Saved"
  /// micro-confirmation's own clear timer whenever [settled] actually is
  /// [DaySheetSaved] (see that class's doc for the one case it is not: a
  /// further edit already arrived and is not yet due its own retry).
  void _onAutosaveSuccess(DaySheetSaveState settled) {
    // Issue #546: through `_updateSaveState` so the field resets even once
    // the sheet has gone — a dismissal-time success leaving it permanently
    // stuck on `DaySheetSaving` would make [_performAutosave]'s own
    // reentrancy check queue a later edit forever without ever actually
    // writing it.
    _updateSaveState(settled);
    if (!mounted) return;
    _offlineAckMessenger ??= _offlineConfirmationMessenger(context);
    if (settled is DaySheetSaved) {
      _savedIndicatorTimer?.cancel();
      _savedIndicatorTimer = Timer(kDaySheetSavedIndicatorDuration, () {
        if (mounted && _saveState is DaySheetSaved) {
          setState(() => _saveState = const DaySheetIdle());
        }
      });
    }
  }

  /// Issue #247: the day sheet doesn't otherwise load `observations` rows
  /// — this is the one exception, populating the "Spotting" toggle's
  /// initial state from any already-persisted spotting observation for
  /// [dayEntryId]. Issue #549: goes through
  /// [ObservationsRepository.listForDayEntryWithLegacyAlias] — scoped to
  /// this one day entry via [ObservationsRepository.listForDayEntry] plus a
  /// single-row day-entry lookup — rather than [ObservationsRepository]
  /// .listForProfile, which decoded every observation and every day entry
  /// the profile has ever logged just to answer this one-day question.
  Future<void> _loadExistingSpotting(String dayEntryId) async {
    try {
      final observations = await Provider.of<ObservationsRepository>(
        context,
        listen: false,
      ).listForDayEntryWithLegacyAlias(dayEntryId);
      if (!mounted) return;
      setState(() {
        if (observations.any((o) => o.category == ObservationCategory.spotting)) {
          _spotting = true;
          _hadSpottingOnLoad = true;
        }
        _childObservationLoadSettled();
      });
    } catch (error, stackTrace) {
      // Issue #642, LLA-011: previously unhandled — a failure here left
      // the editable toggle silently unset (a tolerable default) but the
      // read-only view had no signal at all that anything had gone
      // wrong, rather than a genuine "no spotting logged" fact.
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      if (!mounted) return;
      setState(() => _childObservationLoadSettled(failed: true));
    }
  }

  /// Issue #256: seeds [_painIntensity] from the day's already-persisted
  /// graded pain observations (`category: 'pain'`, `intensity` not null),
  /// so an existing grade — including an imported one — shows up on the
  /// selector and is never silently dropped by an autosave that never
  /// touched it. When several live rows carry the same code (possible in
  /// imported data; local writes resolve one row per code), the highest
  /// grade wins — the severity reading a caregiver alert would act on.
  ///
  /// Issue #642 review (CRAP gate): the decode/merge itself is
  /// [gradedPainIntensitiesFrom] (`day_sheet_reconciliation.dart`, pure,
  /// its own unit tests) — this method stays the thin impure shell around
  /// it (the repository fetch, the mount check, and the
  /// setState/error handling every other loader here uses).
  Future<void> _loadExistingPainIntensity(String dayEntryId) async {
    try {
      final observations = await Provider.of<ObservationsRepository>(
        context,
        listen: false,
      ).listForDayEntry(dayEntryId);
      if (!mounted) return;
      setState(() {
        _painIntensity.addAll(gradedPainIntensitiesFrom(observations));
        _childObservationLoadSettled();
      });
    } catch (error, stackTrace) {
      // Issue #642, LLA-011: see the matching catch in
      // [_loadExistingSpotting] — same reasoning.
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      if (!mounted) return;
      setState(() => _childObservationLoadSettled(failed: true));
    }
  }

  /// Issue #457: seeds the BBT/weight fields from any already-persisted
  /// **manual** measurement for [dayEntryId] — the same one-day-scoped read
  /// [_loadExistingPainIntensity] uses. A row is converted from whatever
  /// unit it is actually stored in into [DaySheet.bbtUnit]/
  /// [DaySheet.weightUnit] so the field always displays in the profile's
  /// current unit, mirroring `measurement_unit.dart`'s read-time-only
  /// conversion contract; a manual row with no [Observation.valueNum] at
  /// all (defensively unreachable — this app never writes one) is treated
  /// as absent rather than seeding an empty/NaN field. Never adopts a
  /// same-category row from another source (a wearable/imported value),
  /// matching [computeMeasurementMutations]'s own write-side discipline —
  /// that value still exists and still charts, it is simply not this
  /// field's to show or edit.
  Future<void> _loadExistingMeasurements(String dayEntryId) async {
    final observations = await Provider.of<ObservationsRepository>(
      context,
      listen: false,
    ).listForDayEntry(dayEntryId);
    if (!mounted) return;
    Observation? manualRowOf(ObservationCategory category) {
      for (final o in observations) {
        if (o.category == category &&
            o.source == ObservationSource.manual &&
            o.valueNum != null) {
          return o;
        }
      }
      return null;
    }

    final bbtRow = manualRowOf(ObservationCategory.bbt);
    final weightRow = manualRowOf(ObservationCategory.weight);
    if (bbtRow == null && weightRow == null) return;
    setState(() {
      _seedingMeasurements = true;
      if (bbtRow != null) {
        final displayValue = convertTemperature(
          bbtRow.valueNum!,
          from: BbtUnit.fromDb(bbtRow.unit),
          to: widget.bbtUnit,
        );
        _bbtValue = displayValue;
        _bbtExcluded = bbtRow.excluded;
        _bbtController.text = formatMeasurementValue(displayValue);
      }
      if (weightRow != null) {
        final displayValue = convertWeight(
          weightRow.valueNum!,
          from: WeightUnit.fromDb(weightRow.unit),
          to: widget.weightUnit,
        );
        _weightValue = displayValue;
        _weightExcluded = weightRow.excluded;
        _weightController.text = formatMeasurementValue(displayValue);
      }
      _seedingMeasurements = false;
    });
  }

  /// Issue #457: the day sheet's own listener for [_bbtController] —
  /// mirrors the note field's "every keystroke re-arms the autosave
  /// debounce" rule, with one difference: an invalid keystroke (unparsable,
  /// or parseable but outside [isValidBbt]'s sanity range) sets
  /// [_bbtError] for the inline error and returns *without* touching
  /// [_bbtValue] or calling [_markDirty] — so a stray character typed while
  /// editing an already-valid value can never itself delete or corrupt
  /// that value's autosaved state. Correcting the text back to something
  /// valid (or clearing it entirely, which is itself always valid — an
  /// explicit "clear this reading") resumes autosaving normally. Suppressed
  /// entirely while [_seedingMeasurements] is true (see that field's doc).
  void _onBbtChanged() {
    if (_seedingMeasurements) return;
    final text = _bbtController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _bbtValue = null;
        _bbtError = null;
      });
      _markDirty();
      return;
    }
    final parsed = double.tryParse(text);
    if (parsed == null) {
      setState(
        () => _bbtError = AppLocalizations.of(context)
            .daySheetMeasurementInvalidNumber,
      );
      return;
    }
    if (!isValidBbt(parsed, widget.bbtUnit)) {
      setState(() => _bbtError = _bbtRangeErrorText());
      return;
    }
    setState(() {
      _bbtValue = parsed;
      _bbtError = null;
    });
    _markDirty();
  }

  /// Weight's mirror of [_onBbtChanged] — same contract throughout.
  void _onWeightChanged() {
    if (_seedingMeasurements) return;
    final text = _weightController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _weightValue = null;
        _weightError = null;
      });
      _markDirty();
      return;
    }
    final parsed = double.tryParse(text);
    if (parsed == null) {
      setState(
        () => _weightError = AppLocalizations.of(context)
            .daySheetMeasurementInvalidNumber,
      );
      return;
    }
    if (!isValidWeight(parsed, widget.weightUnit)) {
      setState(() => _weightError = _weightRangeErrorText());
      return;
    }
    setState(() {
      _weightValue = parsed;
      _weightError = null;
    });
    _markDirty();
  }

  String _bbtRangeErrorText() {
    final (min, max) = bbtRangeIn(widget.bbtUnit);
    return AppLocalizations.of(context).daySheetBbtRangeError(
      formatMeasurementValue(min),
      formatMeasurementValue(max),
    );
  }

  String _weightRangeErrorText() {
    final (min, max) = weightRangeIn(widget.weightUnit);
    return AppLocalizations.of(context).daySheetWeightRangeError(
      formatMeasurementValue(min),
      formatMeasurementValue(max),
    );
  }

  /// Issue #457: BBT's per-point "exclude from charts" flag (A1-44), reused
  /// for weight — toggling it never deletes or changes the logged value
  /// itself, only whether the BBT chart (#245) plots this one point.
  /// Disabled while there is no current value to exclude (rendered only
  /// when [_bbtValue]/[_weightValue] is non-null — see [_measurementsSection]).
  void _toggleBbtExcluded() {
    LLHaptics.selection();
    setState(() => _bbtExcluded = !_bbtExcluded);
    _markDirty();
  }

  void _toggleWeightExcluded() {
    LLHaptics.selection();
    setState(() => _weightExcluded = !_weightExcluded);
    _markDirty();
  }

  /// Fetches the target day entry's already-persisted observation rows and
  /// delegates to [computeObservationMutations] (issue #601 — moved to
  /// `lib/domain/logging/day_sheet_reconciliation.dart`, pure) for the
  /// spotting (#247) and graded pain-intensity (#256) upserts/deletes to
  /// commit atomically alongside [pending] (Issue #471). The repository
  /// fetch is the one impure half that has to stay here.
  Future<ObservationMutations> _computeObservationMutations(
    DayEntry pending,
    ObservationsRepository? observations,
  ) async {
    if (observations == null) return const ObservationMutations();
    final targetId =
        _persistedEntryId ??
        (pending.id.isNotEmpty ? pending.id : (widget.existing?.id ?? ''));
    List<Observation> existingObs = const [];
    if (targetId.isNotEmpty) {
      existingObs = await observations.listForDayEntry(targetId);
    }
    return computeObservationMutations(
      existingObservations: existingObs,
      spotting: _spotting,
      painIntensity: _painIntensity,
      // Issue #457: the BBT/weight fields' last-validated values, not the
      // controllers' raw (possibly currently-invalid) text — see
      // `_onBbtChanged`/`_onWeightChanged`'s own doc for why an in-progress
      // invalid keystroke must never reach a write.
      bbtValue: _bbtValue,
      bbtUnit: widget.bbtUnit.toDb(),
      bbtExcluded: _bbtExcluded,
      weightValue: _weightValue,
      weightUnit: widget.weightUnit.toDb(),
      weightExcluded: _weightExcluded,
      targetDayEntryId: targetId,
      profileId: widget.profileId,
      date: widget.date,
      tz: pending.tz,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Issue #182 AC8: captured before the sheet goes away (the sheet's own
  /// context is gone right after), so the confirmation still reaches the
  /// screen underneath — `ScaffoldMessenger.of` resolves to the app's single
  /// root messenger regardless, but capturing early avoids relying on that.
  /// Null (no SnackBar at all) unless [shouldConfirmOfflineSave] says so.
  ScaffoldMessengerState? _offlineConfirmationMessenger(BuildContext context) {
    final shouldConfirm = shouldConfirmOfflineSave(
      snapshot: Provider.of<SyncStatusController?>(
        context,
        listen: false,
      )?.snapshot,
      authState: Provider.of<AuthController?>(context, listen: false)?.state,
    );
    return shouldConfirm ? ScaffoldMessenger.of(context) : null;
  }

  Future<void> _delete() async {
    // Issue #574: resolved once, not on every Text/label below.
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.daySheetDeleteTitle),
        content: SingleChildScrollView(
          child: Text(
            l10n.daySheetDeleteBody(
              daySheetDateLabel(
                widget.date,
                widget.today,
                locale: dates.calendarLocale(context),
                preference: _dateFormat,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.daySheetCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.daySheetDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    LLHaptics.destructive();
    // Issue #601 LLA-003 audit finding: a delete must never be undone by
    // an autosave -- neither a not-yet-started queued edit (dropped
    // outright below: deleting supersedes it) nor an already in-flight
    // write completing *after* this point and resurrecting the row via
    // its own upsert (`deletedAt: null`). Cancel the debounce (nothing
    // not-yet-started may begin), then transition to [DaySheetDeleting]
    // -- a terminal state [daySheetMarkDirty]/[daySheetBeginSave] both
    // refuse to act on -- *before* awaiting whatever write is already in
    // flight: that ordering is what makes this the actual fix, not merely
    // documentation. Once [_saveState] reads [DaySheetDeleting], that
    // write's own eventual [daySheetSettleWrite] call finds `state is!
    // DaySheetSaving` and silently drops its result instead of applying
    // or retriggering it (see [DaySheetDeleting]'s own doc for the full
    // reasoning).
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final inFlight = _inFlightWrite;
    _saveState = const DaySheetDeleting();
    setState(() {
      _busy = true;
      _deleteFailed = false;
    });
    if (inFlight != null) {
      // Whatever that write's own outcome, deletion proceeds regardless --
      // it must not get stuck behind, or be derailed by, a save that is
      // about to be superseded anyway. `_writePending` already reports
      // (and Sentry-captures) its own failures; nothing further to do
      // with them here.
      await inFlight.catchError((_) {});
    }
    // Issue #856: capture the full pre-delete state *before* the tombstone,
    // read back from the repository so it reflects the latest autosaved
    // write rather than the (possibly stale) entry the sheet opened with.
    // The undo restores exactly this, through the same repository path.
    final repository = widget.repository;
    final priorEntry = await _captureDeletedEntry(repository);
    final priorObservations = await _captureDeletedObservations(priorEntry);
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    try {
      await repository.delete(widget.profileId, widget.date);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleteFailed = true;
          // Deletion did not go through. Nothing was pending before
          // [DaySheetDeleting] (it discarded any queued edit outright,
          // matching the pre-#601 code's own unconditional drop on every
          // delete attempt, successful or not), so Idle -- not a stuck
          // terminal state -- is what lets a further edit or another
          // delete attempt work normally again.
          _saveState = const DaySheetIdle();
        });
      }
      return;
    }
    _saveState = const DaySheetDeleted();
    if (mounted) {
      // A latched offline acknowledgement is about the *saved* entry — the
      // entry is now deleted, so it must not fire as the sheet leaves.
      _offlineAckMessenger = null;
      if (priorEntry != null) {
        _showDeleteUndoSnackbar(
          messenger,
          l10n,
          repository,
          priorEntry,
          priorObservations,
        );
      }
      Navigator.of(context).pop();
    }
  }

  /// Issue #856: the live day entry the delete is about to tombstone, read
  /// back through [repository] immediately before the tombstone so the undo
  /// snapshot carries the entry's current persisted payload (flow, tags,
  /// note, PMS, provenance) — not the possibly-stale `widget.existing` the
  /// sheet opened with. A read failure leaves the undo unable to restore the
  /// row rather than aborting the delete; nothing here is on the delete's
  /// critical path.
  Future<DayEntry?> _captureDeletedEntry(DayEntriesRepository repository) async {
    try {
      return await repository.find(widget.profileId, widget.date);
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      return null;
    }
  }

  /// Issue #856: every live observation row attached to [entry] — spotting,
  /// graded pain intensities, BBT/weight measurements, and any imported or
  /// health-authored row — captured with its full payload so the undo can
  /// revive the same rows (never fresh ones). The tombstone cascade clears
  /// these rows' payloads, so this must run before the delete.
  Future<List<Observation>> _captureDeletedObservations(DayEntry? entry) async {
    final observations = _observationsRepository;
    if (entry == null || observations == null) return const [];
    try {
      return await observations.listForDayEntry(entry.id);
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      return const [];
    }
  }

  /// Issue #856: shows the post-delete snackbar with an Undo action,
  /// mirroring `overview_panel.dart`'s `today-card-logged-snackbar` shape
  /// (same content-plus-action layout, `SnackBar`'s own default duration).
  /// The restore runs only from the explicit action tap, so an ignored or
  /// dismissed snackbar simply leaves the delete in place. [messenger] is
  /// captured before the pop because this sheet's context is gone by the
  /// time the action can be tapped.
  void _showDeleteUndoSnackbar(
    ScaffoldMessengerState? messenger,
    AppLocalizations l10n,
    DayEntriesRepository repository,
    DayEntry entry,
    List<Observation> observations,
  ) {
    messenger?.showSnackBar(
      SnackBar(
        key: const ValueKey('day-sheet-delete-snackbar'),
        content: Text(l10n.daySheetDeletedSnackbar),
        action: SnackBarAction(
          label: l10n.daySheetUndo,
          onPressed: () => unawaited(_undoDelete(
            repository: repository,
            entry: entry,
            observations: observations,
          )),
        ),
      ),
    );
  }

  /// Issue #856: reverses the delete through the same repository path the
  /// delete itself took — re-saving [entry] and [observations] by their
  /// original ids revives the exact tombstoned rows (`_writeDayEntry`/
  /// `_writeObservation` clear `deletedAt` and rewrite the captured
  /// payload), rather than inserting a fresh day entry with a new id. The
  /// entry carries its own `profileId`, so a profile switch since the delete
  /// never redirects the restore; no `BuildContext` is touched here (the
  /// sheet has long since been disposed when this runs).
  Future<void> _undoDelete({
    required DayEntriesRepository repository,
    required DayEntry entry,
    required List<Observation> observations,
  }) async {
    try {
      await repository.saveDayEntryWithObservations(
        entry: entry,
        observationsToUpsert: observations,
      );
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  /// PopScope wiring (#198): dismissal of a cleanly autosaved (or clean)
  /// sheet just closes; a debounced change still pending is flushed so
  /// dismissal never silently drops it; and a failed-pending sheet refuses
  /// to close without an explicit discard ([_confirmDiscardWhileFailed]).
  ///
  /// Issue #887 adds the dismissal-time cycle-start disclosure: a session
  /// that changed the cycle-start set gets a snackbar with an Undo that
  /// restores the pre-session entry (#316's pattern, the one #856 gave
  /// delete). It queues *behind* the offline acknowledgement when both
  /// are due — #182 AC8's "Saved on this device · will sync" shows the
  /// moment the sheet leaves (that contract is pinned by its own tests),
  /// and ScaffoldMessenger displays queued snackbars in order, so the
  /// estimate-change disclosure with its Undo follows it.
  void _onSheetPop(bool didPop, Object? result) {
    if (!didPop) {
      if (_saveState is DaySheetFailed && !_discardUnsaved) {
        unawaited(_confirmDiscardWhileFailed());
      }
      return;
    }
    _handleSheetPopped();
  }

  /// The didPop half of [_onSheetPop] (split out for the CRAP gate):
  /// flush what a debounce left pending, then show the dismissal-time
  /// snackbars.
  void _handleSheetPopped() {
    // Dirty or Failed both carry unsaved content (mirrors the old
    // `_dirty`, which failure also set) — PopScope's own `canPop` above
    // means Failed only reaches here once `_discardUnsaved` is already
    // true, so this is belt-and-braces for that case too, not just
    // Dirty's normal one.
    final flushPending =
        (_saveState is DaySheetDirty || _saveState is DaySheetFailed) &&
            !_discardUnsaved;
    // Computed before the flush settles the state: an offline-looking flush
    // earns the same "Saved on this device · will sync" acknowledgement a
    // completed save already latched in `_offlineAckMessenger`. The
    // cycle-start evaluation below also reads the pre-flush composed entry
    // — exactly the state the flush is about to persist.
    final messenger =
        _offlineAckMessenger ??
        (flushPending ? _offlineConfirmationMessenger(context) : null);
    final cycleStartSnackBar = _cycleStartChangeSnackBar();
    if (flushPending) unawaited(_performAutosave());
    if (messenger != null) {
      messenger.showSnackBar(
        const SnackBar(
          key: ValueKey('offline-save-confirmation'),
          content: Text(kOfflineSaveConfirmationCopy),
        ),
      );
    }
    if (cycleStartSnackBar != null) {
      ScaffoldMessenger.of(context).showSnackBar(cycleStartSnackBar);
    }
  }

  /// Issue #887: the paths where the sheet's leaving state is not what
  /// persists, so the cycle-start snackbar must stay silent — read-only
  /// and future-dated sheets never write, a discard drops the changes on
  /// purpose, and the delete flow's own Undo snackbar owns its dismissal.
  bool get _cycleStartSnackBarSuppressed =>
      widget.readOnly ||
      widget.date.isAfter(widget.today) ||
      _discardUnsaved ||
      _saveState is DaySheetDeleting ||
      _saveState is DaySheetDeleted;

  /// Issue #887: the Undo snackbar for a dismissal whose session changed
  /// the cycle-start set, or null when it didn't (or can't be known —
  /// see [_otherBleedDates]'s fail-open rule). Evaluated as the *net*
  /// session change — the composed entry the sheet is leaving behind
  /// (also exactly what a still-debounced flush is about to write)
  /// against the entry the sheet opened with — so a user who reverts
  /// their flow before dismissing earns nothing: the estimates never saw
  /// a change.
  SnackBar? _cycleStartChangeSnackBar() {
    final others = _otherBleedDates;
    if (others == null || _cycleStartSnackBarSuppressed) return null;
    final evaluation = evaluateCycleStartWrite(
      otherBleedDates: others,
      date: widget.date,
      today: widget.today,
      fromFlow: widget.existing?.flow ?? FlowLevel.none,
      toFlow: _composeEntry().flow,
    );
    if (!evaluation.changesCycleStartSet) return null;
    final l10n = AppLocalizations.of(context);
    return SnackBar(
      key: const ValueKey('day-sheet-cycle-start-snackbar'),
      content: Text(
        evaluation.startsCycleAtDate
            ? l10n.daySheetCycleStartSnackbar
            : l10n.daySheetCycleHistorySnackbar,
      ),
      action: SnackBarAction(
        label: l10n.daySheetUndo,
        onPressed: () => unawaited(_undoCycleStartChange(
          repository: widget.repository,
          previous: widget.existing,
          profileId: widget.profileId,
          date: widget.date,
        )),
      ),
    );
  }

  /// Issue #887: restores exactly what the session's cycle-start-changing
  /// write overwrote — the entry the sheet opened with, or a tombstone
  /// through the repository's own delete path when the session created
  /// the day (`overview_panel.dart`'s `_undoLogToday`, #316's pattern, is
  /// the model the issue names). Goes through [DayEntriesRepository]
  /// either way, so sync dirty-marking applies as it would to any edit.
  /// The child observation rows a session may have written (spotting,
  /// graded pain, measurements) are deliberately untouched: none of them
  /// can start a cycle, so the undo's contract is exactly the
  /// cycle-start decision the snackbar disclosed.
  Future<void> _undoCycleStartChange({
    required DayEntriesRepository repository,
    required DayEntry? previous,
    required String profileId,
    required LocalDate date,
  }) async {
    try {
      if (previous == null) {
        await repository.delete(profileId, date);
      } else {
        await repository.save(previous);
      }
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  /// The discard confirmation shown when dismissal is attempted while a
  /// save has failed and the changes are still unsaved (#198). "Keep
  /// editing" returns to the sheet (the inline retry error is still there);
  /// "Discard" deliberately drops the pending changes and closes.
  Future<void> _confirmDiscardWhileFailed() async {
    if (_discardDialogOpen) return;
    _discardDialogOpen = true;
    // Issue #574: resolved once, not on every Text/label below.
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.daySheetDiscardTitle),
        content: const SingleChildScrollView(
          child: Text(
            "The last change couldn't be saved. Discarding removes it from "
            'this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.daySheetKeepEditing),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.daySheetDiscard),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard != true || !mounted) return;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    // Only reachable with `_saveState is DaySheetFailed` (the only state
    // that ever triggers this dialog, via `_onSheetPop`'s `!didPop`
    // branch) — nothing is in flight, so it is always safe to go straight
    // to Idle.
    setState(() {
      _discardUnsaved = true;
      _saveState = const DaySheetIdle();
    });
    // The user just chose to drop unsaved changes — a parting "Saved on
    // this device" acknowledgement would be a lie about this dismissal.
    _offlineAckMessenger = null;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (widget.date.isAfter(widget.today)) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: LLSpace.space5),
        child: Text(AppLocalizations.of(context).daySheetFutureDate),
      );
    } else if (widget.readOnly) {
      body = _readOnlyBody();
    } else {
      body = _editableBody();
    }
    return PopScope(
      // Only the failure-pending state refuses dismissal (#198); a normal
      // autosaved dismissal closes without ceremony.
      canPop: _saveState is! DaySheetFailed || _discardUnsaved,
      onPopInvokedWithResult: _onSheetPop,
      child: _sheetShell(child: body),
    );
  }

  Widget _sheetShell({required Widget child}) {
    // Issue #262: in landscape the 85%-of-height cap leaves ~300dp for four
    // chip categories plus the note field. The content is already scrollable
    // ([_editableBody]'s Flexible + SingleChildScrollView, [_readOnlyBody]'s
    // own scroll view) and the shell already pads by the keyboard inset, so
    // the fix is a taller cap when width exceeds height (92% instead of 85%)
    // plus the shared form max-width so the sheet never stretches full-bleed
    // on a tablet. Verified: landscape-height pump with all chip categories
    // and the note field reachable, and the note field above the keyboard.
    final size = MediaQuery.sizeOf(context);
    final maxHeight =
        size.height * (size.width > size.height ? 0.92 : 0.85);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        // #198 (B-12): pad by the keyboard inset (the pattern already
        // correct in `accept_invite_sheet.dart`/`claim_profile_sheet.dart`)
        // so the sheet's own box shrinks when the keyboard is up — the
        // inner scroll view can then bring the note field into view and
        // the pinned bottom area stays above the keyboard.
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        width: double.infinity,
        child: ResponsiveBody(child: child),
      ),
    );
  }

  /// The flow chip row plus the standalone spotting toggle (issue #247).
  /// Split out of [_editableBody] to keep each method under the CRAP gate.
  /// Every chip re-arms the autosave debounce (#198) — a flow/spotted
  /// change is a change like any other. #138: every chip is wrapped in
  /// [groupedChipSemantics] so it announces its group ("Flow") and its
  /// own label/selected state as one node.
  Widget _flowChips(AppLocalizations l10n) {
    final group = l10n.daySheetFlowLabel;
    return Wrap(
      spacing: LLSpace.space2,
      runSpacing: LLSpace.space1,
      children: [
        for (final level in kSelectableFlowLevels)
          groupedChipSemantics(
            group: group,
            label: localizedFlowLabel(level, l10n),
            selected: _flow == level,
            // Mirrors ChoiceChip's own gesture semantics: re-tapping the
            // already-selected chip is a no-op, not a re-selection.
            onTap: _busy || _flow == level ? null : () => _selectFlow(level),
            child: ChoiceChip(
              label: Text(localizedFlowLabel(level, l10n)),
              selected: _flow == level,
              onSelected: _busy
                  ? null
                  : (selected) {
                      if (selected) unawaited(_selectFlow(level));
                    },
            ),
          ),
        // Issue #247: spotting is its own `observations` category,
        // not a flow level — a standalone toggle rather than one of
        // the flow chips above, so it can coexist with any flow
        // selection (see `_syncSpottingObservation`). #160/#138: the
        // label reads from ARB (same string the deprecated flow level
        // uses) like every other chip here.
        groupedChipSemantics(
          group: group,
          label: l10n.flowLevelSpotting,
          selected: _spotting,
          onTap: _busy ? null : () => _toggleSpotting(!_spotting),
          child: FilterChip(
            key: const ValueKey('spotting-chip'),
            label: Text(l10n.flowLevelSpotting),
            selected: _spotting,
            onSelected: _busy ? null : _toggleSpotting,
          ),
        ),
      ],
    );
  }

  /// Issue #220: the first-class PMS toggle — its own chip *outside* the
  /// flow row's group, mirroring the issue's (and Clue's) separation of
  /// the PMS phase from both the flow levels and the taxonomy chips: a day
  /// can be PMS without any flow at all, and without being tagged for
  /// every symptom present. Rides the entry itself (`DayEntry.pms`), so
  /// unlike spotting it needs no observation-row sync — marking it dirty
  /// is the whole write.
  Widget _pmsChip(AppLocalizations l10n) {
    final group = l10n.daySheetPmsGroup;
    return groupedChipSemantics(
      group: group,
      label: l10n.daySheetPmsChip,
      selected: _pms,
      onTap: _busy ? null : () => _togglePms(!_pms),
      child: FilterChip(
        key: const ValueKey('pms-chip'),
        label: Text(l10n.daySheetPmsChip),
        selected: _pms,
        onSelected: _busy ? null : _togglePms,
      ),
    );
  }

  /// The shared free-text day note plus its disclosure (issue #800/#801),
  /// its own method so [_editableBody] keeps a low CRAP score and so the
  /// order of the sheet's fields is legible in one place (issue #812).
  ///
  /// Issue #812: rendered directly after the searchable taxonomy and ahead of
  /// the two numeric measurement fields (and the rarely-populated
  /// unrecognised/unmapped sections), so a guardian writing an observation
  /// reaches it without first wading through BBT/weight — the issue's stated
  /// minimum. The field grows with its content ([minLines]/[maxLines]) and
  /// carries a hint in the voice guide's register.
  Widget _noteField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: LLSpace.space3),
          child: TextFormField(
            key: const ValueKey('note-field'),
            controller: _noteController,
            focusNode: _noteFocus,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: l10n.daySheetNoteLabel,
              hintText: l10n.daySheetNoteHint,
              alignLabelWithHint: true,
            ),
            minLines: 2,
            maxLines: 6,
            // #165: the note is multiline — the honest keyboard action is
            // "newline" (a "done" action would steal the enter key from note
            // line breaks).
            textInputAction: TextInputAction.newline,
            // Mirrors the server CHECK; a longer note is rejected forever.
            maxLength: kMaxNoteLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
          ),
        ),
        // Issue #800/#801: who can read what a guardian writes is stated at
        // the point of writing, not buried in settings.
        Padding(
          padding: const EdgeInsets.only(top: LLSpace.space1),
          child: Text(
            kCareNotesDisclosure,
            key: const ValueKey('day-note-disclosure'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// Selects [level] as the day's flow — the single write path behind both
  /// the visible ChoiceChip's `onSelected` and the #138 semantics wrapper's
  /// accessibility tap.
  ///
  /// Issue #887: a bleed-level tap that would start a new cycle earlier
  /// than the profile's history expects asks first — disclosure and
  /// consent, never a different model (the engine's episode semantics are
  /// untouched, the same design principle #130 applied to same-date
  /// merges). "Start new cycle" falls through to the ordinary selection
  /// below; "Log spotting instead" records the day as spotting (the
  /// mid-cycle bleed that never starts a cycle); cancel leaves the sheet
  /// exactly as it was. Once a bleed level is selected, further
  /// bleed-level taps don't re-ask — the evaluation compares against the
  /// current selection, so only the transition into a cycle-starting
  /// bleed is a consent decision.
  Future<void> _selectFlow(FlowLevel level) async {
    final guard = _cycleStartGuardFor(level);
    if (guard != null) {
      final choice = await _confirmCycleStartDialog(guard, level);
      if (choice != _CycleStartChoice.startCycle) {
        if (choice == _CycleStartChoice.logSpotting && !_spotting) {
          _toggleSpotting(true);
        }
        return;
      }
    }
    LLHaptics.selection();
    setState(() {
      _flow = level;
      _flowExplicitlySet = true;
    });
    _markDirty();
  }

  /// Issue #887: the surprise evaluation for tapping [level], or null when
  /// no confirmation is due — not surprising, or the bleed history has not
  /// loaded (see [_otherBleedDates]'s fail-open rule). Evaluated against
  /// the *current* in-memory selection as the before-state, so a change
  /// between bleed levels (light → heavy) never re-asks.
  CycleStartWriteEvaluation? _cycleStartGuardFor(FlowLevel level) {
    final others = _otherBleedDates;
    if (others == null) return null;
    final evaluation = evaluateCycleStartWrite(
      otherBleedDates: others,
      date: widget.date,
      today: widget.today,
      fromFlow: _flow,
      toFlow: level,
    );
    return evaluation.startsCycleEarly ? evaluation : null;
  }

  /// Issue #887: the early-cycle-start confirmation. Plain-language: names
  /// the cycle day, what the tap would close and update, and that spotting
  /// — the chip right next to this one, the mis-tap the issue is about —
  /// never starts a cycle.
  Future<_CycleStartChoice> _confirmCycleStartDialog(
    CycleStartWriteEvaluation guard,
    FlowLevel level,
  ) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<_CycleStartChoice>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: const ValueKey('cycle-start-confirm-dialog'),
            title: Text(l10n.daySheetCycleStartDialogTitle),
            content: Text(
              l10n.daySheetCycleStartDialogBody(
                guard.cycleDay ?? 0,
                localizedFlowLabel(level, l10n),
                guard.closedCycleLengthDays ?? 0,
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('cycle-start-cancel'),
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_CycleStartChoice.cancel),
                child: Text(l10n.daySheetCancel),
              ),
              OutlinedButton(
                key: const ValueKey('cycle-start-spotting'),
                onPressed: () => Navigator.of(dialogContext)
                    .pop(_CycleStartChoice.logSpotting),
                child: Text(l10n.daySheetCycleStartSpotting),
              ),
              FilledButton(
                key: const ValueKey('cycle-start-confirm'),
                onPressed: () => Navigator.of(dialogContext)
                    .pop(_CycleStartChoice.startCycle),
                child: Text(l10n.daySheetCycleStartConfirm),
              ),
            ],
          ),
        ) ??
        _CycleStartChoice.cancel;
  }

  /// Sets the standalone spotting toggle (issue #247) — shared by the
  /// visible chip and its semantics tap.
  ///
  /// Issue #889: the in-memory [_flow] is reconciled here through the same
  /// [resolveEffectiveFlow] the autosave path uses, so the Flow chips
  /// render exactly what will be persisted (previously [_flow] stayed
  /// [FlowLevel.none] while the write path raised it, showing both "None
  /// ✓" and "Spotting ✓" and then silently reopening as "Not bleeding").
  /// Turning spotting on over an unlogged day raises the selected chip to
  /// "Not bleeding"; turning it back off returns it to "None" only when
  /// this toggle is what raised it ([_spottingRaisedFlow]) — an explicit
  /// "Not bleeding" (tapped this session or loaded from the store) is left
  /// alone, and a real bleed level is never touched.
  void _toggleSpotting(bool value) {
    LLHaptics.selection();
    setState(() {
      if (value) {
        final before = _flow;
        _flow = resolveEffectiveFlow(
          spotting: true,
          flow: _flow,
          hadSpottingOnLoad: _hadSpottingOnLoad,
          flowExplicitlySet: _flowExplicitlySet,
        );
        // Only a genuine raise from "nothing logged" is this toggle's to
        // undo; a flow that was already notBleeding stays an assertion.
        if (before == FlowLevel.none) {
          _spottingRaisedFlow = _flow != FlowLevel.none;
        }
      } else {
        _flow = resolveEffectiveFlow(
          spotting: false,
          flow: _flow,
          hadSpottingOnLoad: _hadSpottingOnLoad || _spottingRaisedFlow,
          flowExplicitlySet: _flowExplicitlySet,
        );
        _spottingRaisedFlow = false;
      }
      _spotting = value;
    });
    _markDirty();
  }

  /// Sets the first-class PMS toggle (issue #220) — shared by the visible
  /// chip and its semantics tap. The marker rides the entry itself, so
  /// this is exactly like any other content change: state, then dirty.
  void _togglePms(bool value) {
    LLHaptics.selection();
    setState(() => _pms = value);
    _markDirty();
  }

  /// Adds or removes [code] from the taxonomy grid — shared by the visible
  /// chip and its semantics tap (#138). Issue #253: adding a code whose
  /// category is single-select ([kSingleSelectTagCategories]) first removes
  /// the day's other selected codes of that same category, so the picker
  /// never holds two discharge options at once.
  void _toggleTag(String code) {
    LLHaptics.selection();
    final tag = tagByCode(code);
    final singleSelect =
        tag != null && kSingleSelectTagCategories.contains(tag.category);
    var added = false;
    setState(() {
      if (_tags.contains(code)) {
        _tags.remove(code);
        _sessionSelectedTags.remove(code);
      } else {
        if (singleSelect) {
          final others = [
            for (final existing in _tags)
              if (tagByCode(existing)?.category == tag.category) existing,
          ];
          for (final other in others) {
            _tags.remove(other);
            _sessionSelectedTags.remove(other);
          }
        }
        _tags.add(code);
        _sessionSelectedTags.add(code);
        added = true;
      }
    });
    _markDirty();
    // Issue #234: a pick (never a removal) is what "recently used" means —
    // deselecting a tag says nothing about it being a good future shortcut.
    if (added) _recordTagRecentUse(code);
  }

  /// Issue #257: opens the custom-tag manager sheet (create / rename /
  /// retire) over the profile's registry. Cached repository (never a
  /// fresh `Provider.of` — the sheet may be mid-dismissal), the exact
  /// [_observationsRepository] caching rule.
  Future<void> _manageCustomTags() async {
    final repository = _tagRegistry;
    if (repository == null) return;
    await showCustomTagManagerSheet(
      context,
      repository: repository,
      profileId: widget.profileId,
    );
  }

  /// Issue #234: optimistically moves [code] to the front of this
  /// profile's Recent row (immediate UI feedback via
  /// [withRecordedTagUse]), then persists the change through the
  /// device-local [TagRecentsStore] — best-effort, never syncing and never
  /// affecting the day entry's own autosave (see that store's own doc for
  /// the persistence posture).
  void _recordTagRecentUse(String code) {
    setState(() => _tagRecents = withRecordedTagUse(_tagRecents, code));
    unawaited(_persistTagRecentUse(code));
  }

  Future<void> _persistTagRecentUse(String code) async {
    final settings = Provider.of<SettingsStore?>(context, listen: false);
    if (settings == null) return;
    try {
      await TagRecentsStore(settings).recordUse(widget.profileId, code);
    } catch (error, stackTrace) {
      // Best-effort UX convenience: a failed write here must never surface
      // as a save error or block logging, only silently lose this pick's
      // contribution to the shortlist.
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  /// Issue #234: seeds [_tagRecents] once per sheet session from the
  /// device-local store. Best-effort, matching every other local-only read
  /// in this file — a failure leaves the Recent row simply empty rather
  /// than surfacing an error.
  Future<void> _loadTagRecents() async {
    final settings = Provider.of<SettingsStore?>(context, listen: false);
    if (settings == null) return;
    try {
      final recents = await TagRecentsStore(settings).load(widget.profileId);
      if (!mounted) return;
      setState(() => _tagRecents = recents);
    } catch (error, stackTrace) {
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    }
  }

  /// Issue #256: records [code]'s intensity choice ([value], or `null` to
  /// clear) and marks the sheet dirty — the observation-row write itself
  /// rides the autosave via [_syncPainIntensityObservations], exactly like
  /// the spotting toggle.
  void _setPainIntensity(String code, int? value) {
    LLHaptics.selection();
    setState(() => _painIntensity[code] = value);
    _markDirty();
  }

  /// The pain codes needing an intensity selector row right now: every
  /// taxonomy pain code whose chip is selected, plus every code already
  /// carrying an intensity state this session (a loaded/imported grade).
  /// Taxonomy order, pain-first per #249's settled ordering.
  Iterable<TagCode> get _painIntensitySelectors sync* {
    for (final tag in kTagTaxonomy) {
      if (tag.category == TagCategory.pain &&
          (_tags.contains(tag.code) || _painIntensity.containsKey(tag.code))) {
        yield tag;
      }
    }
  }

  /// One graded 1-5 intensity selector row for [tag] (issue #256): five
  /// choice chips plus a Clear affordance, wrapped in the same #138
  /// semantics pattern as every other chip group here. The chosen value
  /// lives on the code's `observations` row (`observations.intensity`,
  /// #240's schema) — the field the server's high-severity caregiver alert
  /// reads (`intensity >= 4`, issue #256). Clear leaves the row ungraded:
  /// "no severity recorded", never "low".
  Widget _painIntensityRow(
    AppLocalizations l10n,
    ThemeData theme,
    TagCode tag,
  ) {
    final group = l10n.daySheetIntensityGroup;
    final current = _painIntensity[tag.code];
    return Padding(
      padding: const EdgeInsets.only(top: LLSpace.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: LLSpace.space3),
              child: Text(
                tag.display,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            // Issue #234: the reusable graded-intensity control
            // (`lib/ui/components/intensity_selector.dart`) over the same
            // 1-5 `_painIntensity` state — same keys
            // (`pain-intensity-<code>-<level>`/`-clear` via [keyPrefix]),
            // same semantics text, same busy-guard, so this swap changes
            // no observable behaviour, only where the chip row is defined.
            child: IntensitySelector(
              groupLabel: group,
              itemLabel: tag.display,
              value: current,
              enabled: !_busy,
              clearLabel: l10n.daySheetIntensityClear,
              keyPrefix: 'pain-intensity-${tag.code}',
              onChanged: (value) => _setPainIntensity(tag.code, value),
            ),
          ),
        ],
      ),
    );
  }

  /// A section heading for the editable sheet (#138): flagged
  /// [Semantics.header] so screen readers offer heading navigation between
  /// the chip groups. Issue #812: `titleSmall` (14/20 w500) — one step above
  /// the `labelMedium`/12 chip labels it introduces, so the heading outranks
  /// the content it labels instead of being the smallest text on the sheet.
  Widget _sectionHeading(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.only(top: LLSpace.space4, bottom: LLSpace.space1),
    child: Semantics(
      header: true,
      child: Text(label, style: theme.textTheme.titleSmall),
    ),
  );

  /// Issue #457: one numeric measurement field (BBT or weight) plus its
  /// inline validation error and "exclude from charts" toggle — factored
  /// out of [_editableBody] since it is rendered twice with only the
  /// field-specific pieces differing (keeps [_editableBody]'s own CRAP
  /// score low, the same reason [_painIntensityRow] is its own method).
  /// The exclude toggle only renders once [value] is non-null — excluding
  /// is meaningless with nothing logged to exclude — and mirrors
  /// `CycleHistorySection`'s own Omit/Include text-button pair rather than
  /// a checkbox, for the same "a short, explicit verb reads better than an
  /// unlabelled box" reason.
  Widget _measurementField({
    required ThemeData theme,
    required AppLocalizations l10n,
    required String groupLabel,
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required String? error,
    required double? value,
    required bool excluded,
    required VoidCallback onToggleExcluded,
    required Key excludeKey,
    required Key errorKey,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    final excludeLabel = excluded
        ? l10n.daySheetMeasurementIncludeLabel
        : l10n.daySheetMeasurementExcludeLabel;
    return Padding(
      padding: const EdgeInsets.only(top: LLSpace.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  label: '$groupLabel: $label',
                  excludeSemantics: true,
                  child: TextFormField(
                    key: fieldKey,
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: textInputAction,
                    onFieldSubmitted: onFieldSubmitted,
                    decoration: InputDecoration(labelText: label),
                  ),
                ),
              ),
              if (value != null)
                groupedChipSemantics(
                  group: groupLabel,
                  label: excludeLabel,
                  selected: excluded,
                  onTap: _busy ? null : onToggleExcluded,
                  child: TextButton(
                    key: excludeKey,
                    onPressed: _busy ? null : onToggleExcluded,
                    child: Text(excludeLabel),
                  ),
                ),
            ],
          ),
          if (error != null) InlineError(key: errorKey, message: error),
        ],
      ),
    );
  }

  /// The sheet's date header row (issue #763): the human-readable title
  /// plus the attribution badge, shared by the editable body (pinned above
  /// its scroll view) and the read-only body. Split out of [_editableBody]
  /// so both bodies — and the [SheetDragHeader] wrapping them — read one
  /// definition, keeping each method under the CRAP gate.
  ///
  /// [date] is the title's date: the editable body passes `widget.date`
  /// while the read-only body passes its entry's own date (the same day in
  /// practice, but the read-only path historically rendered the entry's).
  Widget _sheetHeaderRow(ThemeData theme, LocalDate date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LLSpace.space2),
      // A Wrap, not a Row (#198): the human-readable title is
      // wider than the raw ISO string it replaced, and a long
      // attribution badge beside it would overflow horizontally
      // — the badge flows to a second line instead.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // #138: flagged as a heading so the sheet's date is
          // reachable through screen-reader heading navigation. Issue #812:
          // `titleLarge` (22/28 w500) — the sheet's own title now outranks
          // the `titleSmall` section headings.
          Semantics(
            header: true,
            child: Text(
              key: const ValueKey('day-sheet-date-title'),
              daySheetDateLabel(
                date,
                widget.today,
                locale: dates.calendarLocale(context),
                preference: _dateFormat,
              ),
              style: theme.textTheme.titleLarge,
            ),
          ),
          if (widget.existing != null)
            CaregiverAttributionBadge(
              loggedByUserId: widget.existing!.loggedByUserId,
              lastModifiedByUserId: widget.existing!.lastModifiedByUserId,
              currentUserId: widget.currentUserId,
              guardians: widget.guardians,
              source: widget.existing!.source.toDb(),
            ),
        ],
      ),
    );
  }

  Widget _editableBody() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Issue #763: the date header is pinned chrome above the scroll
        // view (not its first child) and wrapped in [SheetDragHeader], so
        // a downward drag started on it dismisses the sheet instead of
        // being eaten by the scrollable — previously only the ~24px drag
        // handle did. Chips, fields, and the scroll content itself are
        // untouched, so their gestures keep working as before.
        SheetDragHeader(
          key: const ValueKey('day-sheet-drag-header'),
          child: _sheetHeaderRow(theme, widget.date),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Issue #130: the quiet, dismissible same-date merge notice
                // — shown to every guardian (the winner too), with the
                // losing author's recovery affordance rendered inside.
                DayEntryMergeNoticeSection(
                  events: _mergeEvents,
                  currentUserId: widget.currentUserId,
                  guardians: widget.guardians,
                  onDismiss: (event) => unawaited(_dismissMergeEvent(event)),
                  onRestoreNote: _restoreMergedNote,
                  onRestoreFlow: _restoreMergedFlow,
                ),
                _sectionHeading(theme, l10n.daySheetFlowLabel),
                _flowChips(l10n),
                // Issue #220: the first-class PMS toggle sits between the
                // flow row and the taxonomy grid — it belongs to neither.
                _pmsChip(l10n),
                // Issue #259: the profile's curated categories and order
                // (resolved above) replace the mode's default list; an
                // entry's already-logged tags for a disabled category stay
                // in [_tags] and round-trip through autosave untouched
                // (AC3) — they are simply not rendered here. Issue #234:
                // the previous per-category heading+Wrap loop (still the
                // shape read-only/other consumers never touch) is now
                // `CategoryPicker` — search, a Recent row, and collapsible
                // sections over the same [_categoriesInOrder] and the same
                // [_toggleTag]/[kUnverifiedTagCategories] rules.
                CategoryPicker(
                  categories: _categoriesInOrder,
                  categoryLabel: _copy.categoryLabel,
                  selected: _tags,
                  onToggle: _toggleTag,
                  recentCodes: _tagRecents,
                  enabled: !_busy,
                  searchHint: l10n.daySheetTagSearchHint,
                  searchSemanticsLabel: l10n.daySheetTagSearchSemanticsLabel,
                  clearSearchTooltip: l10n.daySheetTagSearchClearTooltip,
                  recentLabel: l10n.daySheetTagRecentLabel,
                  unverifiedNote: l10n.daySheetUnverifiedPin,
                  // Issue #256: the pain category's graded intensity
                  // selectors — one row per pain code that is either
                  // chip-selected or already carries an intensity for the
                  // day (so an existing/imported grade stays visible and
                  // editable even if the code's day-entry tag is not
                  // selected). AC: "at least the pain category exposes a
                  // graded intensity input in the day sheet"; the reusable
                  // IntensitySelector component is issue #234.
                  trailingBuilder: (category) => category == TagCategory.pain
                      ? [
                          for (final tag in _painIntensitySelectors)
                            _painIntensityRow(l10n, theme, tag),
                        ]
                      : const [],
                  // Issue #257: the profile's custom-tag registry — one
                  // collapsible section after every curated category,
                  // offering the LIVE, non-retired entries (retired tags
                  // never render here; their stored codes render as inert
                  // chips by display name instead). The manage affordance
                  // is present whenever a registry repository is in scope,
                  // so the first tag can be created from the sheet itself.
                  customTags: [
                    for (final tag in _registry)
                      if (tag.offered) (code: tag.code, label: tag.displayName),
                  ],
                  customLabel: l10n.daySheetCustomTagsLabel,
                  customManageTooltip: l10n.daySheetCustomTagsManageTooltip,
                  noneCustomNote: l10n.daySheetCustomTagsNone,
                  onManageCustomTags:
                      _tagRegistry == null ? null : _manageCustomTags,
                ),
                // Issue #812: the shared note now sits directly after the
                // taxonomy and ahead of the two numeric measurement fields —
                // the issue's own stated minimum. The taxonomy stays directly
                // under Flow (the primary logging surface, and a position the
                // existing chip-tap tests pin), so the note is not pushed
                // above it; a guardian gets to the note as soon as the tags
                // are done rather than at the very bottom of the sheet.
                _noteField(l10n),
                // Issue #457: BBT/weight, standalone like the PMS toggle —
                // neither is a `TagCategory` (they are numeric, not
                // chip-selected options), so this section sits outside the
                // curated-categories loop above rather than inside it.
                _sectionHeading(theme, l10n.daySheetMeasurementsHeading),
                _measurementField(
                  theme: theme,
                  l10n: l10n,
                  groupLabel: l10n.daySheetBbtGroup,
                  fieldKey: const ValueKey('bbt-field'),
                  controller: _bbtController,
                  label: l10n.daySheetBbtFieldLabel(bbtUnitSymbol(widget.bbtUnit)),
                  error: _bbtError,
                  value: _bbtValue,
                  excluded: _bbtExcluded,
                  onToggleExcluded: _toggleBbtExcluded,
                  excludeKey: const ValueKey('bbt-exclude-toggle'),
                  errorKey: const ValueKey('bbt-error'),
                  // #165: BBT → weight → note is the keyboard focus order
                  // (`forms_a11y_test` pins it). Issue #812 moved the note's
                  // visual position ahead of these fields; the next-key chain
                  // itself is deliberately unchanged.
                  focusNode: _bbtFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _weightFocus.requestFocus(),
                ),
                _measurementField(
                  theme: theme,
                  l10n: l10n,
                  groupLabel: l10n.daySheetWeightGroup,
                  fieldKey: const ValueKey('weight-field'),
                  controller: _weightController,
                  label: l10n.daySheetWeightFieldLabel(
                    weightUnitSymbol(widget.weightUnit),
                  ),
                  error: _weightError,
                  value: _weightValue,
                  excluded: _weightExcluded,
                  onToggleExcluded: _toggleWeightExcluded,
                  excludeKey: const ValueKey('weight-exclude-toggle'),
                  errorKey: const ValueKey('weight-error'),
                  focusNode: _weightFocus,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                ),
                if (_inertTags.isNotEmpty)
                  ..._unrecognisedTagsSection(theme),
                if (_unmappedObservations.isNotEmpty)
                  ..._unmappedObservationsSection(theme),
                // Issue #801: the per-guardian dated notes, beside the shared
                // day note — never a rework of it.
                // Issue #872: only when the profile actually has guardians to
                // share with. A signed-out, guardian-less local profile used
                // to render this section's second note box and a near-identical
                // disclosure, even though there is no guardian, no one else
                // with access, and no actionable difference — such a profile
                // keeps exactly the one shared "Note" box it has always had.
                if (!widget.readOnly &&
                    widget.currentUserId != null &&
                    widget.guardians.isNotEmpty)
                  GuardianNotesSection(
                    profileId: widget.profileId,
                    date: widget.date,
                    tz: (widget.timezoneProvider ??
                        resolveCurrentTimeZoneSync)(),
                    currentUserId: widget.currentUserId,
                    guardians: widget.guardians,
                    canWrite: _guardianNotesCanWrite,
                  ),
              ],
            ),
          ),
        ),
        _pinnedBottomArea(theme),
      ],
    );
  }

  /// The persistent bottom area inside the sheet (#198): the delete
  /// affordance, the autosave status, and the affirmative Done control
  /// (plus the save/delete retry errors) sit here, below the scroll view, so
  /// they stay on screen no matter how many chip categories are expanded —
  /// and above the keyboard, thanks to the shell's view-inset padding.
  ///
  /// Issue #812: [Done] gives the interaction an end. It is a dismissal, not
  /// a save — autosave already persisted the edit — so it simply pops the
  /// sheet, exactly like the scrim, the back gesture, or the drag handle;
  /// `PopScope`'s `_onSheetPop` still flushes any debounced change and still
  /// refuses to close a failed-pending sheet without an explicit discard.
  /// Issue #923: the save-failure banner's copy. A date-bounds rejection
  /// names the actual cause (and, for a pre-birth-year date, points at the
  /// profile setting that fixes it) instead of the generic "Couldn't save —
  /// try again"; only a genuine bug/transient failure keeps the generic
  /// copy. Reads [_saveErrorClass], set by [_writePending] from the typed
  /// exception, never from a message string.
  String _saveErrorMessage(AppLocalizations l10n) {
    switch (_saveErrorClass) {
      case DaySheetWriteErrorClass.futureDate:
        return l10n.daySheetSaveErrorFutureDate;
      case DaySheetWriteErrorClass.beforeBirthYear:
        return l10n.daySheetSaveErrorBeforeBirthYear;
      case null:
      case DaySheetWriteErrorClass.bug:
        return l10n.daySheetSaveError;
    }
  }

  Widget _pinnedBottomArea(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saveState is DaySheetFailed)
          InlineError(
            key: const ValueKey('save-error'),
            message: _saveErrorMessage(l10n),
            onRetry: _performAutosave,
          ),
        if (_deleteFailed)
          InlineError(
            key: const ValueKey('delete-error'),
            message: l10n.daySheetDeleteError,
            onRetry: _delete,
          ),
        Padding(
          padding: const EdgeInsets.only(top: LLSpace.space2),
          child: Row(
            children: [
              if (widget.existing != null)
                IconButton(
                  tooltip: l10n.daySheetDeleteTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : _delete,
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _autosaveStatusSlot(theme),
                ),
              ),
              const SizedBox(width: LLSpace.space2),
              ConstrainedBox(
                // Issue #812 + #460: an expanded/translated label must never
                // overflow the pinned bar (the RTL + pseudo-locale smoke
                // expands every message), so the affirmative control is
                // capped and ellipsized rather than forcing the row wider
                // than the sheet.
                constraints: const BoxConstraints(maxWidth: 240),
                child: FilledButton.tonal(
                  key: const ValueKey('day-sheet-done'),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.daySheetDoneLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The autosave status slot (#198). Always present (keyed) in the
  /// editable sheet — the read-only variant never builds it — showing
  /// "Saving…" while a write is in flight, a transient "Saved" after one
  /// succeeds, and nothing when idle.
  Widget _autosaveStatusSlot(ThemeData theme) {
    final Widget content;
    if (_saveState is DaySheetSaving) {
      content = Row(
        key: const ValueKey('autosave-saving'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: LLSpace.space2),
          Text(
            AppLocalizations.of(context).daySheetSaving,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    } else if (_saveState is DaySheetSaved) {
      content = Row(
        key: const ValueKey('autosave-saved'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: LLSpace.space1),
          Text(
            AppLocalizations.of(context).daySheetSaved,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    } else {
      content = const SizedBox.shrink(key: ValueKey('autosave-idle'));
    }
    // Issue #809: saving/saved/idle cross-fade in and out rather than
    // popping. The "Saved" confirmation in particular fades away through
    // the outgoing FadeTransition when its timer expires, instead of
    // vanishing; the outer 'autosave-status' key stays put so the slot's
    // widget-test lookup is unchanged.
    return Semantics(
      liveRegion: true,
      child: KeyedSubtree(
        key: const ValueKey('autosave-status'),
        child: AnimatedSwitcher(
          duration: LLMotion.resolve(context, LLMotion.fast),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: content,
        ),
      ),
    );
  }

  /// Issue #257: the inert subset of [_unrecognisedTags] that actually
  /// renders as inert chips — stored codes this build's taxonomy does not
  /// know AND the registry does not offer. An offered registry code
  /// renders as a selectable chip in the picker's custom-tags section; a
  /// RETIRED registry code stays here (it has no picker chip — retirement
  /// removed it) and renders by display name via [_displayOf], so its
  /// stored rows keep rendering (#257's retire-not-delete rule).
  List<String> get _inertTags => [
        for (final code in _unrecognisedTags)
          if (!_registry.any((tag) => tag.offered && tag.code == code)) code,
      ];

  /// Inert, visible chips for [_inertTags] (#237, extended by #257):
  /// unlike the taxonomy [FilterChip] grid above, these carry no
  /// `onSelected` — they cannot be toggled, only shown — so they
  /// round-trip through `_tags` (and therefore through autosave)
  /// unchanged rather than being silently dropped or invisibly
  /// resubmitted as if user-validated. #257: a retired custom tag's chip
  /// shows its display name ([_displayOf]); a wholly unknown code (never
  /// in the taxonomy, not in — or not yet synced to — this device's
  /// registry copy) shows its raw code, never drops (#237).
  /// Issue #199: loads the day's escape-hatch rows — `observations` with
  /// a non-null `raw` (an imported-but-unrecognised Clue datapoint) — so
  /// the sheet can render them as readable text instead of leaving them
  /// invisible. Read-only: nothing here writes, autosaves, or synthesises.
  Future<void> _loadUnmappedObservations(String dayEntryId) async {
    final rows = [
      for (final o in await Provider.of<ObservationsRepository>(
        context,
        listen: false,
      ).listForDayEntry(dayEntryId))
        if (o.raw != null) o,
    ];
    if (!mounted) return;
    setState(() {
      _unmappedObservations = rows;
    });
  }

  /// Inert, visible chips for [_unmappedObservations] (Issue #199): each
  /// escape-hatch row renders as one readable line ([describeUnmappedRaw]),
  /// never raw JSON and never nothing. A stored `raw` that is not JSON at
  /// all (possible — storage bounds the string but does not parse it)
  /// degrades to the same fallback copy `describeUnmappedRaw` uses for an
  /// empty map, so rendering never throws on the very rows it exists to
  /// make visible.
  ///
  /// Its own heading, not [_unrecognisedTagsSection]'s: that one names tag
  /// *codes* this build does not recognise, this one names imported
  /// datapoints that mapped to no field at all. Sharing a heading would
  /// stack two differently-sourced "Unrecognised" lists back to back.
  List<Widget> _unmappedObservationsSection(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(
        top: LLSpace.space3,
        bottom: LLSpace.space1,
      ),
      child: Text(
        AppLocalizations.of(context).daySheetUnmappedImported,
        style: theme.textTheme.labelMedium,
      ),
    ),
    Wrap(
      spacing: LLSpace.space2,
      runSpacing: LLSpace.space1,
      children: [
        for (var i = 0; i < _unmappedObservations.length; i++)
          Chip(
            key: ValueKey('unmapped-observation-$i'),
            label: Text(_describeUnmapped(_unmappedObservations[i].raw)),
          ),
      ],
    ),
  ];

  String _describeUnmapped(String? raw) {
    final fallback = AppLocalizations.of(context).daySheetUnmappedFallback;
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return describeUnmappedRaw(Map<String, Object?>.from(decoded));
      }
      return fallback;
    } on FormatException {
      return fallback;
    }
  }

  List<Widget> _unrecognisedTagsSection(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: LLSpace.space3, bottom: LLSpace.space1),
      child: Text(
        AppLocalizations.of(context).daySheetUnrecognised,
        style: theme.textTheme.labelMedium,
      ),
    ),
    Wrap(
      spacing: LLSpace.space2,
      runSpacing: LLSpace.space1,
      children: [
        for (final code in _inertTags)
          Chip(key: ValueKey('unrecognised-tag-$code'), label: Text(_displayOf(code))),
      ],
    ),
  ];

  /// R13 copy: when the caller's own accepted role is the reason this sheet
  /// is read-only (not an archived profile - the two reasons are additive,
  /// R14), name that reason explicitly so a viewer session is never
  /// mistaken for an archive. Derived from the same `guardians`/
  /// `currentUserId` data already passed in for the attribution badge, per
  /// [acceptedGuardianFor]'s null-vs-empty discipline - an unmatched or
  /// unknown caller has no reason to show here.
  String? get _readOnlyReason {
    final role = acceptedGuardianFor(
      widget.guardians,
      widget.currentUserId,
    )?.role;
    return role == null
        ? null
        : guardianRoleReadOnlyReason(AppLocalizations.of(context), role);
  }

  /// Issue #801: whether the caller may write a guardian note. Reuses the
  /// same role-derivation seam as [_readOnlyReason] rather than duplicating
  /// any gate logic: the day_entries/observations/care-notes ladder — any
  /// accepted guardian except a viewer. A caller with no matched role (a
  /// local-only operator, or a test with no guardians list) defaults to the
  /// sheet's own [DaySheet.readOnly] flag.
  bool get _guardianNotesCanWrite {
    if (widget.readOnly) return false;
    return acceptedGuardianFor(widget.guardians, widget.currentUserId)
            ?.role
            .canLog ??
        true;
  }

  /// Issue #642, LLA-012: bounded via [SingleChildScrollView] — before this
  /// fix, a long note, several tag chips, or (once LLA-011 lands alongside
  /// this) spotting/graded-pain-intensity lines could exceed
  /// [_sheetShell]'s `maxHeight` with nothing to scroll, overflowing off
  /// the bottom of a small or heavily text-scaled screen. Mirrors the
  /// editable body's own `SingleChildScrollView` (`_editableBody`). A
  /// `SingleChildScrollView` shrink-wraps to its child's actual height when
  /// that height already fits, so a short read-only day (little or no
  /// content) renders exactly as tall as before this fix — it only starts
  /// scrolling once content would otherwise overflow. Issue #763: the date
  /// header is now pinned above this scroll view (inside a
  /// [SheetDragHeader]), which is why the scroll view is wrapped in a
  /// [Flexible]/[Column] the way [_editableBody]'s already was.
  Widget _readOnlyBody() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final reason = _readOnlyReason;
    final existing = widget.existing;
    if (existing == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LLSpace.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reason != null) ...[
                Text(reason, style: theme.textTheme.bodyMedium),
                const SizedBox(height: LLSpace.space1),
              ],
              Text(
                AppLocalizations.of(context).daySheetNoEntry,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Issue #763: same pinned-header treatment as the editable body —
        // the date header (with the read-only reason above it) sits
        // outside the scroll view inside [SheetDragHeader], so a downward
        // drag started on it dismisses the sheet instead of scrolling.
        SheetDragHeader(
          key: const ValueKey('day-sheet-drag-header'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reason != null) ...[
                Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: LLSpace.space2),
              ],
              _sheetHeaderRow(theme, existing.localDate),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: LLSpace.space3),
                Text(
                  AppLocalizations.of(context).daySheetFlowLabel,
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  localizedFlowLabel(existing.flow, l10n),
                  style: theme.textTheme.titleSmall,
                ),
                // Issue #220: the read-only view names the PMS marker too,
                // so a viewer (or a reviewing guardian) sees the phase even
                // though the toggle itself is disabled here.
                if (existing.pms) ...[
                  const SizedBox(height: LLSpace.space3),
                  Text(
                    l10n.daySheetPmsGroup,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(l10n.daySheetPmsChip, style: theme.textTheme.titleSmall),
                ],
                // Issue #642, LLA-011.
                ..._readOnlyChildObservationsSection(theme, l10n),
                if (existing.tags.isNotEmpty) ...[
                  const SizedBox(height: LLSpace.space3),
                  Text(
                    AppLocalizations.of(context).daySheetTagsLabel,
                    style: theme.textTheme.labelMedium,
                  ),
                  Wrap(
                    spacing: LLSpace.space2,
                    runSpacing: LLSpace.space1,
                    children: [
                      for (final code in existing.tags)
                        // Issue #257: registry-aware resolution — a custom
                        // tag's display name where available (retired tags
                        // included), the raw code otherwise (never dropped,
                        // #237).
                        Chip(
                          key: ValueKey('read-only-tag-$code'),
                          label: Text(_displayOf(code)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: LLSpace.space3),
                Text(
                  AppLocalizations.of(context).daySheetNoteLabel,
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  (existing.note == null || existing.note!.isEmpty)
                      ? AppLocalizations.of(context).daySheetNoNote
                      : existing.note!,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Issue #642, LLA-011: the read-only body's own rendering of spotting
  /// and graded pain intensity — both child `observations` rows the
  /// pre-#642 view silently omitted (it only ever read fields on the
  /// [DayEntry] itself), so a spotting-only day read as "not bleeding" to
  /// a viewer or an archived owner, and a caregiver-alert-worthy pain
  /// grade (`intensity >= 4`) was invisible to them too. Split out of
  /// [_readOnlyBody] to keep that method under the CRAP gate, mirroring
  /// this file's other `_readOnlyBody`-adjacent split points.
  ///
  /// Loading/error semantics: a small progress row while
  /// [_childObservationsLoading] (both loaders — [_loadExistingSpotting],
  /// [_loadExistingPainIntensity] — always run together, see [initState]),
  /// failure copy on [_childObservationsLoadFailed], otherwise the
  /// spotting marker (if set) and one line per graded pain code — reusing
  /// [_spotting]/[_painIntensity], the same state fields the editable
  /// chips below read, since both loaders run unconditionally whenever
  /// [DaySheet.existing] is non-null (editable or read-only alike).
  List<Widget> _readOnlyChildObservationsSection(
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (_childObservationsLoading) {
      return [
        const SizedBox(height: LLSpace.space3),
        Row(
          key: const ValueKey('day-sheet-child-observations-loading'),
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: LLSpace.space2),
            // Issue #642, LLA-012: `Flexible`, not a bare `Text` (which
            // would leave the `Row` unbounded) — this copy is long enough
            // that 200% text scaling on a 320dp-wide screen overflows the
            // row horizontally without it; the row is short-lived (only
            // shown until both child-observation loaders settle) but a
            // transient frame can still overflow and fail a test/trip
            // `FlutterError.onError` in production.
            Flexible(
              child: Text(
                l10n.daySheetChildObservationsLoading,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ];
    }
    if (_childObservationsLoadFailed) {
      // Issue #555 guard: a retryable in-place failure renders InlineError
      // (the only widget that wraps its message in `Semantics(liveRegion:
      // true, ...)`), never a bare red `Text` — no `onRetry` here since
      // there is no isolated retry affordance for just this section; the
      // operator's own next visit to this day re-attempts the load.
      return [
        const SizedBox(height: LLSpace.space3),
        InlineError(
          key: const ValueKey('day-sheet-child-observations-error'),
          message: l10n.daySheetChildObservationsError,
        ),
      ];
    }
    final gradedPain = [
      for (final entry in _painIntensity.entries)
        if (entry.value != null) (code: entry.key, level: entry.value!),
    ];
    return [
      if (_spotting) ...[
        const SizedBox(height: LLSpace.space3),
        Text(l10n.daySheetSpottingGroup, style: theme.textTheme.labelMedium),
        Text(
          l10n.flowLevelSpotting,
          key: const ValueKey('day-sheet-spotting-value'),
          style: theme.textTheme.titleSmall,
        ),
      ],
      if (gradedPain.isNotEmpty) ...[
        const SizedBox(height: LLSpace.space3),
        Text(l10n.daySheetIntensityGroup, style: theme.textTheme.labelMedium),
        for (final row in gradedPain)
          Text(
            '${tagByCode(row.code)?.display ?? row.code}: ${row.level}',
            key: ValueKey('day-sheet-pain-intensity-${row.code}'),
            style: theme.textTheme.titleSmall,
          ),
      ],
      // Issue #457: BBT/weight, read-only — seeded by
      // `_loadExistingMeasurements` exactly like the editable sheet (that
      // load is unconditional on `existing != null`, not gated on
      // `widget.readOnly`), so a viewer or an archived profile still sees
      // whatever was logged, just with no field to edit it through. Rendered
      // alongside spotting/pain above rather than gated on
      // [_childObservationsLoading]/[_childObservationsLoadFailed] (issue
      // #642, LLA-011): those loaders cover exactly [_loadExistingSpotting]/
      // [_loadExistingPainIntensity], and folding a third, independent
      // async load (`_loadExistingMeasurements`) into that same
      // loading/error gate is a bigger behavioural change than this method
      // needs to make room for BBT/weight — the same transient-omission
      // risk the LLA-011 fix closed for spotting/pain remains open for
      // BBT/weight specifically, tracked as a follow-up rather than
      // silently absorbed into this conflict resolution.
      if (_bbtValue != null) ...[
        const SizedBox(height: LLSpace.space3),
        _readOnlyMeasurementRow(
          theme,
          label: l10n.daySheetBbtFieldLabel(bbtUnitSymbol(widget.bbtUnit)),
          value: _bbtValue!,
          excluded: _bbtExcluded,
          l10n: l10n,
        ),
      ],
      if (_weightValue != null) ...[
        const SizedBox(height: LLSpace.space3),
        _readOnlyMeasurementRow(
          theme,
          label: l10n.daySheetWeightFieldLabel(
            weightUnitSymbol(widget.weightUnit),
          ),
          value: _weightValue!,
          excluded: _weightExcluded,
          l10n: l10n,
        ),
      ],
    ];
  }

  /// One read-only measurement row (Issue #457): label, formatted value,
  /// and — when the reading was excluded — a small "(excluded from
  /// charts)" caption, mirroring `CycleHistorySection`'s own "Excluded from
  /// averages" subtitle treatment for an omitted cycle.
  Widget _readOnlyMeasurementRow(
    ThemeData theme, {
    required String label,
    required double value,
    required bool excluded,
    required AppLocalizations l10n,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(formatMeasurementValue(value), style: theme.textTheme.titleSmall),
        if (excluded)
          Text(
            l10n.daySheetMeasurementExcludeLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Issue #887: the outcome of the early-cycle-start confirmation dialog
/// ([_DaySheetState._confirmCycleStartDialog]). Barrier dismissal (a tap
/// outside the dialog) reads as [cancel] — the sheet keeps exactly what
/// it had, which is the same consent posture as the explicit cancel
/// button.
enum _CycleStartChoice { startCycle, logSpotting, cancel }
