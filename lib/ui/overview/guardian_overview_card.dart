/// The guardian logistics card (Issue #850 U5): the front page a non-subject
/// guardian sees in place of the subject's own-voice Today screen.
///
/// It carries only what a guardian looking after someone else's record
/// needs at a glance: the subject's first name, the next-period estimate
/// (with the existing tier vocabulary), the PMS window when one exists, a
/// bounded "last logged" age and author, a tag *count* and a note
/// present/absent boolean, an unstocked-supplies count, and the quick
/// actions. It is deliberately "counts, not content" (plan D-3): it names
/// no symptom, tag code, or note text — the activity feed's discipline
/// (`lib/ui/sharing/activity_feed_screen.dart:301-327`). Tags and notes are
/// one tap in (the day sheet), not on the card.
///
/// Presentation only (D-8): the lens never changes permission. A `viewer`
/// (a role that cannot log) gets the card with no actions; every logging
/// role gets them. Everything reads third-person
/// (`docs/product/voice-and-copy.md` rule 2) — "last logged … by you" is
/// the one place "you" is correct, since that *is* the reader.
///
/// The "last logged" read is a bounded single-row query through the narrow
/// [LatestDayEntryReader] seam, never a second full-history subscription
/// (plan open question 7).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/activity_actor_copy.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/l10n/tiers.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

/// The subject's first name from a profile display name: the text before the
/// first whitespace, trimmed. An empty/whitespace-only name yields the empty
/// string so the caller can substitute a neutral fallback rather than
/// rendering a leading apostrophe.
String firstNameOf(String displayName) {
  final trimmed = displayName.trim();
  final space = trimmed.indexOf(' ');
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

class GuardianOverviewCard extends StatefulWidget {
  const GuardianOverviewCard({
    super.key,
    required this.profileId,
    required this.subjectName,
    required this.prediction,
    required this.today,
    required this.guardians,
    required this.currentUserId,
    required this.canAct,
    required this.onAddNote,
    this.onOpenCare,
    this.onOpenSupplies,
  });

  final String profileId;

  /// The profile's display name; only the first name renders.
  final String subjectName;

  /// The same prediction stream the subject lens renders.
  final CyclePrediction prediction;

  /// Device-local "today", for the last-logged age.
  final LocalDate today;

  /// Accepted guardians, for resolving the last entry's author through the
  /// activity-feed naming ladder (never a raw uuid).
  final List<ProfileGuardian> guardians;

  final String? currentUserId;

  /// False for a `viewer` (or an archived profile): the actions are hidden.
  final bool canAct;

  /// Opens today's day sheet, where the guardian-note section lives (#801).
  final VoidCallback onAddNote;

  /// Opens the shared care screen; null when the tree has no care
  /// repository/repository wiring to reach it.
  final VoidCallback? onOpenCare;

  /// Opens the supplies list (a section of the same care screen); null on
  /// the same condition as [onOpenCare].
  final VoidCallback? onOpenSupplies;

  @override
  State<GuardianOverviewCard> createState() => _GuardianOverviewCardState();
}

class _GuardianOverviewCardState extends State<GuardianOverviewCard> {
  bool _loadedLatest = false;
  DayEntry? _latest;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLatest());
  }

  /// The bounded latest-entry read. A repository that does not implement
  /// [LatestDayEntryReader] (a hand-rolled test fake) leaves this null, so
  /// the card renders the "nothing logged yet" state instead of subscribing
  /// to the full history.
  Future<void> _loadLatest() async {
    final entries = Provider.of<DayEntriesRepository?>(context, listen: false);
    // `is` alone does not promote across two unrelated interfaces
    // (DayEntriesRepository is not a subtype of LatestDayEntryReader), so
    // the capability is cast explicitly.
    final reader = entries is LatestDayEntryReader
        ? entries as LatestDayEntryReader
        : null;
    final entry = reader == null
        ? null
        : await reader.latestEntryFor(widget.profileId);
    if (!mounted) return;
    setState(() {
      _latest = entry;
      _loadedLatest = true;
    });
  }

  String _name(AppLocalizations l10n) {
    final first = firstNameOf(widget.subjectName);
    return first.isEmpty ? l10n.guardianOverviewThisProfile : first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final name = _name(l10n);
    return Card(
      key: const ValueKey('guardian-overview-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.guardianOverviewLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: LLSpace.space1),
            Text(
              name,
              key: const ValueKey('guardian-overview-subject'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: LLSpace.space2),
            _estimateLine(context, theme, l10n, name),
            ?_pmsLine(context, theme, l10n, name),
            const SizedBox(height: LLSpace.space2),
            _lastLoggedLine(theme, l10n),
            _countsLine(theme, l10n),
            _suppliesLine(theme, l10n),
            if (widget.canAct) _actions(theme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _estimateLine(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    String name,
  ) {
    final prediction = widget.prediction;
    final text = switch (prediction) {
      ActivePrediction() => l10n.guardianOverviewNextPeriod(
        name,
        estimateDateText(prediction, dates.calendarLocale(context)),
        tierLabel(l10n, prediction.tier),
      ),
      NotEnoughHistory() => l10n.guardianOverviewNoEstimate(name),
      PredictionsSuppressed() => l10n.guardianOverviewPredictionsOff,
      PredictionsDisabled() => l10n.guardianOverviewPredictionsOff,
    };
    return Text(
      text,
      key: const ValueKey('guardian-overview-estimate'),
      style: theme.textTheme.bodyMedium,
    );
  }

  Widget? _pmsLine(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    String name,
  ) {
    final prediction = widget.prediction;
    if (prediction is! ActivePrediction) return null;
    final pms = prediction.pms;
    if (pms == null) return null;
    String format(LocalDate date) => dates.formatLocalDateMonthDayYear(
      date,
      locale: dates.calendarLocale(context),
    );
    return Padding(
      padding: const EdgeInsets.only(top: LLSpace.space1),
      child: Text(
        l10n.guardianOverviewPmsWindow(
          name,
          '${format(pms.predictedStart)} – ${format(pms.predictedEnd)}',
        ),
        key: const ValueKey('guardian-overview-pms'),
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Widget _lastLoggedLine(ThemeData theme, AppLocalizations l10n) {
    if (!_loadedLatest) return const SizedBox.shrink();
    final style = theme.textTheme.bodySmall;
    final entry = _latest;
    if (entry == null) {
      return Text(
        l10n.guardianOverviewNeverLogged,
        key: const ValueKey('guardian-overview-last-logged'),
        style: style,
      );
    }
    final rawDays = widget.today.difference(entry.localDate);
    final days = rawDays < 0 ? 0 : rawDays;
    final actor =
        activityActorLabel(
          l10n,
          entry.loggedByUserId,
          widget.currentUserId,
          widget.guardians,
        ) ??
        l10n.activityActorGuardianFallback;
    return Text(
      l10n.guardianOverviewLastLogged(days, actor),
      key: const ValueKey('guardian-overview-last-logged'),
      style: style,
    );
  }

  /// Tag count and note-present boolean for the latest entry — never a tag
  /// code, label, or note text (D-3).
  Widget _countsLine(ThemeData theme, AppLocalizations l10n) {
    final entry = _latest;
    if (!_loadedLatest || entry == null) return const SizedBox.shrink();
    final tagCount = entry.tags.length;
    final hasNote = entry.note != null && entry.note!.trim().isNotEmpty;
    final style = theme.textTheme.bodySmall;
    if (tagCount == 0 && !hasNote) {
      return Padding(
        padding: const EdgeInsets.only(top: LLSpace.space1),
        child: Text(
          l10n.guardianOverviewNoDetails,
          key: const ValueKey('guardian-overview-counts'),
          style: style,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LLSpace.space1),
      child: Wrap(
        spacing: LLSpace.space3,
        runSpacing: LLSpace.space1,
        children: [
          if (tagCount > 0)
            Text(
              l10n.guardianOverviewTagCount(tagCount),
              key: const ValueKey('guardian-overview-tag-count'),
              style: style,
            ),
          if (hasNote)
            Text(
              l10n.guardianOverviewNotePresent,
              key: const ValueKey('guardian-overview-note-present'),
              style: style,
            ),
        ],
      ),
    );
  }

  Widget _suppliesLine(ThemeData theme, AppLocalizations l10n) {
    final repository = Provider.of<CareContentRepository?>(
      context,
      listen: false,
    );
    if (repository == null) return const SizedBox.shrink();
    return StreamBuilder<List<VisitPrepItem>>(
      stream: repository.watchSupplyItems(widget.profileId),
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (items == null) return const SizedBox.shrink();
        final unstocked = items.where((item) => !item.isChecked).length;
        return Padding(
          padding: const EdgeInsets.only(top: LLSpace.space1),
          child: Text(
            unstocked == 0
                ? l10n.guardianOverviewSuppliesStocked
                : l10n.guardianOverviewSuppliesUnstocked(unstocked),
            key: const ValueKey('guardian-overview-supplies'),
            style: theme.textTheme.bodySmall,
          ),
        );
      },
    );
  }

  Widget _actions(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: LLSpace.space3),
      child: Wrap(
        spacing: LLSpace.space2,
        runSpacing: LLSpace.space1,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('guardian-overview-action-note'),
            onPressed: widget.onAddNote,
            icon: const Icon(Icons.edit_note, size: 18),
            label: Text(l10n.guardianOverviewActionNote),
          ),
          if (widget.onOpenCare != null)
            OutlinedButton.icon(
              key: const ValueKey('guardian-overview-action-care'),
              onPressed: widget.onOpenCare,
              icon: const Icon(Icons.medical_information_outlined, size: 18),
              label: Text(l10n.guardianOverviewActionCare),
            ),
          if (widget.onOpenSupplies != null)
            OutlinedButton.icon(
              key: const ValueKey('guardian-overview-action-supplies'),
              onPressed: widget.onOpenSupplies,
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: Text(l10n.guardianOverviewActionSupplies),
            ),
        ],
      ),
    );
  }
}
