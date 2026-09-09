/// Day entry sheet (U5, R8/R9): flow selector, one-tap curated tag chips,
/// free-text note, Save (upsert) and confirm-then-tombstone Delete.
///
/// Guards: future dates are never loggable (the calendar disables them; the
/// sheet re-checks), archived profiles get a read-only view with no
/// save/delete affordances, and a repository save/delete failure keeps the
/// sheet open with all entered values intact plus an inline retry error.
///
/// Issue #131: the profile's care mode selects the category headings and
/// the order they are surfaced in (`careModeCopyFor`) — a prospective
/// logging-default only. Every category remains available in every mode
/// (teen reorders, it never removes: "not a euphemism for a reduced app"),
/// and saved entries always render verbatim regardless of mode.
///
/// Route naming (U2 Approach 2b): the sheet itself is named
/// `DaySheetScreen` at its push site (`month_calendar.dart`). Its internal
/// "Delete this entry?" `showDialog` is deliberately left unnamed — a
/// trivial confirm/cancel choice, not a distinct destination.
library;

import 'package:flutter/material.dart';
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
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart'
    show kOfflineSaveConfirmationCopy, shouldConfirmOfflineSave;
import 'package:provider/provider.dart';

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';

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

/// Issue #160: the localized flow-chip label. Same five strings
/// [flowLabel] derives from the enum name for `en`; this variant reads them
/// from [AppLocalizations] so the sheet's chips follow the active locale
/// (`flowLabel` stays as the `en` fallback for callers outside the four
/// localized screens, e.g. the activity feed).
String localizedFlowLabel(FlowLevel flow, AppLocalizations l10n) =>
    switch (flow) {
      FlowLevel.none => l10n.flowLevelNone,
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.spotting => l10n.flowLevelSpotting,
      FlowLevel.light => l10n.flowLevelLight,
      FlowLevel.medium => l10n.flowLevelMedium,
      FlowLevel.heavy => l10n.flowLevelHeavy,
      // Issue #247 values: no ARB keys yet (#160 follow-up) — `en` fallback.
      FlowLevel.notBleeding => 'Not bleeding',
      FlowLevel.superHeavy => 'Super heavy',
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

  /// Issue #247: spotting is logged as its own `observations` row
  /// (`category: 'spotting'`), not a [FlowLevel] value — this toggle
  /// tracks it independently of [_flow]. Initialised from any already
  /// -persisted (or synthesised-from-legacy-`spotting`-flow) spotting
  /// observation by [_loadExistingSpotting]; starts `false` for a new
  /// entry.
  bool _spotting = false;

  /// Review fix (blocking): `true` once [_loadExistingSpotting] finds the
  /// day already had spotting on load — kept `true` even after the user
  /// unchecks the toggle, so [_save] can tell "spotting was just removed"
  /// apart from "spotting was never on this session".
  bool _hadSpottingOnLoad = false;

  /// Review fix (blocking): `true` once the user taps any flow chip this
  /// session (including re-tapping the already-selected one) — an
  /// explicit choice, as opposed to [_flow]'s initial value merely being
  /// inherited from the loaded entry (which, for a spotting-only day, is
  /// [FlowLevel.notBleeding] only because spotting raised it there, never
  /// because anyone chose "Not bleeding" on purpose). See [_save]'s
  /// `revertToNone`.
  bool _flowExplicitlySet = false;

  /// The mode's headings and surfacing order (Issue #131).
  CareModeCopy get _copy => careModeCopyFor(widget.mode);

  /// Stored codes absent from [kTagTaxonomy] at load time (#237): the chip
  /// grid below only ever renders [kTagTaxonomy] members, so a code the
  /// running build does not recognise would otherwise be adopted into
  /// [_tags] invisibly and undeselectably. Rendered separately as inert
  /// chips (`_unrecognisedTagsSection`) and never touched by the taxonomy
  /// chip grid's `onSelected`, so they round-trip through Save unchanged.
  late final List<String> _unrecognisedTags;

  /// Codes the user actively picked from the visible taxonomy chip grid
  /// this editing session (#237) — as opposed to [_tags], which also holds
  /// whatever the entry already carried (including [_unrecognisedTags]).
  /// [validateTagCodes] is invoked against only this set before Save, never
  /// against the full adopted [_tags]: a pre-existing unknown code must
  /// never be re-validated (and rejected) just because Save was pressed.
  final Set<String> _sessionSelectedTags = {};

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _flow = existing?.flow ?? FlowLevel.none;
    _tags = {...?existing?.tags};
    _unrecognisedTags = [
      for (final code in existing?.tags ?? const <String>[])
        if (!isValidTagCode(code)) code,
    ];
    _noteController = TextEditingController(text: existing?.note ?? '');
    if (existing != null) {
      _loadExistingSpotting(existing.id);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
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
  /// leave this toggle off for such a day, and Save would then silently
  /// drop the spotting fact (raising the stored flow to `notBleeding`
  /// with no accompanying observation, live or synthesised).
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

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    final note = _noteController.text.trim();
    final tz = (widget.timezoneProvider ?? resolveCurrentTimeZone)();
    final effectiveFlow = _resolveEffectiveFlow();
    try {
      // Only the codes freshly picked this session from the visible
      // taxonomy chip grid are validated (#237) — never the full adopted
      // `_tags`, which may still hold a pre-existing code the running build
      // does not recognise (`_unrecognisedTags`). That code is preserved,
      // not silently re-validated and rejected, on every Save.
      validateTagCodes(_sessionSelectedTags);
      final saved = await widget.repository.save(
        DayEntry(
          id: widget.existing?.id ?? '',
          profileId: widget.profileId,
          localDate: widget.date,
          tz: tz,
          flow: effectiveFlow,
          tags: _tags.toList(),
          note: note.isEmpty ? null : note,
          updatedAt: DateTime.now().toUtc(),
          // Issue #159 review finding: a bare `DayEntry(...)` defaults to
          // manual/null/null, which would silently reset an imported entry's
          // provenance on every Save (even a no-op one) — carry forward
          // whatever the loaded entry already had instead.
          source: widget.existing?.source ?? DayEntrySource.manual,
          sourceId: widget.existing?.sourceId,
          importId: widget.existing?.importId,
        ),
      );
      // Review fix (blocking): a save that outlives this sheet (the user
      // navigated away while the await above was in flight) must not touch
      // this now-unmounted widget's `context` — `_syncSpottingObservation`
      // reads `Provider.of` from it.
      if (!mounted) return;
      await _syncSpottingObservation(saved, tz);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _saveFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    final messenger = _offlineConfirmationMessenger(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      const SnackBar(
        key: ValueKey('offline-save-confirmation'),
        content: Text(kOfflineSaveConfirmationCopy),
      ),
    );
  }

  /// The `flow` value actually written by [_save]. Issue #247: selecting
  /// "Spotting" on a day with no other flow chosen is still a positive
  /// fact about the day, not "unlogged" — it is raised to notBleeding. A
  /// day already logged at a real bleed level keeps that level; spotting
  /// is recorded alongside it as its own observation, never overwriting a
  /// chosen flow.
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
  /// spotting observation since this sheet opened.
  Future<void> _syncSpottingObservation(DayEntry saved, String tz) async {
    final repo = Provider.of<ObservationsRepository>(context, listen: false);
    final existingSpotting = [
      for (final o in await repo.listForDayEntry(saved.id))
        if (o.category == 'spotting') o,
    ];
    if (!_spotting) {
      for (final o in existingSpotting) {
        await repo.delete(o.id);
      }
      return;
    }
    if (existingSpotting.isNotEmpty) return;
    await repo.save(
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

  /// Issue #182 AC8: captured before [Navigator.pop] (the sheet's own
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.daySheetDeleteTitle),
        content: Text(l10n.daySheetDeleteBody(widget.date.iso)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.daySheetCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.daySheetDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.date.isAfter(widget.today)) {
      return _sheetShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(AppLocalizations.of(context).daySheetFutureDate),
        ),
      );
    }
    if (widget.readOnly) {
      return _sheetShell(child: _readOnlyBody());
    }
    return _sheetShell(child: _editableBody());
  }

  Widget _sheetShell({required Widget child}) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        width: double.infinity,
        child: child,
      ),
    );
  }

  /// The flow chip row plus the standalone spotting toggle (issue #247).
  /// Split out of [_editableBody] to keep each method under the CRAP gate.
  Widget _flowChips(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final level in kSelectableFlowLevels)
          ChoiceChip(
            label: Text(localizedFlowLabel(level, l10n)),
            selected: _flow == level,
            onSelected: _busy
                ? null
                : (selected) {
                    if (selected) {
                      setState(() {
                        _flow = level;
                        _flowExplicitlySet = true;
                      });
                    }
                  },
          ),
        // Issue #247: spotting is its own `observations` category,
        // not a flow level — a standalone toggle rather than one of
        // the flow chips above, so it can coexist with any flow
        // selection (see `_syncSpottingObservation`).
        FilterChip(
          key: const ValueKey('spotting-chip'),
          label: const Text('Spotting'),
          selected: _spotting,
          onSelected: _busy
              ? null
              : (selected) => setState(() => _spotting = selected),
        ),
      ],
    );
  }

  Widget _editableBody() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.date.iso, style: theme.textTheme.titleMedium),
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
          ),
          _flowChips(l10n),
          for (final category in _copy.categoriesInOrder) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                _copy.categoryLabel(category),
                style: theme.textTheme.labelMedium,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in kTagTaxonomy)
                  if (tag.category == category)
                    FilterChip(
                      label: Text(tag.display),
                      selected: _tags.contains(tag.code),
                      onSelected: _busy
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _tags.add(tag.code);
                                  _sessionSelectedTags.add(tag.code);
                                } else {
                                  _tags.remove(tag.code);
                                  _sessionSelectedTags.remove(tag.code);
                                }
                              });
                            },
                    ),
              ],
            ),
          ],
          if (_unrecognisedTags.isNotEmpty) ..._unrecognisedTagsSection(theme),
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
          if (_saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineError(
                key: const ValueKey('save-error'),
                message: l10n.daySheetSaveError,
                onRetry: _save,
              ),
            ),
          if (_deleteFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineError(
                key: const ValueKey('delete-error'),
                message: l10n.daySheetDeleteError,
                onRetry: _delete,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: widget.existing == null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (widget.existing != null)
                  IconButton(
                    tooltip: l10n.daySheetDeleteTooltip,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : _delete,
                  ),
                FilledButton(
                  key: const ValueKey('save-button'),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.daySheetSave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Inert, visible chips for [_unrecognisedTags] (#237): unlike the
  /// taxonomy [FilterChip] grid above, these carry no `onSelected` — they
  /// cannot be toggled, only shown — so they round-trip through `_tags`
  /// (and therefore through Save) unchanged rather than being silently
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
            Text(l10n.daySheetNoEntry, style: theme.textTheme.bodyMedium),
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
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(existing.localDate.iso, style: theme.textTheme.titleMedium),
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
        Text(l10n.daySheetFlowLabel, style: theme.textTheme.labelMedium),
        Text(
          localizedFlowLabel(existing.flow, l10n),
          style: theme.textTheme.titleSmall,
        ),
        if (existing.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.daySheetTagsLabel, style: theme.textTheme.labelMedium),
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
        Text(l10n.daySheetNoteLabel, style: theme.textTheme.labelMedium),
        Text(
          (existing.note == null || existing.note!.isEmpty)
              ? l10n.daySheetNoNote
              : existing.note!,
        ),
      ],
    );
  }
}
