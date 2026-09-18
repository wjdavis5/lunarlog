/// The life-stage-mode exit exclusion offer (Issues #192 Pregnancy and #455
/// Postpartum): leaving a mode that pauses prediction prompts to exclude
/// the mode's interval from cycle averages — the data-integrity half of
/// both issues (a pregnancy or a postpartum stretch left in the record
/// poisons the averages the next ordinary cycles are measured against,
/// with no in-app correction otherwise).
///
/// One implementation serves both modes (the interval math and the write
/// path are identical); only the copy, the dialog route name, and which
/// [intervalExclusionStarts] wrapper is consulted differ. The pregnancy
/// call site is `profile_picker_screen.dart`'s mode-edit exit; the
/// postpartum call sites are that same edit exit and the overview's
/// cycles-have-returned offer.
///
/// * **Accepting** writes one `cycle_overrides` row per cycle *start*
///   inside `[modeStartedOn, exitedOn)` (`excluded_from_average = true`)
///   through the same `CycleExclusionList.omit` seam the history list's
///   own omit toggle uses — the #188 schema is keyed by single
///   cycle-start dates (#132's consumption mechanism), so "spanning the
///   interval" is realized as one exclusion row per start inside it; the
///   half-open bound deliberately keeps a period starting exactly on the
///   exit date (the first real cycle after the mode) out of the
///   exclusion. See `intervalExclusionStarts` for the full rationale.
/// * **Declining** writes nothing: the long apparent "cycle" is already
///   auto-flagged as an outlier by the 15–60 validity window in cycle
///   history, and every cycle stays individually excludable later
///   through the history list's omit toggle.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/postpartum.dart' show postpartumExclusionStarts;
import 'package:lunarlog/domain/prediction/cycle_history.dart'
    show CycleExclusionList;
import 'package:lunarlog/domain/pregnancy.dart' show pregnancyExclusionStarts;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';

/// The outcome of offering the exclusion: [accepted] is true when the
/// operator chose to exclude (the rows are written before this returns),
/// false when declined or when nothing was offerable (no recorded
/// `modeStartedOn`, no episodes inside the interval, an unsupported mode,
/// or a read-only caller).
class ModeExitExclusionOutcome {
  const ModeExitExclusionOutcome({required this.accepted});

  final bool accepted;
}

/// The mode-specific surface of the offer: localized copy, the dialog route
/// name, and the per-mode value key prefix (`<mode>-exit-exclusion-*`) so
/// #192's existing pregnancy keys and #455's postpartum keys stay stable
/// and independently testable.
class _ModeExitCopy {
  const _ModeExitCopy({
    required this.title,
    required this.body,
    required this.accept,
    required this.decline,
    required this.done,
    required this.routeName,
    required this.keyPrefix,
  });

  final String title;
  final String body;
  final String accept;
  final String decline;
  final String done;
  final String routeName;
  final String keyPrefix;

  static _ModeExitCopy? forMode(AppLocalizations l10n, LifecycleMode mode) =>
      switch (mode) {
        LifecycleMode.pregnancy => _ModeExitCopy(
            title: l10n.pregnancyExitExclusionTitle,
            body: l10n.pregnancyExitExclusionBody,
            accept: l10n.pregnancyExitExclusionAccept,
            decline: l10n.pregnancyExitExclusionDecline,
            done: l10n.pregnancyExitExclusionDone,
            routeName: kRoutePregnancyExitExclusionDialog,
            keyPrefix: 'pregnancy',
          ),
        LifecycleMode.postpartum => _ModeExitCopy(
            title: l10n.postpartumExitExclusionTitle,
            body: l10n.postpartumExitExclusionBody,
            accept: l10n.postpartumExitExclusionAccept,
            decline: l10n.postpartumExitExclusionDecline,
            done: l10n.postpartumExitExclusionDone,
            routeName: kRoutePostpartumExitExclusionDialog,
            keyPrefix: 'postpartum',
          ),
        // Conceive/tracking/perimenopause have no discrete span to exclude;
        // the offer is a no-op rather than a guessed interval.
        _ => null,
      };
}

/// The cycle-start dates to write for [exitedMode]'s interval — routed
/// through each mode's own domain wrapper so the intent stays named even
/// though both delegate to the same shared helper.
Set<LocalDate> _exclusionStartsFor({
  required LifecycleMode exitedMode,
  required Iterable<Episode> episodes,
  required LocalDate? modeStartedOn,
  required LocalDate exitedOn,
}) =>
    switch (exitedMode) {
      LifecycleMode.pregnancy => pregnancyExclusionStarts(
          episodes: episodes,
          modeStartedOn: modeStartedOn,
          exitedOn: exitedOn,
        ),
      LifecycleMode.postpartum => postpartumExclusionStarts(
          episodes: episodes,
          modeStartedOn: modeStartedOn,
          exitedOn: exitedOn,
        ),
      _ => const <LocalDate>{},
    };

/// Shows the offer and performs the writes when accepted. [modeStartedOn]
/// is the exited mode's `mode_started_on` as it stood *before* the mode
/// switch is applied (the interval's start); [exitedOn] is the date the
/// mode moved off [exitedMode] (today at the switch). Pure inputs
/// ([bleedDates]) keep this testable without a repository.
Future<ModeExitExclusionOutcome> offerModeExitExclusion(
  BuildContext context, {
  required LifecycleMode exitedMode,
  required String? modeStartedOn,
  required LocalDate exitedOn,
  required List<LocalDate> bleedDates,
  required CycleExclusionList exclusions,
  required String profileId,
  required bool readOnly,
}) async {
  final copy = _ModeExitCopy.forMode(AppLocalizations.of(context), exitedMode);
  final startedOn = modeStartedOn == null || modeStartedOn.isEmpty
      ? null
      : _tryParseIso(modeStartedOn);
  final starts = _exclusionStartsFor(
    exitedMode: exitedMode,
    episodes: deriveEpisodes(bleedDates),
    modeStartedOn: startedOn,
    exitedOn: exitedOn,
  );
  // Nothing inside the interval to exclude (or an unstamped mode, or a
  // mode with no discrete span): the dialog has nothing honest to offer —
  // the auto-outlier flag and the history list's per-cycle toggle still
  // cover it.
  if (copy == null || starts.isEmpty || readOnly) {
    return const ModeExitExclusionOutcome(accepted: false);
  }
  final accepted = await showDialog<bool>(
        context: context,
        routeSettings: RouteSettings(name: copy.routeName),
        builder: (dialogContext) => AlertDialog(
          title: Text(copy.title),
          content: SingleChildScrollView(
            child: Text(copy.body),
          ),
          actions: [
            TextButton(
              key: ValueKey('${copy.keyPrefix}-exit-exclusion-decline'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.decline),
            ),
            FilledButton(
              key: ValueKey('${copy.keyPrefix}-exit-exclusion-accept'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(copy.accept),
            ),
          ],
        ),
      ) ??
      false;
  if (!accepted) {
    return const ModeExitExclusionOutcome(accepted: false);
  }
  for (final start in starts) {
    await exclusions.omit(profileId, start);
  }
  return const ModeExitExclusionOutcome(accepted: true);
}

/// Convenience wrapper resolving the seams from [context] (all optional:
/// a tree without the exclusion seam or the entries repository simply
/// never offers the dialog — the exact pre-#192 behavior) and surfacing
/// the completion snackbar on accept.
Future<void> offerModeExitExclusionFromTree(
  BuildContext context, {
  required LifecycleMode exitedMode,
  required String profileId,
  required String? modeStartedOn,
}) async {
  final copy = _ModeExitCopy.forMode(AppLocalizations.of(context), exitedMode);
  if (copy == null) return;
  final exclusions = _maybeRead<CycleExclusionList>(context);
  final entries = _maybeRead<DayEntriesRepository>(context);
  if (exclusions == null || entries == null) return;
  final bleedDates = await _bleedDatesFor(entries, profileId);
  if (!context.mounted) return;
  final outcome = await offerModeExitExclusion(
    context,
    exitedMode: exitedMode,
    modeStartedOn: modeStartedOn,
    exitedOn: LocalDate.today(),
    bleedDates: bleedDates,
    exclusions: exclusions,
    profileId: profileId,
    readOnly: false,
  );
  if (!context.mounted || !outcome.accepted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        copy.done,
        key: ValueKey('${copy.keyPrefix}-exit-exclusion-snackbar'),
      ),
    ),
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T?>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The profile's live bleed dates (the same `bleedDatesOf` filter
/// episode derivation itself uses — tombstone-checked and bleed-only).
Future<List<LocalDate>> _bleedDatesFor(
  DayEntriesRepository repository,
  String profileId,
) async {
  final entries = await repository.listForProfile(profileId);
  return bleedDatesOf(entries).toList();
}

LocalDate? _tryParseIso(String iso) {
  try {
    return LocalDate.fromIso(iso);
  } on ArgumentError {
    return null;
  }
}
