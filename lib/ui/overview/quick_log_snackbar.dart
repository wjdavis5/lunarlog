/// The confirmation shown after a "Period started today" quick log — the
/// Today card's tap (`OverviewPanel`) and the home-screen widget's
/// (`lib/app.dart`, issue #1016) both build it here, so the two can never
/// say different things about the same write.
///
/// Issue #1412: the message used to read "Recorded a medium-flow period
/// start for today" whatever happened. `quickLogFlowLevel` never lowers a
/// day already logged at medium flow or heavier, so on such a day the tap
/// leaves the flow exactly as it was; the snackbar now says that, and
/// offers no Undo because there is nothing to undo.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/logging/quick_log.dart'
    show quickLogChangesFlow;
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Builds the quick-log confirmation for a day whose flow was
/// [previousFlow] before the tap (null when the day had no entry).
///
/// * The tap created the entry or raised it to the quick-log level →
///   the "recorded" message with an Undo action wired to [onUndo].
/// * The day was already at or above that level → the "already logged"
///   message, without Undo.
///
/// [contentKey] keys the message `Text` (each caller keeps its own key).
SnackBar quickLogSnackBar({
  required AppLocalizations l10n,
  required FlowLevel? previousFlow,
  required Key contentKey,
  required VoidCallback onUndo,
}) {
  if (!quickLogChangesFlow(previousFlow)) {
    return SnackBar(
      content: Text(l10n.overviewAlreadyLoggedSnackbar, key: contentKey),
    );
  }
  return SnackBar(
    content: Text(l10n.overviewLoggedSnackbar, key: contentKey),
    action: SnackBarAction(label: l10n.overviewUndo, onPressed: onUndo),
  );
}
