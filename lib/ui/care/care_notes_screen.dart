/// Shared care notes and visit-prep checklist for one profile (Issue #128).
///
/// Two per-profile, non-date-bound surfaces visible to every accepted
/// guardian on the profile: standing care notes (free text, who wrote it
/// and when) and a visit-prep checklist (add, check off with who-checked
/// attribution, remove; checked items stay visible until the list is
/// cleared). Reached from the profile screen's app bar; the account JSON
/// export carries both (the clinician-facing half carries the prep list).
///
/// Role gating mirrors the day sheet: a `viewer` reads both surfaces and
/// cannot write to either (AC2) — inputs are hidden and the viewer's
/// read-only reason is shown. Server-side enforcement lives in RLS +
/// `sync_push` (a viewer push is rejected); this screen only reflects it.
///
/// Attribution copy never shows a raw uuid (the activity-feed precedent):
/// the guardian's display name is resolved from the guardians watch, with
/// "Another guardian" as the fallback and "You" for the current operator.
///
/// This is deliberately not messaging: no threading, no replies, no
/// notifications of its own.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:provider/provider.dart';

/// Formats an instant as a bare civil date (`2026-08-31`) for the
/// attribution line. Time-of-day is not shown: "who and roughly when" is
/// the whole contract, and a date keeps the copy stable across zones.
String careAttributionDate(DateTime instant) {
  final local = instant.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class CareNotesScreen extends StatefulWidget {
  const CareNotesScreen({
    super.key,
    required this.profile,
    required this.repository,
    required this.guardiansRepository,
    this.readOnly = false,
  });

  final Profile profile;
  final CareContentRepository repository;
  final ProfileGuardiansRepository guardiansRepository;

  /// The archived-profile passthrough (additive with the viewer gate, which
  /// is derived per snapshot below).
  final bool readOnly;

  @override
  State<CareNotesScreen> createState() => _CareNotesScreenState();
}

class _CareNotesScreenState extends State<CareNotesScreen> {
  late final Stream<List<CareNote>> _notesStream;
  late final Stream<List<VisitPrepItem>> _prepStream;
  late final Stream<List<ProfileGuardian>> _guardiansStream;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();
  String? _currentUserId;
  AuthController? _auth;
  bool _savingNote = false;
  bool _savingItem = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notesStream = widget.repository.watchCareNotes(widget.profile.id);
    _prepStream = widget.repository.watchPrepItems(widget.profile.id);
    _guardiansStream =
        widget.guardiansRepository.watchForProfile(widget.profile.id);
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    _noteController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.profile.displayName} Care')),
      body: StreamBuilder<List<ProfileGuardian>>(
        stream: _guardiansStream,
        builder: (context, guardiansSnapshot) {
          final guardians = guardiansSnapshot.data ?? const [];
          final viewerReadOnly =
              acceptedGuardianFor(guardians, _currentUserId)?.role.canLog ==
                  false;
          final effectiveReadOnly = widget.readOnly || viewerReadOnly;
          final readOnlyReason = widget.readOnly
              ? 'This profile is archived.'
              : acceptedGuardianFor(guardians, _currentUserId)
                  ?.role
                  .readOnlyReason;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (effectiveReadOnly && readOnlyReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    readOnlyReason,
                    key: const ValueKey('care-read-only-reason'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    key: const ValueKey('care-error'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
              _CareNotesSection(
                notesStream: _notesStream,
                guardians: guardians,
                currentUserId: _currentUserId,
                canWrite: !effectiveReadOnly,
                controller: _noteController,
                saving: _savingNote,
                onAdd: _addNote,
                onDelete: _deleteNote,
              ),
              const SizedBox(height: 24),
              _VisitPrepSection(
                prepStream: _prepStream,
                guardians: guardians,
                currentUserId: _currentUserId,
                canWrite: !effectiveReadOnly,
                controller: _itemController,
                saving: _savingItem,
                onAdd: _addItem,
                onToggle: _toggleItem,
                onDelete: _deleteItem,
                onClearChecked: _clearChecked,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addNote() async {
    final body = _noteController.text.trim();
    if (body.isEmpty || _savingNote) return;
    setState(() {
      _savingNote = true;
      _error = null;
    });
    try {
      await widget.repository.saveCareNote(
        profileId: widget.profile.id,
        body: body,
      );
      _noteController.clear();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the care note.');
      }
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _addItem() async {
    final body = _itemController.text.trim();
    if (body.isEmpty || _savingItem) return;
    setState(() {
      _savingItem = true;
      _error = null;
    });
    try {
      await widget.repository.addPrepItem(
        profileId: widget.profile.id,
        body: body,
      );
      _itemController.clear();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not add the prep item.');
      }
    } finally {
      if (mounted) setState(() => _savingItem = false);
    }
  }

  Future<void> _toggleItem(VisitPrepItem item, bool checked) async {
    setState(() => _error = null);
    try {
      await widget.repository.setPrepItemChecked(
        id: item.id,
        checked: checked,
        checkedByUserId: checked ? _currentUserId : null,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update the prep item.');
      }
    }
  }

  Future<void> _deleteItem(VisitPrepItem item) async {
    setState(() => _error = null);
    try {
      await widget.repository.deletePrepItem(item.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not remove the prep item.');
      }
    }
  }

  Future<void> _deleteNote(CareNote note) async {
    setState(() => _error = null);
    try {
      await widget.repository.deleteCareNote(note.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not remove the care note.');
      }
    }
  }

  Future<void> _clearChecked() async {
    setState(() => _error = null);
    try {
      await widget.repository.clearCheckedPrepItems(widget.profile.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not clear the checked items.');
      }
    }
  }
}

/// Resolves [userId] to display copy for the "Checked by" line, mirroring
/// [CaregiverAttributionBadge]'s naming ("you" for the current operator,
/// the guardian's display name when known, the role label, "Caregiver" as
/// the fallback) — never a raw uuid (the activity-feed precedent).
String careActorCopy(
  String? userId,
  List<ProfileGuardian> guardians,
  String? currentUserId,
) {
  if (userId != null) {
    if (userId == currentUserId) return 'you';
    final guardian = _guardianFor(userId, guardians);
    if (guardian != null) {
      final name = guardian.displayName;
      return (name == null || name.isEmpty) ? guardian.role.label : name;
    }
  }
  return 'Caregiver';
}

/// The guardian row for [userId], or null when no row matches. Split out
/// of [careActorCopy] so neither method carries the lookup and the naming
/// branches together under the CRAP gate.
ProfileGuardian? _guardianFor(
    String userId, List<ProfileGuardian> guardians) {
  for (final guardian in guardians) {
    if (guardian.userId == userId) return guardian;
  }
  return null;
}

class _CareNotesSection extends StatelessWidget {
  const _CareNotesSection({
    required this.notesStream,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.controller,
    required this.saving,
    required this.onAdd,
    required this.onDelete,
  });

  final Stream<List<CareNote>> notesStream;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final TextEditingController controller;
  final bool saving;
  final Future<void> Function() onAdd;
  final Future<void> Function(CareNote note) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Care notes', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        StreamBuilder<List<CareNote>>(
          stream: notesStream,
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const [];
            if (notes.isEmpty) {
              return const Text(
                'No care notes yet.',
                key: ValueKey('care-notes-empty'),
              );
            }
            return Column(
              children: [
                for (final note in notes)
                  _CareNoteRow(
                    note: note,
                    guardians: guardians,
                    currentUserId: currentUserId,
                    canWrite: canWrite,
                    onDelete: onDelete,
                  ),
              ],
            );
          },
        ),
        if (canWrite) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('care-note-field'),
            controller: controller,
            maxLength: kMaxCareNoteLength,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Add a care note',
              hintText: 'Standing notes for everyone caring for this profile',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('care-note-add'),
              onPressed: saving ? null : onAdd,
              child: const Text('Add note'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CareNoteRow extends StatelessWidget {
  const _CareNoteRow({
    required this.note,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.onDelete,
  });

  final CareNote note;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final Future<void> Function(CareNote note) onDelete;

  @override
  Widget build(BuildContext context) {
    // Server-authoritative attribution, when the row has synced at least
    // once (the badge hides itself for a never-synced local row — the
    // CaregiverAttributionBadge precedent: nothing known, nothing shown).
    final hasAttribution = note.loggedByUserId != null ||
        note.lastModifiedByUserId != null;
    return Card(
      key: ValueKey('care-note-${note.id}'),
      child: ListTile(
        title: Text(note.body),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAttribution)
              CaregiverAttributionBadge(
                loggedByUserId: note.loggedByUserId,
                lastModifiedByUserId: note.lastModifiedByUserId,
                currentUserId: currentUserId,
                guardians: guardians,
              ),
            Text(
              careAttributionDate(note.updatedAt),
              key: ValueKey('care-note-by-${note.id}'),
            ),
          ],
        ),
        trailing: canWrite
            ? IconButton(
                key: ValueKey('care-note-delete-${note.id}'),
                tooltip: 'Remove note',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(note),
              )
            : null,
      ),
    );
  }
}

class _VisitPrepSection extends StatelessWidget {
  const _VisitPrepSection({
    required this.prepStream,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.controller,
    required this.saving,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onClearChecked,
  });

  final Stream<List<VisitPrepItem>> prepStream;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final TextEditingController controller;
  final bool saving;
  final Future<void> Function() onAdd;
  final Future<void> Function(VisitPrepItem item, bool checked) onToggle;
  final Future<void> Function(VisitPrepItem item) onDelete;
  final Future<void> Function() onClearChecked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Visit prep', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        StreamBuilder<List<VisitPrepItem>>(
          stream: prepStream,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const Text(
                'No prep items yet.',
                key: ValueKey('visit-prep-empty'),
              );
            }
            final checkedCount = items.where((i) => i.isChecked).length;
            return Column(
              children: [
                for (final item in items)
                  _VisitPrepRow(
                    item: item,
                    guardians: guardians,
                    currentUserId: currentUserId,
                    canWrite: canWrite,
                    onToggle: onToggle,
                    onDelete: onDelete,
                  ),
                if (canWrite && checkedCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('visit-prep-clear-checked'),
                      onPressed: onClearChecked,
                      child: Text('Clear checked ($checkedCount)'),
                    ),
                  ),
              ],
            );
          },
        ),
        if (canWrite) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('visit-prep-field'),
            controller: controller,
            maxLength: kMaxVisitPrepItemLength,
            decoration: const InputDecoration(
              labelText: 'Add a prep item',
              hintText: 'A question or to-bring for the next appointment',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('visit-prep-add'),
              onPressed: saving ? null : onAdd,
              child: const Text('Add item'),
            ),
          ),
        ],
      ],
    );
  }
}

class _VisitPrepRow extends StatelessWidget {
  const _VisitPrepRow({
    required this.item,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.onToggle,
    required this.onDelete,
  });

  final VisitPrepItem item;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final Future<void> Function(VisitPrepItem item, bool checked) onToggle;
  final Future<void> Function(VisitPrepItem item) onDelete;

  @override
  Widget build(BuildContext context) {
    final checkedBy = item.isChecked
        ? careActorCopy(item.checkedByUserId, guardians, currentUserId)
        : null;
    return Card(
      key: ValueKey('visit-prep-${item.id}'),
      child: CheckboxListTile(
        key: ValueKey('visit-prep-check-${item.id}'),
        value: item.isChecked,
        onChanged: canWrite ? (checked) => onToggle(item, checked ?? false) : null,
        title: Text(item.body),
        subtitle: checkedBy == null
            ? null
            : Text(
                'Checked by $checkedBy',
                key: ValueKey('visit-prep-checked-by-${item.id}'),
              ),
        secondary: canWrite
            ? IconButton(
                key: ValueKey('visit-prep-delete-${item.id}'),
                tooltip: 'Remove item',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(item),
              )
            : null,
      ),
    );
  }
}

/// The care entry point: an app-bar icon pushing [CareNotesScreen],
/// mirroring [ActivityFeedButton]'s shape (no "new" dot — care content has
/// no notifications of its own by design).
class CareNotesButton extends StatelessWidget {
  const CareNotesButton({
    super.key,
    required this.profile,
    required this.repository,
    required this.guardiansRepository,
    this.readOnly = false,
  });

  final Profile profile;
  final CareContentRepository repository;
  final ProfileGuardiansRepository guardiansRepository;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('care-notes-button'),
      tooltip: 'Care notes & visit prep',
      icon: const Icon(Icons.medical_information_outlined),
      onPressed: () => Navigator.of(context).push(
        buildNamedRoute<void>(
          name: kRouteCareNotesScreen,
          builder: (_) => CareNotesScreen(
            profile: profile,
            repository: repository,
            guardiansRepository: guardiansRepository,
            readOnly: readOnly,
          ),
        ),
      ),
    );
  }
}
