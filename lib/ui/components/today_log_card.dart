/// The Today screen's log card (issue #1489): one card, under the estimate,
/// that says what is logged for today.
///
/// Today used to show the estimate and nothing about the day's own log, so
/// a person who had logged cramps that morning opened the app to a screen
/// that looked the same as if they had logged nothing. This card is the
/// answer the screen was missing: the flow, the tags by the labels the day
/// sheet shows, and whether there is a note.
///
/// Like [TodayCard] it is handed plain values and a callback and never
/// talks to a repository: [OverviewPanel] watches today's entry, turns it
/// into a [TodayLogSummary] with [todayLogSummaryOf], and owns the action.
///
/// **The note's text never reaches this file.** A [TodayLogSummary] carries
/// only the fact that a note exists ([TodayLogSummary.hasNote]), so no path
/// through this widget — the visible lines or the screen-reader label — can
/// show what the note says.
///
/// For the person who logs only. A guardian's front page is
/// `GuardianOverviewCard`, which shows counts and never content (#850).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart'
    show formatMeasurementValue, localizedFlowLabel;

import '../theme/tokens.dart';

/// The most tags the card names before it says "and N more".
const int kTodayLogMaxTags = 6;

/// What the card says about a day that has something logged, already in
/// the reader's words. Holds labels and facts only — never a tag code, and
/// never the note's text.
class TodayLogSummary {
  const TodayLogSummary({
    this.flow,
    this.tags = const [],
    this.details = const [],
    this.hasNote = false,
  });

  /// The flow line ("Medium flow", "Spotting", "Not bleeding"), or null
  /// when the day records no flow.
  final String? flow;

  /// Every tag's label, in the order the entry stores them. The card shows
  /// the first [kTodayLogMaxTags] and counts the rest.
  final List<String> tags;

  /// The lines for what the day holds besides flow, tags and a note: the
  /// PMS marker and the temperature and weight readings.
  final List<String> details;

  /// Whether the day has a note.
  final bool hasNote;
}

/// The summary of [log] for the card, or null when nothing is logged
/// ([TodayLog.hasContent]) and the card should say so instead.
///
/// The words are the app's own: flow through [localizedFlowLabel] and the
/// calendar's "{level} flow"; tags through [tagDisplayLabel], the day
/// sheet's own resolver, so a custom tag reads by the name it was given
/// ([customTags] is the profile's registry); the PMS marker and the
/// readings by the day sheet's labels, in [bbtUnit] and [weightUnit].
TodayLogSummary? todayLogSummaryOf(
  TodayLog log, {
  required AppLocalizations l10n,
  Iterable<CustomTag> customTags = const [],
  BbtUnit bbtUnit = BbtUnit.celsius,
  WeightUnit weightUnit = WeightUnit.kg,
}) {
  final entry = log.entry;
  if (entry == null || !log.hasContent) return null;
  return TodayLogSummary(
    flow: _flowLine(log, entry, l10n),
    tags: [for (final code in entry.tags) tagDisplayLabel(code, customTags)],
    details: [
      if (entry.pms) l10n.daySheetPmsChip,
      if (log.bbt case final reading?)
        _readingLine(
          l10n.daySheetBbtFieldLabel(bbtUnitSymbol(bbtUnit)),
          convertTemperature(
            reading.valueNum!,
            from: BbtUnit.fromDb(reading.unit),
            to: bbtUnit,
          ),
        ),
      if (log.weight case final reading?)
        _readingLine(
          l10n.daySheetWeightFieldLabel(weightUnitSymbol(weightUnit)),
          convertWeight(
            reading.valueNum!,
            from: WeightUnit.fromDb(reading.unit),
            to: weightUnit,
          ),
        ),
    ],
    hasNote: log.hasNote,
  );
}

/// A bleed level reads "{level} flow", as the calendar says it. Bleed wins
/// over spotting, as on the calendar (issue #761). Otherwise a spotting
/// record reads "Spotting" — the entry's own flow says "not bleeding" on
/// such a day, which is the one thing it was not — and an explicit "not
/// bleeding" reads as itself. No flow at all is left out.
String? _flowLine(TodayLog log, DayEntry entry, AppLocalizations l10n) {
  final flow = entry.flow;
  if (isBleed(flow)) {
    return l10n.calendarCellFlowState(localizedFlowLabel(flow, l10n));
  }
  if (log.hasSpotting) return l10n.flowLevelSpotting;
  return flow == FlowLevel.none ? null : localizedFlowLabel(flow, l10n);
}

/// A reading under the day sheet's own field label: "BBT (°C): 36.7".
String _readingLine(String label, double value) =>
    '$label: ${formatMeasurementValue(value)}';

/// The card's lines for [summary], top to bottom. Also what the
/// screen-reader label is built from, so the two cannot say different
/// things.
List<String> todayLogLines(TodayLogSummary summary, AppLocalizations l10n) => [
      ?summary.flow,
      if (summary.tags.isNotEmpty) _tagsLine(summary.tags, l10n),
      ...summary.details,
      if (summary.hasNote) l10n.todayLogNoteAdded,
    ];

/// The first [kTodayLogMaxTags] labels, then "and N more".
String _tagsLine(List<String> tags, AppLocalizations l10n) {
  final shown = tags.take(kTodayLogMaxTags).join(', ');
  final more = tags.length - kTodayLogMaxTags;
  return more > 0 ? '$shown ${l10n.todayLogMoreTags(more)}' : shown;
}

class TodayLogCard extends StatelessWidget {
  const TodayLogCard({
    super.key,
    required this.summary,
    required this.canEdit,
    required this.onEdit,
  });

  /// What is logged today, or null when nothing is.
  final TodayLogSummary? summary;

  /// False for someone who cannot log (a `viewer`, or an archived profile):
  /// the summary shows without the action, rather than with it disabled.
  final bool canEdit;

  /// Opens today's day sheet. Not offered when nothing is logged: the
  /// floating button is the action then.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return Card(
      key: const ValueKey('today-log-card'),
      child: summary == null ? _empty(context) : _logged(context, summary),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(LLSpace.space4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          AppLocalizations.of(context).todayLogEmpty,
          key: const ValueKey('today-log-empty'),
          // De-emphasised copy takes `onSurfaceVariant`, as the reminder
          // hint under this card does (#162).
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _logged(BuildContext context, TodayLogSummary summary) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final lines = todayLogLines(summary, l10n);
    return Padding(
      // The Edit button brings its own 48dp tap target and its own inset,
      // so the card gives up most of its top and end padding to it: the
      // title then sits within 2dp of where it does in the card without the
      // button, and the button's label ends on the card's 16dp gutter.
      padding: canEdit
          ? const EdgeInsetsDirectional.fromSTEB(
              LLSpace.space4,
              LLSpace.space1,
              LLSpace.space1,
              LLSpace.space4,
            )
          : const EdgeInsets.all(LLSpace.space4),
      // One node reads the whole summary as a sentence; the lines under it
      // are excluded so a screen reader does not then read them again one
      // by one. The Edit button stays a node of its own inside it.
      child: Semantics(
        container: true,
        label: l10n.todayLogSemantics(
          lines.map((line) => '$line.').join(' '),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A Wrap, not a Row: at large text sizes the button moves under
            // the title instead of squeezing it (the estimate row's own
            // answer to the same problem, #836).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: LLSpace.space2,
              children: [
                ExcludeSemantics(
                  child: Text(
                    l10n.todayLogTitle,
                    key: const ValueKey('today-log-title'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (canEdit)
                  TextButton(
                    key: const ValueKey('today-log-edit'),
                    // A 48dp square at least, not the default 64dp-wide
                    // minimum: "Edit" is shorter than that minimum, which
                    // centred the word and left it short of the gutter.
                    style: TextButton.styleFrom(
                      minimumSize: const Size.square(LLSpace.space7),
                    ),
                    onPressed: onEdit,
                    child: Text(l10n.todayLogEdit),
                  ),
              ],
            ),
            ExcludeSemantics(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  top: canEdit ? 0 : LLSpace.space1,
                  end: canEdit ? LLSpace.space3 : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, line) in lines.indexed)
                      Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : LLSpace.space1,
                        ),
                        child: Text(
                          line,
                          key: ValueKey('today-log-line-$index'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
