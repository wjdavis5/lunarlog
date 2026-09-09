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
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/domain/util/timezone.dart';

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';

String flowLabel(FlowLevel flow) {
  final name = flow.name;
  return name[0].toUpperCase() + name.substring(1);
}

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
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    final note = _noteController.text.trim();
    final tz = (widget.timezoneProvider ?? resolveCurrentTimeZone)();
    try {
      // Only the codes freshly picked this session from the visible
      // taxonomy chip grid are validated (#237) — never the full adopted
      // `_tags`, which may still hold a pre-existing code the running build
      // does not recognise (`_unrecognisedTags`). That code is preserved,
      // not silently re-validated and rejected, on every Save.
      validateTagCodes(_sessionSelectedTags);
      await widget.repository.save(DayEntry(
        id: widget.existing?.id ?? '',
        profileId: widget.profileId,
        localDate: widget.date,
        tz: tz,
        flow: _flow,
        tags: _tags.toList(),
        note: note.isEmpty ? null : note,
        updatedAt: DateTime.now().toUtc(),
      ));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _saveFailed = true;
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'The entry for ${widget.date.iso} is removed from the calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
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
          child: const Text("Future dates can't be logged."),
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

  Widget _editableBody() {
    final theme = Theme.of(context);
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
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final level in FlowLevel.values)
                ChoiceChip(
                  label: Text(flowLabel(level)),
                  selected: _flow == level,
                  onSelected: _busy
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() => _flow = level);
                          }
                        },
                ),
            ],
          ),
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
              decoration: const InputDecoration(
                labelText: 'Note',
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
                message: "Couldn't save — try again",
                onRetry: _save,
              ),
            ),
          if (_deleteFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineError(
                key: const ValueKey('delete-error'),
                message: "Couldn't delete — try again",
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
                    tooltip: 'Delete entry',
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
                      : const Text('Save'),
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
          child: Text('Unrecognised', style: theme.textTheme.labelMedium),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final code in _unrecognisedTags)
              Chip(
                key: ValueKey('unrecognised-tag-$code'),
                label: Text(code),
              ),
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
  String? get _readOnlyReason =>
      acceptedGuardianFor(widget.guardians, widget.currentUserId)
          ?.role
          .readOnlyReason;

  Widget _readOnlyBody() {
    final theme = Theme.of(context);
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
            Text('No entry for this day.', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reason != null) ...[
          Text(reason, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
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
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Flow', style: theme.textTheme.labelMedium),
        Text(flowLabel(existing.flow), style: theme.textTheme.titleSmall),
        if (existing.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Tags', style: theme.textTheme.labelMedium),
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
        Text('Note', style: theme.textTheme.labelMedium),
        Text(
          (existing.note == null || existing.note!.isEmpty)
              ? 'No note'
              : existing.note!,
        ),
      ],
    );
  }
}
