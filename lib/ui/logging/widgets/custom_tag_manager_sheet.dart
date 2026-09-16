/// Issue #257: the custom-tag manager sheet — the create/rename/retire
/// surface the day sheet's tag picker opens. Minimal by design (the
/// brief's "minimal management UI in the tag picker"): one create field,
/// one list, and per-row rename/retire affordances.
///
/// Retirement is the primary lifecycle action and is deliberately NOT
/// styled destructive: it removes a code from the picker
/// (`hidden_at`) while every stored day-entry tag / observation row
/// referencing the code keeps rendering — Clue's
/// delete-destroys-history failure mode is structurally impossible here
/// (nothing in this sheet, the repository, or the server can delete a
/// stored reference), so the confirm dialog is a plain AlertDialog, not a
/// [DestructiveButton] flow.
///
/// Copy comes from [AppLocalizations] (`customTags*` keys), colors from
/// the ambient theme — no hardcoded strings, no bespoke palette.
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Opens the manager sheet over [repository]'s registry for [profileId].
Future<void> showCustomTagManagerSheet(
  BuildContext context, {
  required TagRegistryRepository repository,
  required String profileId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'CustomTagManagerSheet'),
      builder: (_) => CustomTagManagerSheet(
        repository: repository,
        profileId: profileId,
      ),
    );

/// Renders the create/rename field error for [error] against [l10n]
/// (Issue #257) — shared by the sheet's create field and the rename
/// dialog so the two surfaces can never drift apart on copy.
String customTagErrorText(AppLocalizations l10n, CustomTagLabelError error) =>
    switch (error) {
      CustomTagLabelError.empty => l10n.customTagsErrorEmpty,
      CustomTagLabelError.tooLong => l10n.customTagsErrorTooLong,
      CustomTagLabelError.noLettersOrDigits => l10n.customTagsErrorNoLetters,
      CustomTagLabelError.duplicateCode => l10n.customTagsErrorDuplicate,
      CustomTagLabelError.collidesWithTaxonomy => l10n.customTagsErrorTaxonomy,
    };

class CustomTagManagerSheet extends StatefulWidget {
  const CustomTagManagerSheet({
    super.key,
    required this.repository,
    required this.profileId,
  });

  final TagRegistryRepository repository;
  final String profileId;

  @override
  State<CustomTagManagerSheet> createState() => _CustomTagManagerSheetState();
}

class _CustomTagManagerSheetState extends State<CustomTagManagerSheet> {
  final TextEditingController _controller = TextEditingController();

  /// LIVE registry entries (tombstones excluded by the repository read),
  /// retired included — the manager lists retired rows with a status
  /// label so "where did my tag go" has an answer in-app.
  List<CustomTag> _tags = const [];
  StreamSubscription<List<CustomTag>>? _sub;
  CustomTagLabelError? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.repository
        .watchForProfile(widget.profileId)
        .listen((tags) {
      if (mounted) setState(() => _tags = tags);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _controller.dispose();
    super.dispose();
  }

  /// The manager's live count for the cap check: live-and-not-yet-retired
  /// rows (a retired row frees its slot in the picker, mirroring the
  /// server's own live-row count in `sync_push`).
  int get _offeredCount =>
      _tags.where((tag) => tag.offered).length;


  /// Validates the create field against the registry and the cap, then
  /// writes through the repository. Validation is caller-owned (the
  /// repository interface's own doc): a field-level error renders instead
  /// of a thrown ArgumentError.
  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final error = validateCustomTagLabel(_controller.text, _tags);
    if (error == null && _offeredCount >= kMaxCustomTagsPerProfile) {
      // The cap is not part of [CustomTagLabelError] (it is a count, not a
      // property of the label); the sheet owns it, exactly the way the
      // server's sync_push path does.
      setState(
          () => _capError = l10n.customTagsErrorCap(kMaxCustomTagsPerProfile));
      return;
    }
    if (_capError != null) setState(() => _capError = null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    try {
      await widget.repository.create(
        profileId: widget.profileId,
        label: _controller.text.trim(),
      );
      _controller.clear();
    } on ArgumentError {
      // A concurrent co-guardian write can invalidate the pre-check (a
      // same-code row landed between validation and insert) — the watched
      // list has already updated, so re-running the check against the
      // fresh registry reports it as an ordinary duplicate.
      if (!mounted) return;
      setState(() => _error =
          validateCustomTagLabel(_controller.text, _tags) ?? _error);
    }
  }

  /// Set when the only reason a create is refused is the per-profile cap;
  /// kept separately from [_error] because it is a count the sheet owns,
  /// not a [CustomTagLabelError] the domain model derives.
  String? _capError;

  /// Opens the rename dialog for [tag]. The registry list handed to
  /// [validateCustomTagLabel] excludes [tag] itself — a rename never
  /// changes the code, so the entry's own code must not read as a
  /// duplicate of itself.
  Future<void> _rename(CustomTag tag) async {
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameTagDialog(
        tag: tag,
        others: [for (final t in _tags) if (t.id != tag.id) t],
      ),
    );
    if (label == null) return;
    try {
      await widget.repository.rename(tagId: tag.id, label: label);
    } on ArgumentError {
      // A concurrent co-guardian write can invalidate the pre-check;
      // the watched list has already updated, so the next open of this
      // dialog reports the state honestly. Nothing to roll back.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.customTagsSheetTitle,
                  key: const ValueKey('custom-tags-title'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom-tag-create-field'),
                    controller: _controller,
                    maxLength: kMaxCustomTagLabelLength,
                    onSubmitted: (_) => _create(),
                    decoration: InputDecoration(
                      hintText: l10n.customTagsAddHint,
                      errorText: _error == null
                          ? _capError
                          : (_error == null ? null : customTagErrorText(l10n, _error!)),
                    ),
                    onChanged: (_) {
                      if (_error != null || _capError != null) {
                        setState(() {
                          _error = null;
                          _capError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('custom-tag-create'),
                  tooltip: l10n.customTagsAddTooltip,
                  icon: const Icon(Icons.add),
                  onPressed: _create,
                ),
              ],
            ),
            Flexible(
              child: _tags.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.customTagsEmptyList,
                        key: const ValueKey('custom-tags-empty'),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('custom-tags-list'),
                      shrinkWrap: true,
                      itemCount: _tags.length,
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        return ListTile(
                          key: ValueKey('custom-tag-row-${tag.code}'),
                          dense: true,
                          title: Text(
                            tag.displayName,
                            style: tag.offered
                                ? null
                                : theme.textTheme.bodyMedium?.copyWith(
                                    // #162: onSurfaceVariant is the
                                    // de-emphasised text role; outline is
                                    // a decorative-boundary role only.
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                          ),
                          trailing: tag.offered
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: ValueKey(
                                          'custom-tag-rename-${tag.code}'),
                                      tooltip: l10n.customTagsRenameTooltip,
                                      icon: const Icon(Icons.edit_outlined),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _rename(tag),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                          'custom-tag-retire-${tag.code}'),
                                      tooltip: l10n.customTagsRetireTooltip,
                                      icon:
                                          const Icon(Icons.visibility_off_outlined),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _retire(tag),
                                    ),
                                  ],
                                )
                              : Text(
                                  l10n.customTagsRetiredLabel,
                                  key: ValueKey(
                                      'custom-tag-retired-${tag.code}'),
                                  style: theme.textTheme.labelSmall,
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the retire confirmation for [tag], then writes `hidden_at`
  /// through the repository. Plain (non-destructive) styling: retirement
  /// deletes nothing — see the library doc.
  Future<void> _retire(CustomTag tag) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.customTagsRetireTitle(tag.displayName)),
        content: Text(l10n.customTagsRetireBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.daySheetCancel),
          ),
          TextButton(
            key: const ValueKey('custom-tag-retire-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.customTagsRetireConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.retire(tag.id);
  }
}

/// The rename dialog (Issue #257) — a [StatefulWidget] so the field's
/// controller is owned by the dialog's own element and disposed only
/// when the route's exit animation finishes removing it (a controller
/// disposed from the caller, right after `showDialog` resolves, dies
/// under the still-animating route and throws). Pops with the validated
/// trimmed label, or null on cancel.
class _RenameTagDialog extends StatefulWidget {
  const _RenameTagDialog({required this.tag, required this.others});

  final CustomTag tag;

  /// The registry excluding [tag] itself — a rename never changes the
  /// code, so the entry's own code must not read as a duplicate of
  /// itself.
  final List<CustomTag> others;

  @override
  State<_RenameTagDialog> createState() => _RenameTagDialogState();
}

class _RenameTagDialogState extends State<_RenameTagDialog> {
  late final TextEditingController _controller;
  CustomTagLabelError? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.tag.displayName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CustomTagLabelError? _validate() =>
      validateCustomTagLabel(_controller.text, widget.others);

  void _submit() {
    if (_validate() != null) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.customTagsRenameTitle),
      content: TextField(
        key: const ValueKey('custom-tag-rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: kMaxCustomTagLabelLength,
        decoration: InputDecoration(
          hintText: l10n.customTagsAddHint,
          errorText:
              _error == null ? null : customTagErrorText(l10n, _error!),
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) {
          final next = _validate();
          if (next != null) {
            setState(() => _error = next);
            return;
          }
          _submit();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.daySheetCancel),
        ),
        TextButton(
          key: const ValueKey('custom-tag-rename-save'),
          onPressed: () {
            final next = _validate();
            if (next != null) {
              setState(() => _error = next);
              return;
            }
            _submit();
          },
          child: Text(l10n.daySheetSave),
        ),
      ],
    );
  }
}
