/// The day sheet's "Notes from guardians" section (Issue #801).
///
/// One dated, author-scoped note per guardian, added *beside* the shared day
/// note — never a rework of it. A guardian sees every note for the day (the
/// visibility rule from issue #800: open and transparent), can edit or
/// remove only her own, and — critically — is told who can read what she is
/// about to write, at the point of writing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../domain/limits.dart';
import '../../domain/models/guardian_note.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/repositories/guardian_notes_repository.dart';
import '../theme/tokens.dart';

/// The disclosure that MUST sit beside every guardian-note input the app
/// ever renders (issue #801, ratifying issue #800's "open and transparent"
/// decision). Transparency nobody is told about is indistinguishable from
/// privacy that does not exist.
const String kGuardianNotesDisclosure =
    'Anyone with access to this profile can read this note — including the '
    'person it is about.';

/// The same rule, worded for the standing care-notes surface.
const String kCareNotesDisclosure =
    'Anyone with access to this profile can read these notes — including '
    'the person they are about.';

class GuardianNotesSection extends StatefulWidget {
  const GuardianNotesSection({
    super.key,
    required this.profileId,
    required this.date,
    required this.tz,
    this.currentUserId,
    this.guardians = const [],
    this.canWrite = true,
    this.repository,
  });

  final String profileId;
  final LocalDate date;

  /// IANA zone the note is stamped with (the author's day).
  final String tz;

  /// The bound account, used to pick out this author's own note (and to
  /// decide editability). Null for a never-synced local-only operator.
  final String? currentUserId;

  /// Accepted guardians, for display attribution. Never a permission source
  /// here — [canWrite] carries that, derived by the caller from the same
  /// role ladder.
  final List<ProfileGuardian> guardians;

  /// Whether the caller may write. The caller derives this with the existing
  /// `acceptedGuardianFor(...).role.canLog` ladder — this widget does not
  /// re-derive, and renders read-only when false (a viewer).
  final bool canWrite;

  /// Injected seam for tests; defaults to the ambient provider.
  final GuardianNotesRepository? repository;

  @override
  State<GuardianNotesSection> createState() => _GuardianNotesSectionState();
}

class _GuardianNotesSectionState extends State<GuardianNotesSection> {
  final TextEditingController _controller = TextEditingController();
  String? _adoptedId;
  bool _seeding = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GuardianNotesRepository? _repo(BuildContext context) =>
      widget.repository ??
      Provider.of<GuardianNotesRepository?>(context, listen: false);

  String _authorName(String? userId) {
    if (userId == null) return 'Guardian';
    if (widget.currentUserId != null && userId == widget.currentUserId) {
      return 'You';
    }
    final match = widget.guardians.cast<ProfileGuardian?>().firstWhere(
          (g) => g?.userId == userId,
          orElse: () => null,
        );
    final name = match?.displayName;
    return (name != null && name.isNotEmpty) ? name : 'Guardian';
  }

  /// Adopts the author's own existing note into the editor the first time it
  /// appears (typically after the initial local read or a pull), without
  /// clobbering text the user has already started typing.
  void _adopt(GuardianNote own) {
    if (_adoptedId == own.id) return;
    _adoptedId = own.id;
    if (!_seeding && _controller.text.trim().isEmpty) {
      _seeding = true;
      _controller.text = own.body;
      _seeding = false;
    }
  }

  Future<void> _save(GuardianNote? own) async {
    final repo = _repo(context);
    final body = _controller.text.trim();
    if (repo == null || body.isEmpty) return;
    setState(() => _saving = true);
    try {
      await repo.save(
        id: own?.id,
        profileId: widget.profileId,
        localDate: widget.date,
        tz: widget.tz,
        body: body,
        loggedByUserId: widget.currentUserId,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(GuardianNote own) async {
    final repo = _repo(context);
    if (repo == null) return;
    await repo.delete(own.id);
    _adoptedId = null;
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo(context);
    if (repo == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<GuardianNote>>(
      stream: repo.watchForProfile(widget.profileId),
      builder: (context, snapshot) {
        final notes = [
          for (final note in snapshot.data ?? const <GuardianNote>[])
            if (note.localDate == widget.date) note,
        ];
        // Issue #871: a second own note must never be silently dropped. The
        // newest own note becomes the editable one; every older own note is
        // rendered as a plain row exactly like another guardian's note. A
        // viewer's own note (she may have written it before a role change)
        // is also rendered as a plain row, since she has no editor. The
        // partition lives in [_partitionOwnNotes] to keep this method's
        // cyclomatic complexity (and its CRAP score) under the gate.
        final (own, rowNotes) = _partitionOwnNotes(notes);
        // Adopt the author's own note into the editor once, only when it is
        // not already adopted — an unconditional post-frame setState here
        // would rebuild, schedule another callback, and never settle.
        if (own != null && _adoptedId != own.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _adopt(own));
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: LLSpace.space4),
            Text(l10n.guardianNotesSectionTitle,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: LLSpace.space1),
            Text(
              kGuardianNotesDisclosure,
              key: const ValueKey('guardian-notes-disclosure'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: LLSpace.space2),
            if (widget.canWrite) _ownEditor(theme, own),
            for (final note in rowNotes) _noteRow(theme, note),
            if (!widget.canWrite && rowNotes.isEmpty)
              Text(l10n.guardianNotesEmpty,
                  style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }

  /// Splits the day's notes into the author's editable [own] note (the
  /// newest one, or null) and the plain [rowNotes] to render beneath the
  /// editor — every other author's note, every older own note, and (for a
  /// viewer) her own note too, since she has no editor.
  (GuardianNote?, List<GuardianNote>) _partitionOwnNotes(
    List<GuardianNote> notes,
  ) {
    GuardianNote? own;
    final rows = <GuardianNote>[];
    for (final note in notes) {
      // An exact author match is "mine" — including a null author for a
      // never-synced local-only operator (currentUserId null), whose note
      // the server has not stamped yet.
      if (note.loggedByUserId != widget.currentUserId) {
        rows.add(note);
        continue;
      }
      if (own == null || _isNewer(note, own)) {
        if (own != null) rows.add(own);
        own = note;
      } else {
        rows.add(note);
      }
    }
    if (!widget.canWrite && own != null) rows.add(own);
    return (own, rows);
  }

  /// Whether [a] should be the editable own note over [b]: later write
  /// first, id as the deterministic tie-break (ULIDs sort chronologically).
  static bool _isNewer(GuardianNote a, GuardianNote b) {
    final byTime = a.updatedAt.compareTo(b.updatedAt);
    if (byTime != 0) return byTime > 0;
    return a.id.compareTo(b.id) > 0;
  }

  Widget _ownEditor(ThemeData theme, GuardianNote? own) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Attribution for your own entry, mirroring the read-only rows'
        // author label so the list reads consistently.
        Text(l10n.guardianNotesYou, style: theme.textTheme.labelMedium),
        const SizedBox(height: LLSpace.space1),
        TextFormField(
          key: const ValueKey('guardian-note-field'),
          controller: _controller,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Your note for this day',
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          textInputAction: TextInputAction.newline,
          maxLength: kMaxCareNoteLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (own != null)
              TextButton(
                key: const ValueKey('guardian-note-remove'),
                onPressed: _saving ? null : () => _remove(own),
                child: Text(l10n.guardianNotesRemove),
              ),
            const SizedBox(width: LLSpace.space2),
            FilledButton(
              key: const ValueKey('guardian-note-save'),
              onPressed: _saving ? null : () => _save(own),
              child: Text(own == null
                  ? l10n.guardianNotesAdd
                  : l10n.guardianNotesUpdate),
            ),
          ],
        ),
      ],
    );
  }

  Widget _noteRow(ThemeData theme, GuardianNote note) {
    return Padding(
      key: ValueKey('guardian-note-${note.id}'),
      padding: const EdgeInsets.only(top: LLSpace.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_authorName(note.loggedByUserId),
              style: theme.textTheme.labelMedium),
          const SizedBox(height: LLSpace.space1),
          Text(note.body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
