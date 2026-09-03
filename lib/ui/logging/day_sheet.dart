/// Day entry sheet (U5, R8/R9): flow selector, one-tap curated tag chips,
/// free-text note, Save (upsert) and confirm-then-tombstone Delete.
///
/// Guards: future dates are never loggable (the calendar disables them; the
/// sheet re-checks), archived profiles get a read-only view with no
/// save/delete affordances, and a repository save/delete failure keeps the
/// sheet open with all entered values intact plus an inline retry error.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/tags.dart';

String flowLabel(FlowLevel flow) {
  final name = flow.name;
  return name[0].toUpperCase() + name.substring(1);
}

String _categoryLabel(TagCategory category) => switch (category) {
      TagCategory.pain => 'Pain',
      TagCategory.body => 'Body',
      TagCategory.mood => 'Mood',
      TagCategory.other => 'Other',
    };

class DaySheet extends StatefulWidget {
  const DaySheet({
    super.key,
    required this.repository,
    required this.profileId,
    required this.date,
    required this.today,
    this.existing,
    this.readOnly = false,
  });

  final DayEntriesRepository repository;
  final String profileId;
  final LocalDate date;

  /// Device-local civil date; [date] must not be after this to be loggable.
  final LocalDate today;

  /// The current live entry for (profileId, date), or null for a new log.
  final DayEntry? existing;
  final bool readOnly;

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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _flow = existing?.flow ?? FlowLevel.none;
    _tags = {...?existing?.tags};
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
    try {
      await widget.repository.save(DayEntry(
        id: widget.existing?.id ?? '',
        profileId: widget.profileId,
        localDate: widget.date,
        tz: DateTime.now().timeZoneName,
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
            child:
                Text(widget.date.iso, style: theme.textTheme.titleMedium),
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
          for (final category in TagCategory.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                _categoryLabel(category),
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
                                } else {
                                  _tags.remove(tag.code);
                                }
                              });
                            },
                    ),
              ],
            ),
          ],
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
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "Couldn't save — try again",
                key: ValueKey('save-error'),
                style: TextStyle(color: Color(0xFFB3261E)),
              ),
            ),
          if (_deleteFailed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "Couldn't delete — try again",
                key: ValueKey('delete-error'),
                style: TextStyle(color: Color(0xFFB3261E)),
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

  Widget _readOnlyBody() {
    final theme = Theme.of(context);
    final existing = widget.existing;
    if (existing == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No entry for this day.', style: theme.textTheme.bodyMedium),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(existing.localDate.iso, style: theme.textTheme.titleMedium),
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
