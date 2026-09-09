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
/// Route naming (U2 Approach 2b): the sheet itself is named
/// `DaySheetScreen` at its push site (`month_calendar.dart`). Its internal
/// "Delete this entry?" / "Discard unsaved changes?" `showDialog`s are
/// deliberately left unnamed — trivial confirm/cancel choices, not distinct
/// destinations.
library;

import 'dart:async' show Timer, scheduleMicrotask, unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart'
    show kOfflineSaveConfirmationCopy, shouldConfirmOfflineSave;
import 'package:provider/provider.dart';

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';

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
String daySheetDateLabel(LocalDate date, LocalDate today) {
  // Thin bridge onto #160's shared helper: LocalDate -> civil DateTime.
  DateTime civil(LocalDate d) => DateTime(d.year, d.month, d.day);
  return dates.relativeDayLabel(civil(date), civil(today));
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
    this.readOnly = false,
    this.timezoneProvider,
    this.currentUserId,
    this.guardians = const [],
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
  final bool readOnly;

  /// Provider for the resolved IANA time zone identifier (paired with #38).
  /// Defaults to [resolveCurrentTimeZone] if not specified.
  final String Function()? timezoneProvider;

  final String? currentUserId;
  final List<ProfileGuardian> guardians;

  @override
  State<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<DaySheet> {
  late FlowLevel _flow;
  late final Set<String> _tags;
  late final TextEditingController _noteController;
  bool _busy = false;
  bool _saveFailed = false;
  bool _deleteFailed = false;

  /// Autosave state (#198): a change is pending ([_dirty]) with its
  /// composed entry ([_pendingEntry]); the debounce timer ([_saveDebounce])
  /// writes it after [kDaySheetAutosaveDelay]. A write in flight sets
  /// [_saving]; its success shows the transient [_showSaved] confirmation,
  /// its failure sets [_saveFailed] and restores [_dirty] (the pending
  /// state is never dropped).
  bool _dirty = false;
  DayEntry? _pendingEntry;
  Timer? _saveDebounce;
  Timer? _savedIndicatorTimer;
  bool _saving = false;
  bool _showSaved = false;

  /// Set when a write was already in flight as another flush arrived; the
  /// running write re-runs the autosave on completion so the newer state is
  /// never dropped (last-writer-wins stays last-*editor*-wins).
  bool _saveQueued = false;

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

  /// The observations repository backing the spotting toggle (#247),
  /// resolved once the sheet is in the tree ([Provider.of] is illegal in
  /// `initState`) and cached so a write started while mounted can finish
  /// its [_syncSpottingObservation] step after the sheet has gone (a
  /// dismissal-time autosave flush outlives its widget — #335's save
  /// skipped the sync in that case; autosave must not silently drop the
  /// toggle's state instead).
  ObservationsRepository? _observationsRepository;

  /// The mode's headings and surfacing order (Issue #131).
  CareModeCopy get _copy => careModeCopyFor(widget.mode);

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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
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
    if (existing != null) {
      _loadExistingSpotting(existing.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Nullable lookup: a sheet pumped where no repository is reachable at
    // all (e.g. the future-date guard in tests) resolves null rather than
    // throwing — [_syncSpottingObservation] then simply skips, since no
    // write can happen in those states anyway.
    _observationsRepository ??=
        Provider.of<ObservationsRepository?>(context, listen: false);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _savedIndicatorTimer?.cancel();
    if (_dirty && !_discardUnsaved) {
      // Belt-and-braces flush (#198): normal dismissal flushes via the
      // PopScope callback while still mounted; this covers a teardown that
      // bypassed a pop. The entry is composed before the controller dies;
      // the write itself is fire-and-forget — there is no sheet left to
      // render a failure into, and the PopScope guard has already handled
      // the interactive failure case above it. The spotting sync (#247)
      // rides along so the persisted entry and its observation row can
      // never disagree about whether the day had spotting.
      final pending = _pendingEntry;
      final repository = widget.repository;
      final observations = _observationsRepository;
      if (pending != null) {
        scheduleMicrotask(() async {
          try {
            final saved = await repository.save(pending);
            await _syncSpottingObservation(saved, pending.tz, observations);
          } catch (_) {}
        });
      }
    }
    _noteController.dispose();
    super.dispose();
  }

  /// Records a pending change and re-arms the autosave debounce (#198).
  void _markDirty() {
    if (widget.readOnly || widget.date.isAfter(widget.today)) return;
    _dirty = true;
    _pendingEntry = _composeEntry();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(kDaySheetAutosaveDelay, _performAutosave);
  }

  /// Snapshots the current editing state into the entry the next write
  /// will persist — called synchronously on change and before any await,
  /// never from a disposed context (the note controller must be alive).
  /// The flow written is [_resolveEffectiveFlow]'s (#247): spotting's
  /// presence/absence is expressed in the entry's `flow` exactly the way
  /// #335's explicit Save did, on every debounced write.
  DayEntry _composeEntry() {
    final note = _noteController.text.trim();
    final tz = (widget.timezoneProvider ?? resolveCurrentTimeZone)();
    return DayEntry(
      id: widget.existing?.id ?? '',
      profileId: widget.profileId,
      localDate: widget.date,
      tz: tz,
      flow: _resolveEffectiveFlow(),
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
  /// failed write. Never closes the sheet.
  Future<void> _performAutosave() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (_saving) {
      // A write is in flight (e.g. dismissal flushed while one ran); queue
      // this attempt so its completion re-runs with the latest state.
      _saveQueued = true;
      return;
    }
    final pending = _pendingEntry;
    if (!_dirty || pending == null) return;
    _dirty = false; // Optimistic; restored below on failure.
    _setAutosaveState(saving: true);
    final saved = await _writePending(pending);
    if (saved) _onAutosaveSuccess();
    if (_saveQueued) {
      _saveQueued = false;
      if (_dirty) unawaited(_performAutosave());
    }
  }

  /// Flips the autosave UI state; a no-op once the sheet has gone (a
  /// dismissal-time flush outlives the widget that started it).
  void _setAutosaveState({required bool saving, bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _saving = saving;
      _saveFailed = failed;
    });
  }

  /// Persists [pending]; on failure restores the pending state (the sheet
  /// keeps every entered value) and raises the inline retry error. After a
  /// successful entry write it syncs the day's spotting observation (#247)
  /// — exactly the step #335's Save performed next, moved into the
  /// autosave path; an observation-write failure surfaces through the same
  /// catch (the entry save and its spotting sync are one logical write).
  Future<bool> _writePending(DayEntry pending) async {
    // Captured while every caller is still mounted: the sync below may
    // complete after this sheet has gone (a dismissal-time flush), and
    // `Provider.of` from a dead context throws.
    final observations = _observationsRepository;
    try {
      // Only the codes freshly picked this session from the visible
      // taxonomy chip grid are validated (#237) — never the full adopted
      // `_tags`, which may still hold a pre-existing code the running build
      // does not recognise (`_unrecognisedTags`). That code is preserved,
      // not silently re-validated and rejected, on every autosave.
      validateTagCodes(_sessionSelectedTags);
      final saved = await widget.repository.save(pending);
      await _syncSpottingObservation(saved, pending.tz, observations);
      return true;
    } catch (_) {
      _dirty = true;
      _setAutosaveState(saving: false, failed: true);
      return false;
    }
  }

  /// Post-success bookkeeping: clear the pending entry, latch the offline
  /// acknowledgement messenger (issue #182 AC8 — it is shown when the sheet
  /// is dismissed, not now, because an open modal sheet's barrier hides a
  /// SnackBar), and show the transient "Saved" micro-confirmation.
  void _onAutosaveSuccess() {
    _pendingEntry = null;
    if (!mounted) return;
    _offlineAckMessenger ??= _offlineConfirmationMessenger(context);
    setState(() => _saving = false);
    _savedIndicatorTimer?.cancel();
    setState(() => _showSaved = true);
    _savedIndicatorTimer = Timer(kDaySheetSavedIndicatorDuration, () {
      if (mounted) setState(() => _showSaved = false);
    });
  }

  /// Issue #247: the day sheet doesn't otherwise load `observations` rows
  /// — this is the one exception, populating the "Spotting" toggle's
  /// initial state from any already-persisted spotting observation for
  /// [dayEntryId]. Review fix (blocking): goes through
  /// [ObservationsRepository.listForProfile] rather than
  /// [ObservationsRepository.listForDayEntry] specifically because only
  /// `listForProfile` synthesises the alias observation for a legacy
  /// `flow = 'spotting'` row that hasn't synced the server-side backfill
  /// yet (see that method's doc comment) — `listForDayEntry` alone would
  /// leave this toggle off for such a day, and the next autosave would
  /// then silently drop the spotting fact (raising the stored flow to
  /// `notBleeding` with no accompanying observation, live or synthesised).
  Future<void> _loadExistingSpotting(String dayEntryId) async {
    final observations = await Provider.of<ObservationsRepository>(
      context,
      listen: false,
    ).listForProfile(widget.profileId);
    if (!mounted) return;
    if (observations.any(
      (o) => o.dayEntryId == dayEntryId && o.category == 'spotting',
    )) {
      setState(() {
        _spotting = true;
        _hadSpottingOnLoad = true;
      });
    }
  }

  /// The `flow` value actually written by every autosave compose (#247,
  /// #335's `_resolveEffectiveFlow` verbatim): selecting "Spotting" on a
  /// day with no other flow chosen is still a positive fact about the day,
  /// not "unlogged" — it is raised to notBleeding. A day already logged at
  /// a real bleed level keeps that level; spotting is recorded alongside
  /// it as its own observation, never overwriting a chosen flow.
  ///
  /// Review fix (blocking): the mirror image — unchecking Spotting on a
  /// day whose only signal *was* spotting reverts `flow` back to
  /// [FlowLevel.none] rather than leaving the previously-derived
  /// [FlowLevel.notBleeding] behind as if it had been asserted on
  /// purpose. Guarded to fire only when the user never touched a flow
  /// chip this session ([_flowExplicitlySet]) — tapping "Not bleeding"
  /// (even alongside spotting) is a deliberate, independent assertion
  /// that survives unchecking spotting.
  FlowLevel _resolveEffectiveFlow() {
    if (_spotting && _flow == FlowLevel.none) return FlowLevel.notBleeding;
    final revertToNone =
        _hadSpottingOnLoad &&
        !_spotting &&
        !_flowExplicitlySet &&
        _flow == FlowLevel.notBleeding;
    return revertToNone ? FlowLevel.none : _flow;
  }

  /// Issue #247: spotting is its own `observations` category row, not a
  /// `FlowLevel` value — writes or clears the day's spotting observation
  /// to match [_spotting], keyed by [saved]'s id (Issue #240's per-day
  /// -entry child rows). Re-reads [saved]'s observations rather than
  /// trusting [_loadExistingSpotting]'s initial snapshot, so this stays
  /// correct even if another device wrote (or cleared) the same day's
  /// spotting observation since this sheet opened. The repository is a
  /// parameter (not a `Provider.of` here) so a write started while the
  /// sheet was mounted can finish this step after it has gone; a null
  /// [observations] (no provider reachable) skips the sync rather than
  /// failing the already-persisted entry write.
  Future<void> _syncSpottingObservation(
    DayEntry saved,
    String tz,
    ObservationsRepository? observations,
  ) async {
    if (observations == null) return;
    final existingSpotting = [
      for (final o in await observations.listForDayEntry(saved.id))
        if (o.category == 'spotting') o,
    ];
    if (!_spotting) {
      for (final o in existingSpotting) {
        await observations.delete(o.id);
      }
      return;
    }
    if (existingSpotting.isNotEmpty) return;
    await observations.save(
      Observation(
        id: '',
        dayEntryId: saved.id,
        profileId: widget.profileId,
        localDate: widget.date,
        tz: tz,
        category: 'spotting',
        code: 'spotting',
        updatedAt: DateTime.now().toUtc(),
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).daySheetDeleteTitle),
        content: Text(
          AppLocalizations.of(context)
              .daySheetDeleteBody(daySheetDateLabel(widget.date, widget.today)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).daySheetCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context).daySheetDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // A delete must never be resurrected by a still-pending autosave: drop
    // any debounce in flight before tombstoning (#198).
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _dirty = false;
    _pendingEntry = null;
    setState(() {
      _busy = true;
      _deleteFailed = false;
    });
    try {
      await widget.repository.delete(widget.profileId, widget.date);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _deleteFailed = true;
        });
      }
      return;
    }
    if (mounted) {
      // A latched offline acknowledgement is about the *saved* entry — the
      // entry is now deleted, so it must not fire as the sheet leaves.
      _offlineAckMessenger = null;
      Navigator.of(context).pop();
    }
  }

  /// PopScope wiring (#198): dismissal of a cleanly autosaved (or clean)
  /// sheet just closes; a debounced change still pending is flushed so
  /// dismissal never silently drops it; and a failed-pending sheet refuses
  /// to close without an explicit discard ([_confirmDiscardWhileFailed]).
  void _onSheetPop(bool didPop, Object? result) {
    if (!didPop) {
      if (_saveFailed && !_discardUnsaved) _confirmDiscardWhileFailed();
      return;
    }
    final flushPending = _dirty && !_discardUnsaved;
    // Computed before the flush clears `_dirty`: an offline-looking flush
    // earns the same "Saved on this device · will sync" acknowledgement a
    // completed save already latched in `_offlineAckMessenger`.
    final messenger =
        _offlineAckMessenger ??
        (flushPending ? _offlineConfirmationMessenger(context) : null);
    if (flushPending) unawaited(_performAutosave());
    messenger?.showSnackBar(
      const SnackBar(
        key: ValueKey('offline-save-confirmation'),
        content: Text(kOfflineSaveConfirmationCopy),
      ),
    );
  }

  /// The discard confirmation shown when dismissal is attempted while a
  /// save has failed and the changes are still unsaved (#198). "Keep
  /// editing" returns to the sheet (the inline retry error is still there);
  /// "Discard" deliberately drops the pending changes and closes.
  Future<void> _confirmDiscardWhileFailed() async {
    if (_discardDialogOpen) return;
    _discardDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).daySheetDiscardTitle),
        content: const Text(
          "The last change couldn't be saved. Discarding removes it from "
          'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).daySheetKeepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(context).daySheetDiscard),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard != true || !mounted) return;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    setState(() {
      _discardUnsaved = true;
      _dirty = false;
    });
    _pendingEntry = null;
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
        padding: const EdgeInsets.symmetric(vertical: 24),
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
      canPop: !_saveFailed || _discardUnsaved,
      onPopInvokedWithResult: _onSheetPop,
      child: _sheetShell(child: body),
    );
  }

  Widget _sheetShell({required Widget child}) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
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
        child: child,
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
      spacing: 8,
      runSpacing: 4,
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
                      if (selected) _selectFlow(level);
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

  /// Selects [level] as the day's flow — the single write path behind both
  /// the visible ChoiceChip's `onSelected` and the #138 semantics wrapper's
  /// accessibility tap.
  void _selectFlow(FlowLevel level) {
    setState(() {
      _flow = level;
      _flowExplicitlySet = true;
    });
    _markDirty();
  }

  /// Sets the standalone spotting toggle (issue #247) — shared by the
  /// visible chip and its semantics tap.
  void _toggleSpotting(bool value) {
    setState(() => _spotting = value);
    _markDirty();
  }

  /// Sets the first-class PMS toggle (issue #220) — shared by the visible
  /// chip and its semantics tap. The marker rides the entry itself, so
  /// this is exactly like any other content change: state, then dirty.
  void _togglePms(bool value) {
    setState(() => _pms = value);
    _markDirty();
  }

  /// Adds or removes [code] from the taxonomy grid — shared by the visible
  /// chip and its semantics tap (#138).
  void _toggleTag(String code) {
    setState(() {
      if (_tags.contains(code)) {
        _tags.remove(code);
        _sessionSelectedTags.remove(code);
      } else {
        _tags.add(code);
        _sessionSelectedTags.add(code);
      }
    });
    _markDirty();
  }

  /// A section heading for the editable sheet (#138): visible like before
  /// (labelMedium), and flagged [Semantics.header] so screen readers offer
  /// heading navigation between the chip groups.
  Widget _sectionHeading(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(label, style: theme.textTheme.labelMedium),
    ),
  );

  Widget _editableBody() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // A Wrap, not a Row (#198): the human-readable title is
                  // wider than the raw ISO string it replaced, and a long
                  // attribution badge beside it would overflow horizontally
                  // — the badge flows to a second line instead.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // #138: flagged as a heading so the sheet's date is
                      // reachable through screen-reader heading navigation.
                      Semantics(
                        header: true,
                        child: Text(
                          key: const ValueKey('day-sheet-date-title'),
                          daySheetDateLabel(widget.date, widget.today),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (widget.existing != null)
                        CaregiverAttributionBadge(
                          loggedByUserId: widget.existing!.loggedByUserId,
                          lastModifiedByUserId:
                              widget.existing!.lastModifiedByUserId,
                          currentUserId: widget.currentUserId,
                          guardians: widget.guardians,
                          source: widget.existing!.source.toDb(),
                        ),
                    ],
                  ),
                ),
                _sectionHeading(theme, l10n.daySheetFlowLabel),
                _flowChips(l10n),
                // Issue #220: the first-class PMS toggle sits between the
                // flow row and the taxonomy grid — it belongs to neither.
                _pmsChip(l10n),
                for (final category in _copy.categoriesInOrder) ...[
                  _sectionHeading(theme, _copy.categoryLabel(category)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in kTagTaxonomy)
                        if (tag.category == category)
                          groupedChipSemantics(
                            group: _copy.categoryLabel(category),
                            label: tag.display,
                            selected: _tags.contains(tag.code),
                            onTap: _busy ? null : () => _toggleTag(tag.code),
                            child: FilterChip(
                              label: Text(tag.display),
                              selected: _tags.contains(tag.code),
                              onSelected: _busy
                                  ? null
                                  : (selected) => _toggleTag(tag.code),
                            ),
                          ),
                    ],
                  ),
                ],
                if (_unrecognisedTags.isNotEmpty)
                  ..._unrecognisedTagsSection(theme),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    key: const ValueKey('note-field'),
                    controller: _noteController,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l10n.daySheetNoteLabel,
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    // Mirrors the server CHECK; a longer note is rejected forever.
                    maxLength: kMaxNoteLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  ),
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
  /// affordance and the autosave status (plus the save/delete retry
  /// errors) sit here, below the scroll view, so they stay on screen no
  /// matter how many chip categories are expanded — and above the
  /// keyboard, thanks to the shell's view-inset padding.
  Widget _pinnedBottomArea(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saveFailed)
          InlineError(
            key: const ValueKey('save-error'),
            message: l10n.daySheetSaveError,
            onRetry: _performAutosave,
          ),
        if (_deleteFailed)
          InlineError(
            key: const ValueKey('delete-error'),
            message: l10n.daySheetDeleteError,
            onRetry: _delete,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
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
    if (_saving) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).daySheetSaving, style: theme.textTheme.bodySmall),
        ],
      );
    } else if (_showSaved) {
      content = Row(
        key: const ValueKey('autosave-saved'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(AppLocalizations.of(context).daySheetSaved, style: theme.textTheme.bodySmall),
        ],
      );
    } else {
      content = const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: KeyedSubtree(
        key: const ValueKey('autosave-status'),
        child: content,
      ),
    );
  }

  /// Inert, visible chips for [_unrecognisedTags] (#237): unlike the
  /// taxonomy [FilterChip] grid above, these carry no `onSelected` — they
  /// cannot be toggled, only shown — so they round-trip through `_tags`
  /// (and therefore through autosave) unchanged rather than being silently
  /// dropped or invisibly resubmitted as if user-validated.
  List<Widget> _unrecognisedTagsSection(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        AppLocalizations.of(context).daySheetUnrecognised,
        style: theme.textTheme.labelMedium,
      ),
    ),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final code in _unrecognisedTags)
          Chip(key: ValueKey('unrecognised-tag-$code'), label: Text(code)),
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
  String? get _readOnlyReason => acceptedGuardianFor(
    widget.guardians,
    widget.currentUserId,
  )?.role.readOnlyReason;

  Widget _readOnlyBody() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final reason = _readOnlyReason;
    final existing = widget.existing;
    if (existing == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reason != null) ...[
              Text(reason, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
            ],
            Text(AppLocalizations.of(context).daySheetNoEntry, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return Column(
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
          const SizedBox(height: 8),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // #138: heading flag mirrors the editable sheet's date title.
            Semantics(
              header: true,
              child: Text(
                key: const ValueKey('day-sheet-date-title'),
                daySheetDateLabel(existing.localDate, widget.today),
                style: theme.textTheme.titleMedium,
              ),
            ),
            CaregiverAttributionBadge(
              loggedByUserId: existing.loggedByUserId,
              lastModifiedByUserId: existing.lastModifiedByUserId,
              currentUserId: widget.currentUserId,
              guardians: widget.guardians,
              source: existing.source.toDb(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(AppLocalizations.of(context).daySheetFlowLabel, style: theme.textTheme.labelMedium),
        Text(localizedFlowLabel(existing.flow, l10n), style: theme.textTheme.titleSmall),
        // Issue #220: the read-only view names the PMS marker too, so a
        // viewer (or a reviewing guardian) sees the phase even though the
        // toggle itself is disabled here.
        if (existing.pms) ...[
          const SizedBox(height: 12),
          Text(l10n.daySheetPmsGroup, style: theme.textTheme.labelMedium),
          Text(l10n.daySheetPmsChip, style: theme.textTheme.titleSmall),
        ],
        if (existing.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(AppLocalizations.of(context).daySheetTagsLabel, style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final code in existing.tags)
                Chip(label: Text(tagByCode(code)?.display ?? code)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(AppLocalizations.of(context).daySheetNoteLabel, style: theme.textTheme.labelMedium),
        Text(
          (existing.note == null || existing.note!.isEmpty)
              ? AppLocalizations.of(context).daySheetNoNote
              : existing.note!,
        ),
      ],
    );
  }
}
