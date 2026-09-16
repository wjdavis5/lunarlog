/// The pregnancy-exit exclusion offer (Issue #192 AC4/AC5): leaving
/// Pregnancy mode prompts to exclude the pregnancy interval from cycle
/// averages — the parity-critical data-integrity half of the issue (the
/// Clue support article this issue cites exists because a pregnancy
/// poisons post-pregnancy averages with no in-app correction).
///
/// * **Accepting** writes one `cycle_overrides` row per cycle *start*
///   inside `[modeStartedOn, exitedOn)` (`excluded_from_average = true`)
///   through the same `CycleExclusionList.omit` seam the history list's
///   own omit toggle uses — the #188 schema is keyed by single
///   cycle-start dates (#132's consumption mechanism), so "spanning the
///   interval" is realized as one exclusion row per start inside it; the
///   half-open bound deliberately keeps a period starting exactly on the
///   exit date (the first real post-pregnancy cycle) out of the
///   exclusion. See `pregnancyExclusionStarts` for the full rationale.
/// * **Declining** writes nothing: the long pregnancy "cycle" is already
///   auto-flagged as an outlier by the 15–60 validity window in cycle
///   history, and every cycle stays individually excludable later
///   through the history list's omit toggle (AC5's "flagged as a
///   candidate outlier ... for later exclusion").
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart'
    show CycleExclusionList;
import 'package:lunarlog/domain/pregnancy.dart' show pregnancyExclusionStarts;
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';

/// The outcome of offering the exclusion: [accepted] is true when the
/// operator chose to exclude (the rows are written before this returns),
/// false when declined or when nothing was offerable (no recorded
/// `modeStartedOn`, no episodes inside the interval, or a read-only
/// caller).
class PregnancyExitExclusionOutcome {
  const PregnancyExitExclusionOutcome({required this.accepted});

  final bool accepted;
}

/// Shows the offer and performs the writes when accepted. [modeStartedOn]
/// is the pregnancy row's `mode_started_on` as it stood *before* the mode
/// switch is applied (the interval's start); [exitedOn] is the date the
/// mode moved off pregnancy (today at the switch). Pure inputs
/// ([bleedDates]) keep this testable without a repository.
Future<PregnancyExitExclusionOutcome> offerPregnancyExitExclusion(
  BuildContext context, {
  required String? modeStartedOn,
  required LocalDate exitedOn,
  required List<LocalDate> bleedDates,
  required CycleExclusionList exclusions,
  required String profileId,
  required bool readOnly,
}) async {
  final l10n = AppLocalizations.of(context);
  final startedOn =
      modeStartedOn == null || modeStartedOn.isEmpty ? null : _tryParseIso(modeStartedOn);
  final starts = pregnancyExclusionStarts(
    episodes: deriveEpisodes(bleedDates),
    modeStartedOn: startedOn,
    exitedOn: exitedOn,
  );
  // Nothing inside the interval to exclude (or an unstamped pregnancy
  // entered before this issue): the dialog has nothing honest to offer —
  // the auto-outlier flag and the history list's per-cycle toggle still
  // cover AC5.
  if (starts.isEmpty || readOnly) {
    return const PregnancyExitExclusionOutcome(accepted: false);
  }
  final accepted = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(
          name: kRoutePregnancyExitExclusionDialog,
        ),
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.pregnancyExitExclusionTitle),
          content: SingleChildScrollView(
            child: Text(l10n.pregnancyExitExclusionBody),
          ),
          actions: [
            TextButton(
              key: const ValueKey('pregnancy-exit-exclusion-decline'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.pregnancyExitExclusionDecline),
            ),
            FilledButton(
              key: const ValueKey('pregnancy-exit-exclusion-accept'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.pregnancyExitExclusionAccept),
            ),
          ],
        ),
      ) ??
      false;
  if (!accepted) {
    return const PregnancyExitExclusionOutcome(accepted: false);
  }
  for (final start in starts) {
    await exclusions.omit(profileId, start);
  }
  return const PregnancyExitExclusionOutcome(accepted: true);
}

/// Convenience wrapper resolving the seams from [context] (all optional:
/// a tree without the exclusion seam or the entries repository simply
/// never offers the dialog — the exact pre-#192 behavior) and surfacing
/// the completion snackbar on accept.
Future<void> offerPregnancyExitExclusionFromTree(
  BuildContext context, {
  required String profileId,
  required String? modeStartedOn,
}) async {
  final exclusions = _maybeRead<CycleExclusionList>(context);
  final entries = _maybeRead<DayEntriesRepository>(context);
  if (exclusions == null || entries == null) return;
  final bleedDates = await _bleedDatesFor(entries, profileId);
  if (!context.mounted) return;
  final outcome = await offerPregnancyExitExclusion(
    context,
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
        AppLocalizations.of(context).pregnancyExitExclusionDone,
        key: const ValueKey('pregnancy-exit-exclusion-snackbar'),
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
