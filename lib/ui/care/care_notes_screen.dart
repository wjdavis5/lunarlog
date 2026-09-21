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

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/logistics/restock_nudge.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show ActivePrediction, CyclePrediction;
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/care/guardian_notes_section.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/components/list_section_header.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/sharing/guardian_watch_mixin.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

/// Formats an instant as a bare, locale-aware civil date (issue #554 --
/// was a hand-rolled, always `YYYY-MM-DD` string) for the attribution
/// line. Time-of-day is not shown: "who and roughly when" is the whole
/// contract, and a date keeps the copy stable across zones.
String careAttributionDate(BuildContext context, DateTime instant) => dates
    .formatShortDate(instant.toLocal(), locale: dates.calendarLocale(context));

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
  late final Stream<List<VisitPrepItem>> _supplyStream;
  late final Stream<List<ProfileGuardian>> _guardiansStream;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _supplyController = TextEditingController();
  String? _currentUserId;
  AuthController? _auth;
  StreamSubscription<CyclePrediction>? _predictionSub;

  /// Issue #851: the profile's next estimated period start, feeding the
  /// restock nudge. Null when predictions are unavailable (no service in
  /// the tree, insufficient history, or suppressed) — [restockNudgeFor]
  /// never guesses a date from null.
  LocalDate? _estimatedNextStart;
  bool _savingNote = false;
  bool _savingItem = false;
  bool _savingSupply = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notesStream = widget.repository.watchCareNotes(widget.profile.id);
    _prepStream = widget.repository.watchPrepItems(widget.profile.id);
    _supplyStream = widget.repository.watchSupplyItems(widget.profile.id);
    _guardiansStream = watchGuardiansForProfileSafely(
      widget.guardiansRepository,
      widget.profile.id,
    );
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    final predictionService = context.read<CyclePredictionService?>();
    if (predictionService != null) {
      _predictionSub = predictionService.watch(widget.profile.id).listen(
        _onPrediction,
      );
    }
  }

  void _onPrediction(CyclePrediction prediction) {
    final start =
        prediction is ActivePrediction ? prediction.estimatedNextStart : null;
    if (mounted && start != _estimatedNextStart) {
      setState(() => _estimatedNextStart = start);
    }
  }

  @override
  void dispose() {
    unawaited(_predictionSub?.cancel());
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    _noteController.dispose();
    _itemController.dispose();
    _supplyController.dispose();
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
      appBar: AppBar(
          title: Text(AppLocalizations.of(context)
              .careNotesTitle(widget.profile.displayName))),
      body: StreamBuilder<List<ProfileGuardian>>(
        stream: _guardiansStream,
        builder: (context, guardiansSnapshot) {
          final l10n = AppLocalizations.of(context);
          final guardians = guardiansSnapshot.data ?? const [];
          final viewerReadOnly =
              acceptedGuardianFor(guardians, _currentUserId)?.role.canLog ==
              false;
          final effectiveReadOnly = widget.readOnly || viewerReadOnly;
          final viewerGuardianRole = acceptedGuardianFor(
            guardians,
            _currentUserId,
          )?.role;
          final readOnlyReason = widget.readOnly
              ? l10n.careNotesReadOnlyArchived
              : viewerGuardianRole == null
              ? null
              : guardianRoleReadOnlyReason(
                  AppLocalizations.of(context),
                  viewerGuardianRole,
                );
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
                  // #555: null onRetry -- this banner is shared across six
                  // different mutations (add/delete note, add/toggle/delete
                  // prep item, clear checked), so there is no single action
                  // to retry; each row's own control is the retry surface.
                  child: InlineError(
                    key: const ValueKey('care-error'),
                    message: _error!,
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
              const SizedBox(height: 24),
              _SuppliesSection(
                supplyStream: _supplyStream,
                guardians: guardians,
                currentUserId: _currentUserId,
                canWrite: !effectiveReadOnly,
                controller: _supplyController,
                saving: _savingSupply,
                estimatedNextStart: _estimatedNextStart,
                today: LocalDate.today(),
                onAdd: _addSupply,
                onToggle: _toggleItem,
                onDelete: _deleteItem,
                onClearChecked: _clearCheckedSupplies,
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
        setState(() => _error =
            AppLocalizations.of(context).careNotesSaveError);
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
        setState(() => _error =
            AppLocalizations.of(context).careNotesAddPrepError);
      }
    } finally {
      if (mounted) setState(() => _savingItem = false);
    }
  }

  Future<void> _addSupply() async {
    final body = _supplyController.text.trim();
    if (body.isEmpty || _savingSupply) return;
    setState(() {
      _savingSupply = true;
      _error = null;
    });
    try {
      await widget.repository.addPrepItem(
        profileId: widget.profile.id,
        body: body,
        kind: VisitPrepItemKind.supply,
      );
      _supplyController.clear();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context).careNotesAddSupplyError);
      }
    } finally {
      if (mounted) setState(() => _savingSupply = false);
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
        setState(() => _error =
            AppLocalizations.of(context).careNotesUpdatePrepError);
      }
    }
  }

  Future<void> _deleteItem(VisitPrepItem item) async {
    setState(() => _error = null);
    try {
      await widget.repository.deletePrepItem(item.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context).careNotesRemovePrepError);
      }
    }
  }

  /// #553: a care note is a shared, multi-guardian record — any accepted
  /// guardian can see (and, before this fix, one mistap could destroy)
  /// text another guardian wrote. A confirmation matches the destructive-
  /// action pattern used elsewhere (e.g. `profile_dialogs.dart`'s archive
  /// confirm, `manage_guardians_screen.dart`'s remove/cancel confirms).
  Future<void> _deleteNote(CareNote note) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.careNotesDeleteTitle),
        content: Text(l10n.careNotesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.careNotesDeleteCancel),
          ),
          FilledButton(
            key: const ValueKey('care-note-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.careNotesDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _error = null);
    try {
      await widget.repository.deleteCareNote(note.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context).careNotesRemoveNoteError);
      }
    }
  }

  Future<void> _clearChecked() async {
    setState(() => _error = null);
    try {
      await widget.repository.clearCheckedPrepItems(widget.profile.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context).careNotesClearCheckedError);
      }
    }
  }

  Future<void> _clearCheckedSupplies() async {
    setState(() => _error = null);
    try {
      await widget.repository.clearCheckedPrepItems(
        widget.profile.id,
        kind: VisitPrepItemKind.supply,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context).careNotesClearStockedError);
      }
    }
  }
}

/// Resolves [userId] to display copy for the "Checked by" line, mirroring
/// [CaregiverAttributionBadge]'s naming ("you" for the current operator,
/// the guardian's display name when known, the role label, "Guardian" as
/// the fallback) — never a raw uuid (the activity-feed precedent).
String careActorCopy(
  AppLocalizations l10n,
  String? userId,
  List<ProfileGuardian> guardians,
  String? currentUserId,
) {
  if (userId != null) {
    if (userId == currentUserId) return l10n.careNotesActorYou;
    final guardian = _guardianFor(userId, guardians);
    if (guardian != null) {
      final name = guardian.displayName;
      return (name == null || name.isEmpty)
          ? guardianRoleLabel(l10n, guardian.role)
          : name;
    }
  }
  return l10n.careNotesActorGuardian;
}

/// The guardian row for [userId], or null when no row matches. Split out
/// of [careActorCopy] so neither method carries the lookup and the naming
/// branches together under the CRAP gate.
ProfileGuardian? _guardianFor(String userId, List<ProfileGuardian> guardians) {
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionHeader(
          title: l10n.careNotesSectionTitle,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, LLSpace.space2),
        ),
        StreamBuilder<List<CareNote>>(
          stream: notesStream,
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const [];
            if (notes.isEmpty) {
              return Text(
                l10n.careNotesEmpty,
                key: const ValueKey('care-notes-empty'),
              );
            }
            return Card(
              key: const ValueKey('care-notes-card'),
              child: Column(
                children: [
                  for (var i = 0; i < notes.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _CareNoteRow(
                      key: ValueKey('care-note-${notes[i].id}'),
                      note: notes[i],
                      guardians: guardians,
                      currentUserId: currentUserId,
                      canWrite: canWrite,
                      onDelete: onDelete,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        if (canWrite) ...[
          const SizedBox(height: 8),
          // Issue #800/#801: the writer is told who can read this, at the
          // point of writing.
          Text(
            kCareNotesDisclosure,
            key: const ValueKey('care-notes-disclosure'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('care-note-field'),
            controller: controller,
            maxLength: kMaxCareNoteLength,
            maxLines: 3,
            minLines: 1,
            // #165: multiline — the honest keyboard action is "newline"
            // (a "done" action would steal the enter key from line
            // breaks).
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: l10n.careNotesAddLabel,
              hintText: l10n.careNotesAddHint,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('care-note-add'),
              onPressed: saving ? null : onAdd,
              child: Text(l10n.careNotesAddButton),
            ),
          ),
        ],
      ],
    );
  }
}

class _CareNoteRow extends StatelessWidget {
  const _CareNoteRow({
    super.key,
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
    final hasAttribution =
        note.loggedByUserId != null || note.lastModifiedByUserId != null;
    return ListTile(
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
            careAttributionDate(context, note.updatedAt),
            key: ValueKey('care-note-by-${note.id}'),
          ),
        ],
      ),
      trailing: canWrite
          ? IconButton(
              key: ValueKey('care-note-delete-${note.id}'),
              tooltip: AppLocalizations.of(context).careNotesRemoveNoteTooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onDelete(note),
            )
          : null,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionHeader(
          title: l10n.careVisitPrepSectionTitle,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, LLSpace.space2),
        ),
        StreamBuilder<List<VisitPrepItem>>(
          stream: prepStream,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return Text(
                l10n.careVisitPrepEmpty,
                key: const ValueKey('visit-prep-empty'),
              );
            }
            final checkedCount = items.where((i) => i.isChecked).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  key: const ValueKey('visit-prep-card'),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _VisitPrepRow(
                          key: ValueKey('visit-prep-${items[i].id}'),
                          item: items[i],
                          guardians: guardians,
                          currentUserId: currentUserId,
                          canWrite: canWrite,
                          onToggle: onToggle,
                          onDelete: onDelete,
                          checkedVerb: l10n.careVisitPrepCheckedVerb,
                        ),
                      ],
                    ],
                  ),
                ),
                if (canWrite && checkedCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('visit-prep-clear-checked'),
                      onPressed: onClearChecked,
                      child: Text(l10n.careVisitPrepClearChecked(checkedCount)),
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
            // #165: single-line — "done" is the Add item action (guarded
            // exactly like the button below).
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!saving) unawaited(onAdd());
            },
            decoration: InputDecoration(
              labelText: l10n.careVisitPrepAddLabel,
              hintText: l10n.careVisitPrepAddHint,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('visit-prep-add'),
              onPressed: saving ? null : onAdd,
              child: Text(l10n.careVisitPrepAddButton),
            ),
          ),
        ],
      ],
    );
  }
}

class _VisitPrepRow extends StatelessWidget {
  const _VisitPrepRow({
    super.key,
    required this.item,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.onToggle,
    required this.onDelete,
    this.keyPrefix = 'visit-prep',
    required this.checkedVerb,
  });

  final VisitPrepItem item;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final Future<void> Function(VisitPrepItem item, bool checked) onToggle;
  final Future<void> Function(VisitPrepItem item) onDelete;

  /// Widget-key prefix, so the supplies list (Issue #851) reuses this row
  /// without colliding with the visit-prep keys in a test or semantics tree.
  final String keyPrefix;

  /// The attribution line's verb: "Checked by" for prep items, "Stocked by"
  /// for supply items.
  final String checkedVerb;

  @override
  Widget build(BuildContext context) {
    final checkedBy = item.isChecked
        ? careActorCopy(
            AppLocalizations.of(context),
            item.checkedByUserId,
            guardians,
            currentUserId,
          )
        : null;
    return CheckboxListTile(
      key: ValueKey('$keyPrefix-check-${item.id}'),
      value: item.isChecked,
      onChanged: canWrite
          ? (checked) => onToggle(item, checked ?? false)
          : null,
      title: Text(item.body),
      subtitle: checkedBy == null
          ? null
          : Text(
              '$checkedVerb $checkedBy',
              key: ValueKey('$keyPrefix-checked-by-${item.id}'),
            ),
      secondary: canWrite
          ? IconButton(
              key: ValueKey('$keyPrefix-delete-${item.id}'),
              tooltip: AppLocalizations.of(context).careNotesRemoveItemTooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onDelete(item),
            )
          : null,
    );
  }
}

/// Issue #851: the profile's household supplies list — a `kind == supply`
/// view over the same checklist substrate the visit-prep section uses. The
/// list lives on the profile and is visible to every guardian, including
/// the subject.
class _SuppliesSection extends StatelessWidget {
  const _SuppliesSection({
    required this.supplyStream,
    required this.guardians,
    required this.currentUserId,
    required this.canWrite,
    required this.controller,
    required this.saving,
    required this.estimatedNextStart,
    required this.today,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onClearChecked,
  });

  final Stream<List<VisitPrepItem>> supplyStream;
  final List<ProfileGuardian> guardians;
  final String? currentUserId;
  final bool canWrite;
  final TextEditingController controller;
  final bool saving;
  final LocalDate? estimatedNextStart;
  final LocalDate today;
  final Future<void> Function() onAdd;
  final Future<void> Function(VisitPrepItem item, bool checked) onToggle;
  final Future<void> Function(VisitPrepItem item) onDelete;
  final Future<void> Function() onClearChecked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionHeader(
          title: l10n.careSuppliesSectionTitle,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, LLSpace.space2),
        ),
        StreamBuilder<List<VisitPrepItem>>(
          stream: supplyStream,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            final nudge = restockNudgeFor(
              supplies: items,
              estimatedNextStart: estimatedNextStart,
              today: today,
            );
            final stockedCount = items.where((i) => i.isChecked).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (nudge != null) _RestockNudgeBanner(nudge: nudge),
                if (items.isEmpty)
                  Text(
                    l10n.careSuppliesEmpty,
                    key: const ValueKey('supplies-empty'),
                  )
                else
                  Card(
                    key: const ValueKey('supplies-card'),
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _VisitPrepRow(
                            key: ValueKey('supply-${items[i].id}'),
                            item: items[i],
                            guardians: guardians,
                            currentUserId: currentUserId,
                            canWrite: canWrite,
                            onToggle: onToggle,
                            onDelete: onDelete,
                            keyPrefix: 'supply',
                            checkedVerb: l10n.careSuppliesStockedVerb,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (canWrite && stockedCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('supplies-clear-stocked'),
                      onPressed: onClearChecked,
                      child: Text(l10n.careSuppliesClearStocked(stockedCount)),
                    ),
                  ),
              ],
            );
          },
        ),
        if (canWrite) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('supplies-field'),
            controller: controller,
            maxLength: kMaxVisitPrepItemLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!saving) unawaited(onAdd());
            },
            decoration: InputDecoration(
              labelText: l10n.careSuppliesAddLabel,
              hintText: l10n.careSuppliesAddHint,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('supplies-add'),
              onPressed: saving ? null : onAdd,
              child: Text(l10n.careSuppliesAddButton),
            ),
          ),
        ],
      ],
    );
  }
}

/// Issue #851: the in-app restock nudge derived by [restockNudgeFor]. It is
/// not a notification — it names the profile's own items and the estimate
/// date, which is exactly what an in-app card may do (the outbox/push copy
/// stays content-free and is a separate, unbuilt concern).
class _RestockNudgeBanner extends StatelessWidget {
  const _RestockNudgeBanner({required this.nudge});

  final RestockNudge nudge;

  @override
  Widget build(BuildContext context) {
    final names = nudge.items.map((item) => item.body).join(', ');
    final date = dates.formatLocalDateMonthDayYear(
      nudge.dueBy,
      locale: dates.calendarLocale(context),
    );
    return Card(
      key: const ValueKey('supplies-restock-nudge'),
      child: ListTile(
        leading: const Icon(Icons.shopping_cart_outlined),
        title: Text(AppLocalizations.of(context).careRestockBefore(date)),
        subtitle: Text(names),
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
      tooltip: AppLocalizations.of(context).careNotesButtonTooltip,
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
